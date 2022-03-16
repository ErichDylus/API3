//SPDX-License-Identifier: MIT
/**** IN PROCESS AND INCOMPLETE
***** this code and any deployments of this code are strictly provided as-is; no guarantee, representation or warranty is being made, express or implied, as to the safety or correctness of the code 
***** or any smart contracts or other software deployed from these files, in accordance with the disclosures and licenses found here: https://github.com/ErichDylus/API3/blob/main/contracts/README.md
***** this code is not audited, and users, developers, or adapters of these files should proceed with caution and use at their own risk.
****/
pragma solidity >=0.8.9;

/// IN PROCESS AND INCOMPLETE, unaudited and for demonstration only, subject to all disclosures, licenses, and caveats of the open-source-law repo
/// @title Airnode Prediction Market
// Prediction market judged by an Airnode RRP call, loosely based on https://gist.github.com/0xfoobar/c7f620e62339b0e7d201cb64f5042eef
import "@api3/airnode-protocol/contracts/rrp/requesters/RrpRequester.sol";

interface IERC20 { 
    function approve(address spender, uint256 amount) external returns (bool); 
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

contract AirnodePredictionMarket is RrpRequester {
    
  address escrowAddress;
  address partyA;
  address partyB;
  uint256 expiryTime;
  uint256 nextPredictionId;
  bool isExpired;
  bool isClosed;
  IERC20 public ierc20;
  string description;
  mapping(address => bool) public parties; //map whether an address is a party to the transaction for restricted() modifier 
  mapping(bytes32 => bool) public incomingFulfillments;
  mapping(bytes32 => int256) public fulfilledData;
  mapping(uint256 => Prediction) public predictions;

  enum Status {
        Offered,
        Accepted,
        Settled
    }
  enum Outcome {
        A,
        B,
        Neutral
    }

  struct Prediction {
        uint256 id;
        uint256 amount;
        address partyA;
        address partyB;
        address airnodeResolver;
        IERC20 token;
        Status status;
    }
  
  event DealExpired(bool isExpired);
  event DealClosed(bool isClosed, uint256 effectiveTime); //event provides exact blockstamp Unix time of closing and oracle information
  event PredictionOffer(uint256 predictId);

  error BuyerAddress();
  error Expired();
  error NotApproved();
  error OnlyBuyer();
  error OracleConditionNotSatisfied();
  
  modifier restricted() { 
    require(parties[msg.sender], "Only parties[]");
    _;
  }
  
  /// @notice deployer (buyer) initiates escrow with description, deposit amount in USD, address of stablecoin, seconds until expiry, and designate recipient seller
  /// @param _description should be a brief identifier of the deal in question - perhaps as to parties/underlying asset/documentation reference/hash 
  /// @param _deposit is the purchase price which will be deposited in the smart escrow contract
  /// @param _seller is the seller's address, who will receive the purchase price if the deal closes
  /// @param _stablecoin is the token contract address for the stablecoin to be sent as deposit
  /// @param _secsUntilExpiry is the number of seconds until the deal expires, which can be converted to days for front end input or the code can be adapted accordingly
  /// @param _airnodeRrp is the public address of the AirnodeRrp.sol protocol contract on the relevant blockchain used for this contract; see: https://docs.api3.org/airnode/v0.2/reference/airnode-addresses.html
  constructor(string memory _description, uint256 _secsUntilExpiry, address _partyB, address _stablecoin, address _airnodeRrp) RrpRequester(_airnodeRrp) {
      if (_partyB == msg.sender) revert BuyerAddress();
      partyA = address(msg.sender);
      escrowAddress = address(this);
      ierc20 = IERC20(_stablecoin);
      description = _description;
      partyB = _partyB;
      parties[msg.sender] = true;
      parties[_partyB] = true;
      parties[escrowAddress] = true;
      expiryTime = block.timestamp + _secsUntilExpiry;
  }
  
    function offerPrediction(address _partyB, address _airnodeResolver, IERC20 token, uint256 amount) external {
        IERC20(token).transferFrom(msg.sender, escrowAddress, amount); // OFFEROR MUST FIRST SEPARATELY APPROVE ESCROWADDRESS FOR AMOUNT
        Prediction memory prediction = Prediction({
            id: nextPredictionId,
            amount: amount,
            partyA: msg.sender,
            partyB: _partyB,
            airnodeResolver: _airnodeResolver,
            token: token,
            status: Status.Offered
        });

        predictions[nextPredictionId] = prediction;
        emit PredictionOffered(nextPredictionId);
        unchecked { nextPredictionId += 1; }
    }

    function withdrawOffer(uint256 predictionId) external {
        Prediction memory prediction = predictions[predictionId];
        require(msg.sender == prediction.partyA, "Not the offer creator");
        require(prediction.status == Status.Offered, "Not offered");
        IERC20 _token = prediction.token;
        uint256 _amount = prediction.amount;
        delete predictions[predictionId];
        _token.transfer(msg.sender, _amount); // refund partyA
    }

    function acceptPrediction(uint predictionId) external {
        Prediction memory prediction = predictions[predictionId];
        require(msg.sender == prediction.partyB, "Not the offer recipient");
        require(prediction.status == Status.Offered, "Not offered");

        prediction.token.transferFrom(msg.sender, address(this), prediction.amount);
        predictions[predictionId].status = Status.Accepted;
    }

    function settlePrediction(uint predictionId, Outcome outcome) external {
        Prediction memory prediction = predictions[predictionId];
        require(msg.sender == prediction.airnodeResolver, "Not the airnodeResolver");
        require(prediction.status == Status.Accepted, "Not accepted");

        if (outcome == Outcome.A) {
            prediction.token.transfer(prediction.partyA, 2 * prediction.amount);
        } else if (outcome == Outcome.B) {
            prediction.token.transfer(prediction.playerB, 2 * prediction.amount);
        } else if (outcome == Outcome.Neutral) {
            prediction.token.transfer(prediction.playerA, prediction.amount);
            prediction.token.transfer(prediction.playerB, prediction.amount);
        }

        predictions[predictionId].status = Status.Settled;
    }
  
  /// @notice check if expired, and if so, return balance to buyer 
  function checkIfExpired() external returns(bool) {
        if (expiryTime <= block.timestamp) {
            isExpired = true;
            _returnDeposit(); 
            emit DealExpired(true);
        } else {
            isExpired = false;
        }
        return(isExpired);
    }
    
  /// @notice for seller to check if deposit is in escrowAddress
  function checkBalance() external restricted view returns(uint256) {
      return ierc20.balanceOf(escrowAddress);
  }
  
  /// @notice call the airnode which will provide a boolean response
  /// @dev inbound API parameters which may already be ABI encoded. Source: https://docs.api3.org/airnode/v0.2/grp-developers/call-an-airnode.html
  /// @param airnode the address of the relevant API provider's airnode
  /// @param endpointId identifier for the specific endpoint desired to access via the airnode
  /// @param sponsor address of the entity that pays for the fulfillment of a request & gas costs the Airnode will incur. These costs will be withdrawn from the sponsorWallet of the Airnode when the requester calls it.
  /// @param sponsorWallet the wallet created via mnemonic by the sponsor with the Admin CLI, funds within used by the airnode to pay gas. See https://docs.api3.org/airnode/v0.2/grp-developers/requesters-sponsors.html#what-is-a-sponsor
  /// @param parameters specify the API and reserved parameters (see Airnode ABI specifications at https://docs.api3.org/airnode/v0.2/reference/specifications/airnode-abi-specifications.html for how these are encoded)
  function callAirnode(address airnode, bytes32 endpointId, address sponsor, address sponsorWallet, bytes calldata parameters) external {
      bytes32 requestId = airnodeRrp.makeFullRequest( // Make the Airnode request
          airnode,                        
          endpointId,                     
          sponsor,                        
          sponsorWallet,                  
          address(this),                  
          this.fulfill.selector,  
          parameters                      
          );
      incomingFulfillments[requestId] = true;
  }

  /// @dev the AirnodeRrp.sol protocol contract will callback here to fulfill the request
  /// @param requestId generated when making the request and passed here as a reference to identify which request the response is for
  /// @param data for a successful response, the requested data which has been encoded. Decode by the function decode() from the abi object
  function fulfill(bytes32 requestId, bytes calldata data) external onlyAirnodeRrp {
      require(incomingFulfillments[requestId], "No Request");
      delete incomingFulfillments[requestId];
      int256 _decodedData = abi.decode(data, (int256));
      fulfilledData[requestId] = _decodedData;
      _closeDeal(_decodedData);
  }
}
