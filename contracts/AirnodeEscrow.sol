//SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

/// IN PROCESS AND INCOMPLETE, unaudited and for demonstration only, subject to all disclosures, licenses, and caveats of the open-source-law repo
/// @author Erich Dylus
/// @title Airnode Escrow
/// @notice create a simple smart escrow contract, with an ERC20 stablecoin as payment, expiration denominated in seconds, deposit refunded if contract expires before closeDeal() called, contingent on a boolean Airnode response
/// @dev intended to be deployed by buyer (as they will separately approve() the contract address for the deposited funds, and deposit is returned to deployer if expired); may be forked/altered for separation of deposit from purchase price, deposit non-refundability, etc.

import "@api3/airnode-protocol/contracts/rrp/requesters/RrpRequester.sol";

interface IERC20 { 
    function approve(address spender, uint256 amount) external returns (bool); 
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

interface AirnodeRRP {
    function makeFullRequest(address airnode, bytes32 endpointId, address sponsor, address sponsorWallet, address fulfillAddress, bytes4 fulfillFunctionId, bytes calldata parameters) external returns (bytes32 requestId);
    function makeTemplateRequest(bytes32 templateId, address sponsor, address sponsorWallet, address fulfillAddress, bytes4 fulfillFunctionId, bytes calldata parameters) external returns (bytes32 requestId);
}

contract AirnodeEscrow {
    
  address escrowAddress;
  address payable buyer;
  address payable seller;
  address stablecoin;
  address airnodeRRP;
  uint256 deposit;
  uint256 effectiveTime;
  uint256 expirationTime;
  bool sellerApproved;
  bool buyerApproved;
  bool isExpired;
  bool isClosed;
  IERC20 public ierc20;
  string description;
  mapping(address => bool) public parties; //map whether an address is a party to the transaction for restricted() modifier 
  
  event DealExpired(bool isExpired);
  event DealClosed(bool isClosed, uint256 effectiveTime); //event provides exact blockstamp Unix time of closing and oracle information
  
  modifier restricted() { 
    require(parties[msg.sender], "This may only be called by a party to the deal or the by escrow contract");
    _;
  }
  
  /// @notice deployer (buyer) initiates escrow with description, deposit amount in USD, address of stablecoin, seconds until expiry, and designate recipient seller
  /// @param _description should be a brief identifier of the deal in question - perhaps as to parties/underlying asset/documentation reference/hash 
  /// @param _deposit is the purchase price which will be deposited in the smart escrow contract
  /// @param _seller is the seller's address, who will receive the purchase price if the deal closes
  /// @param _stablecoin is the token contract address for the stablecoin to be sent as deposit
  /// @param _secsUntilExpiration is the number of seconds until the deal expires, which can be converted to days for front end input or the code can be adapted accordingly
  constructor(string memory _description, uint256 _deposit, address payable _seller, address _stablecoin, uint256 _secsUntilExpiration) payable {
      require(_seller != msg.sender, "Designate different party as seller");
      buyer = payable(address(msg.sender));
      deposit = _deposit;
      escrowAddress = address(this);
      stablecoin = _stablecoin;
      ierc20 = IERC20(stablecoin);
      description = _description;
      seller = _seller;
      parties[msg.sender] = true;
      parties[_seller] = true;
      parties[escrowAddress] = true;
      expirationTime = block.timestamp + _secsUntilExpiration;
  }
  
  /// @notice buyer may confirm seller's recipient address as extra security measure or change seller address
  /// @param _seller is the new recipient address of seller
  function designateSeller(address payable _seller) external restricted {
      require(_seller != seller, "Party already designated as seller");
      require(_seller != buyer, "Buyer cannot also be seller");
      require(!isExpired, "Too late to change seller");
      parties[_seller] = true;
      seller = _seller;
  }
  
  /// ********* DEPLOYER MUST SEPARATELY APPROVE (by interacting with the ERC20 contract in question's approve()) this contract address for the deposit amount (keep decimals in mind) ********
  /// @notice buyer deposits in escrowAddress after separately ERC20-approving escrowAddress
  function depositInEscrow() public restricted returns(bool, uint256) {
      require(msg.sender == buyer, "Only buyer may deposit in escrow");
      ierc20.transferFrom(buyer, escrowAddress, deposit);
      return (true, ierc20.balanceOf(escrowAddress));
      
  }
  
  /// @notice escrowAddress returns deposit to buyer
  function returnDeposit() internal returns(bool, uint256) {
      ierc20.transfer(buyer, deposit);
      return (true, ierc20.balanceOf(escrowAddress));
  }
  
  /// @notice escrowAddress sends deposit to seller
  function paySeller() internal returns(bool, uint256) {
      ierc20.transfer(seller, deposit);
      return (true, ierc20.balanceOf(escrowAddress));
  } 
  
  /// @notice check if expired, and if so, return balance to buyer 
  function checkIfExpired() external returns(bool){
        if (expirationTime <= uint256(block.timestamp)) {
            isExpired = true;
            returnDeposit(); 
            emit DealExpired(isExpired);
        } else {
            isExpired = false;
        }
        return(isExpired);
    }
    
  /// @notice for seller to check if deposit is in escrowAddress
  function checkEscrow() external restricted view returns(uint256) {
      return ierc20.balanceOf(escrowAddress);
  }

  /// if buyer wishes to initiate dispute over seller breach of off chain agreement or repudiate, simply may wait for expiration without sending deposit nor calling this function
  function readyToClose() external restricted returns(string memory){
         if (msg.sender == seller) {
            sellerApproved = true;
            return("Seller is ready to close.");
        } else if (msg.sender == buyer) {
            buyerApproved = true;
            return("Buyer is ready to close.");
        } else {
            return("You are neither buyer nor seller.");
        }
  }
  
  /// @notice call the airnode which will provide a boolean response
  /// @dev inbound API parameters which may already be ABI encoded. Source: https://docs.api3.org/airnode/v0.2/grp-developers/call-an-airnode.html
  function callAirnode(address airnode, bytes32 endpointId, address sponsor, address sponsorWallet, bytes calldata parameters) external {
      bytes32 requestId = airnode.makeFullRequest( // Make the Airnode request
          airnode,                        // airnode
          endpointId,                     // endpointId
          sponsor,                        // sponsor's address
          sponsorWallet,                  // sponsorWallet
          address(this),                  // fulfillAddress
          this.airnodeCallback.selector,  // fulfillFunctionId
          parameters                      // API parameters
          );
      incomingFulfillments[requestId] = true;
  }

  /// @dev the AirnodeRrp.sol protocol contract will callback here
  function airnodeCallback(bytes32 requestId, bytes calldata data) external {
      require(incomingFulfillments[requestId], "No such request made");
      delete incomingFulfillments[requestId];
      bool decodedData = abi.decode(data, (bool));
      fulfilledData[requestId] = decodedData;
  }
    
  /// @notice checks if both buyer and seller are ready to close and expiration has not been met; if so, escrowAddress closes deal and pays seller; if not, deposit returned to buyer
  /// @dev if properly closes, emits event with effective time of closing
  function closeDeal() public returns(bool){
      require(sellerApproved && buyerApproved, "Parties are not ready to close.");
      if (expirationTime <= uint256(block.timestamp)) {
            isExpired = true;
            returnDeposit();
            emit DealExpired(isExpired);
        } else {
            isClosed = true;
            paySeller();
            effectiveTime = uint256(block.timestamp); // effective time of closing upon payment to seller
            emit DealClosed(isClosed, effectiveTime);
        }
        return(isClosed);
  }
}
