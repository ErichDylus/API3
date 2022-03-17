//SPDX-License-Identifier: MIT
/**** IN PROCESS AND INCOMPLETE
***** this code and any deployments of this code are strictly provided as-is; no guarantee, representation or warranty is being made, express or implied, as to the safety or correctness of the code 
***** or any smart contracts or other software deployed from these files, in accordance with the disclosures and licenses found here: https://github.com/ErichDylus/API3/blob/main/contracts/README.md
***** this code is not audited, and users, developers, or adapters of these files should proceed with caution and use at their own risk.
****/
pragma solidity >=0.8.9;

/// IN PROCESS AND INCOMPLETE, unaudited and for demonstration only, subject to all disclosures, licenses, and caveats of the open-source-law repo
/// @title Airnode Prediction Market
/// Prediction market judged by an Airnode RRP call, loosely based on https://gist.github.com/0xfoobar/c7f620e62339b0e7d201cb64f5042eef
/// TODO: support ETH/native gas tokens in addition to ERC20 tokens

import "https://github.com/api3dao/airnode/blob/master/packages/airnode-protocol/contracts/rrp/requesters/RrpRequester.sol";

interface IERC20 { 
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

contract AirnodePredictionMarket is RrpRequester {
    
  address partyA;
  uint256 expiryTime;
  uint256 nextPredictionId;
  mapping(bytes32 => bool) public incomingFulfillments;
  mapping(bytes32 => int256) public fulfilledData;
  mapping(uint256 /* predictionId */ => bool) outcome;
  mapping(uint256 /* predictionId */ => Prediction) public predictionList;

  enum Status {
        Offered,
        Accepted,
        Settled
    }

  struct Prediction {
        uint256 id;
        uint256 amount;
        address partyA;
        address partyB;
        address airnodeResolver;
        string description;
        IERC20 token;
        Status status;
    }
  
  event Expired();
  event DealClosed(bool isClosed, uint256 effectiveTime); //event provides exact blockstamp Unix time of closing and oracle information
  event PredictionOffer(uint256 predictId);

  error HasExpired();
  error NotAccepted();
  error NotAirnodeResolver();
  error NotOffered();
  error NotOfferee();
  error NotOfferor();
  error OracleConditionNotSatisfied();
  error SameAddress();
  
  /// @notice deployer initiates with description of prediction market, seconds until expiry, counterparty, and proper AirnodeRRP protocol contract address 
  /// @param _secsUntilExpiry is the number of seconds until expiry of the proposed prediction market 
  /// @param _airnodeRrpAddr is the public address of the AirnodeRrp.sol protocol contract on the relevant blockchain used for this contract; see: https://docs.api3.org/airnode/v0.2/reference/airnode-addresses.html
  constructor(uint256 _secsUntilExpiry, address _airnodeRrpAddr) RrpRequester(_airnodeRrpAddr) {
      partyA = address(msg.sender);
      expiryTime = block.timestamp + _secsUntilExpiry;
  }
  
    /// @param _partyB  is the counterparty's address for this offer
    /// @param _airnodeResolver is the address of the airnode that will provide the boolean response to resolve the prediction market
    /// @param _description should be a brief identifier or reference to terms of prediction market/agreement
    /// @param _token is the contract address of the token in which the offer is denominated
    /// @param _amount number of tokens for this offer, which partyB will need to match
    function offerPrediction(string memory _description, address _partyB, address _airnodeResolver, IERC20 _token, uint256 _amount) external {
        IERC20(_token).transferFrom(msg.sender, address(this), _amount); // OFFEROR MUST FIRST SEPARATELY APPROVE address(this) FOR AMOUNT
        Prediction memory prediction = Prediction({
            id: nextPredictionId,
            amount: _amount,
            partyA: msg.sender,
            partyB: _partyB,
            airnodeResolver: _airnodeResolver,
            description: _description,
            token: _token,
            status: Status.Offered
        });

        predictionList[nextPredictionId] = prediction;
        emit PredictionOffer(nextPredictionId);
	    unchecked { nextPredictionId += 1; } // will not overflow on human timelines
    }

    /// @param _predictionId prediction offer number
    function withdrawOffer(uint256 _predictionId) external {
        Prediction memory prediction = predictionList[_predictionId];
        if (msg.sender != prediction.partyA) revert NotOfferor();
        if (prediction.status != Status.Offered) revert NotOffered();
        IERC20 _token = prediction.token;
        uint256 _amount = prediction.amount;
        delete predictionList[_predictionId];
        _token.transfer(msg.sender, _amount); // refund partyA
    }

    /// @param _predictionId prediction offer number
    function acceptPrediction(uint256 _predictionId) external {
        Prediction memory prediction = predictionList[_predictionId];
        if (msg.sender != prediction.partyB) revert NotOfferee();
        if (prediction.status != Status.Offered) revert NotOffered();
        prediction.token.transferFrom(msg.sender, address(this), prediction.amount);
        predictionList[_predictionId].status = Status.Accepted;
    }

    /// @dev if not returning a boolean response from airnode, parameters for outcome[] can be designated around fulfilledData[requestId]
    /// @param _predictionId prediction offer number
    function settlePrediction(uint256 _predictionId) external {
        Prediction memory prediction = predictionList[_predictionId];
        if (msg.sender != prediction.airnodeResolver) revert NotAirnodeResolver();
        if (prediction.status != Status.Accepted) revert NotAccepted();
        if (expiryTime <= block.timestamp) { 
            IERC20(prediction.token).transfer(prediction.partyA, prediction.amount);
            IERC20(prediction.token).transfer(prediction.partyB, prediction.amount);
        }
        // call airnode here for outcome[] -- currently hardcoded for partyA to predict true outcome, partyB to predict false
        if (outcome[_predictionId]) {
            IERC20(prediction.token).transfer(prediction.partyA, 2 * prediction.amount);
        } else if (!outcome[_predictionId]) {
            IERC20(prediction.token).transfer(prediction.partyB, 2 * prediction.amount);
        }
        predictionList[_predictionId].status = Status.Settled;
    }
  
  /// @notice call the airnode which will provide a boolean response
  /// @dev inbound API parameters which may already be ABI encoded. Source: https://docs.api3.org/airnode/v0.2/grp-developers/call-an-airnode.html
  /// @param _predictionId prediction offer number
  /// @param endpointId identifier for the specific endpoint desired to access via the airnode
  /// @param sponsor address of the entity that pays for the fulfillment of a request & gas costs the Airnode will incur. These costs will be withdrawn from the sponsorWallet of the Airnode when the requester calls it.
  /// @param sponsorWallet the wallet created via mnemonic by the sponsor with the Admin CLI, funds within used by the airnode to pay gas. See https://docs.api3.org/airnode/v0.2/grp-developers/requesters-sponsors.html#what-is-a-sponsor
  /// @param parameters specify the API and reserved parameters (see Airnode ABI specifications at https://docs.api3.org/airnode/v0.2/reference/specifications/airnode-abi-specifications.html for how these are encoded)
  function callAirnode(uint256 _predictionId, bytes32 endpointId, address sponsor, address sponsorWallet, bytes calldata parameters) external {
	Prediction memory prediction = predictionList[_predictionId];      
	bytes32 requestId = airnodeRrp.makeFullRequest( // Make the Airnode request
          prediction.airnodeResolver,                        
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
  }
}
