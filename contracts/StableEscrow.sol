//SPDX-License-Identifier: MIT

pragma solidity >=0.8.10;

/// unaudited and for demonstration only, provided without warranty of any kind, subject to all disclosures, licenses, and caveats of this repo
/// building at ETHDenver using API3 Beacons powered by Amberdata
/// @title Stable Escrow
/// @notice ERC20 stablecoin smart escrow contract, with a volatility check via Beacon
/// @dev intended to be deployed by buyer (they will separately approve() the contract address for the deposited funds, and deposit is returned to deployer if expired)

interface IERC20 { 
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

interface IRrpBeaconServer { 
    function readBeacon(bytes32 beaconId) external view returns (int224 value, uint32 timestamp);
}

interface ISelfServeRrpBeaconServerWhitelister {
    function whitelistReader(bytes32 beaconId, address reader) external;
}

contract StableEscrow {
    
  bytes32 constant DAIbeaconID = 0x72c512f825577f581e7100dba06031dc34c748e948bb060af51ba76112a9abc0; // this is the same across all chains for Amberdata DAI/USD beacon
  address escrowAddress;
  address buyer;
  address seller;
  uint256 deposit;
  uint256 expiryTime;
  bool sellerApproved;
  bool buyerApproved;
  bool isExpired;
  bool isClosed;
  IERC20 ierc20;
  IRrpBeaconServer ibeacon;
  ISelfServeRrpBeaconServerWhitelister iBeaconWhitelister;
  string description;
  mapping(address => bool) public parties; //map whether an address is a party to the transaction for restricted() modifier 
  
  error BuyerAddress();
  error NotApproved();
  error OnlyBuyer();

  event DealExpired(bool isExpired);
  event UnstableCoin(int224 value, uint256 timestamp);
  event DealClosed(bool isClosed, int224 _value, uint256 effectiveTime); //event provides exact blockstamp time of closing and oracle information
  
  modifier restricted() { 
    require(parties[msg.sender], "Only parties[]");
    _;
  }
  
  /// @notice deployer (buyer) initiates escrow with description, deposit amount in USD, stablecoin contract address, seconds until expiry, and designate recipient seller
  /// @param _description a brief identifier of the deal in question - ex.) parties/underlying asset/documentation reference/hash 
  /// @param _deposit is the purchase price which will be deposited in the smart escrow contract
  /// @param _seller is the seller's address, who will receive the purchase price if the deal closes
  /// @param _stablecoin is the token contract address for the stablecoin to be sent as deposit, blockchain-dependent unlike the beaconID
  /// @param _secsUntilExpiry is the number of seconds until the deal expires, which can be converted to days for front end input or the code can be adapted accordingly
  /// @param _beaconRrp is the public address of the RrpBeaconServer.sol protocol contract on the relevant blockchain used for this contract; see: https://docs.api3.org/beacon/v0.1/reference/contract-addresses.html
  /// @param _selfServeBeaconWhitelister is the public address of the SelfServeRrpBeaconServerWhitelister.sol protocol contract on the relevant blockchain used for this contract; see: https://docs.api3.org/beacon/v0.1/reference/contract-addresses.html
  // Ropsten RrpBeaconServer: 0x2cFda716b751eb406C5124C6E4428F2AEA453D96
  // Ropsten SelfServeRrpBeaconServerWhitelister: 0x7432106a4367e6FfA52c75Cd3535b207C09dd34b
  constructor(string memory _description, uint256 _deposit, uint256 _secsUntilExpiry, address _seller, address _stablecoin, address _beaconRrp, address _selfServeBeaconWhitelister) {
      if (_seller == msg.sender) revert BuyerAddress();
      buyer = msg.sender;
      deposit = _deposit;
      escrowAddress = address(this);
      ierc20 = IERC20(_stablecoin);
      ibeacon = IRrpBeaconServer(_beaconRrp);
      iBeaconWhitelister = ISelfServeRrpBeaconServerWhitelister(_selfServeBeaconWhitelister);
      iBeaconWhitelister.whitelistReader(DAIbeaconID, escrowAddress);
      description = _description;
      seller = _seller;
      parties[msg.sender] = true;
      parties[_seller] = true;
      parties[escrowAddress] = true;
      expiryTime = block.timestamp + _secsUntilExpiry;
  }
  
  /// @notice buyer may confirm seller's recipient address as extra security measure or change seller address
  /// @param _seller is the new recipient address of seller
  function designateSeller(address _seller) external restricted {
      if (_seller == buyer) revert BuyerAddress();
      parties[_seller] = true;
      seller = _seller;
  }
  
  /// @notice buyer deposits in escrowAddress ****** after separately ERC20-approving escrowAddress ****** by calling this function OR simply directly transfers the deposit to escrowAddress
  function depositInEscrow() external returns(bool, uint256) {
      if (msg.sender != buyer) revert OnlyBuyer();
      ierc20.transferFrom(buyer, escrowAddress, deposit);
      return (true, ierc20.balanceOf(escrowAddress));
      
  }
  
  /// @notice escrowAddress returns deposit to buyer
  function _returnDeposit() internal returns(bool, uint256) {
      ierc20.transfer(buyer, deposit);
      return (true, ierc20.balanceOf(escrowAddress));
  }
  
  /// @notice escrowAddress sends deposit to seller
  function _paySeller() internal returns(bool, uint256) {
      ierc20.transfer(seller, deposit);
      return (true, ierc20.balanceOf(escrowAddress));
  } 
  
  /// @notice check if expired, and if so, return balance to buyer 
  function checkIfExpired() external returns(bool) {
        if (expiryTime <= uint256(block.timestamp)) {
            isExpired = true;
            _returnDeposit(); 
            emit DealExpired(isExpired);
        } else {}
        return(isExpired);
    }
    
  /// @notice to check if deposit is in escrowAddress
  function checkEscrow() external view returns(uint256) {
      return ierc20.balanceOf(escrowAddress);
  }

  /// if buyer wishes to initiate dispute over seller breach of off chain agreement or repudiate, simply may wait for expiration without sending deposit nor calling this function
  function readyToClose() external restricted {
        if (msg.sender == seller) {
            sellerApproved = true;
        } else if (msg.sender == buyer) {
            buyerApproved = true;
        }
  }
    
  /// @notice checks if parties are ready to close, if price of DAI is not >3% off $1 peg, and if not expired; if so, escrowAddress closes deal and pays seller; if not, deposit returned to buyer
  /// @dev if properly closes, emits event with effective time of closing
  function closeDeal() external returns(bool, int224) {
        if (!sellerApproved || !buyerApproved) revert NotApproved();
        (int224 _value, uint32 _timestamp) = ibeacon.readBeacon(DAIbeaconID); // hardcoded DAI for testing, could have selection between DAI/USDC/USDT Beacon IDs in future versions
        if (_value < 970000 || _value > 1030000) /* if the DAI price is +- 3% off $1 peg */ {
            _returnDeposit(); // alternatively, could merely alert the parties the stablecoin is off peg, but seller would likely prefer deposit is returned & another token or mechanism used if the peg is lost
            emit UnstableCoin(_value, _timestamp);
        }
        else if (expiryTime <= uint256(block.timestamp)) {
            isExpired = true;
            _returnDeposit();
            emit DealExpired(isExpired);
        } else {
            isClosed = true;
            _paySeller();
            emit DealClosed(isClosed, _value, block.timestamp); // confirmation of deal closing and effective time upon payment to seller
        }
        return(isClosed, _value);
  }
}
