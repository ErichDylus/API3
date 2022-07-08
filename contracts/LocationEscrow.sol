//SPDX-License-Identifier: MIT
/**** 

************** IN PROCESS, INCOMPLETE, DO NOT USE ************************

 ***** TODO: account for (0,0) latitude/longitude
 ***** this code and any deployments of this code are strictly provided as-is; 
 ***** no guarantee, representation or warranty is being made, express or implied, 
 ***** as to the safety or correctness of the code
 ***** or any smart contracts or other software deployed from these files, 
 ***** in accordance with the disclosures and licenses found here: https://github.com/ErichDylus/API3/blob/main/contracts/README.md
 ***** this code is not audited, and users, developers, or adapters of 
 ***** these files should proceed with caution and use at their own risk.
 ****/
pragma solidity >=0.8.9;

/// @title Location Escrow
/** @notice bilateral smart escrow contract, with an ERC20 stablecoin as payment,
 ** expiration denominated in seconds, deposit refunded if contract expires before closeDeal() called,
 ** contingent on Airnode location response (either by radius or within jxn) */
/** @dev buyer should deploy (as they will separately approve() the contract address for the deposited funds,
 ** and deposit is returned to deployer if expired); note https://docs.api3.org/airnode/v0.2/grp-developers/requesters-sponsors.html */

import "https://github.com/api3dao/airnode/blob/master/packages/airnode-protocol/contracts/rrp/requesters/RrpRequesterV0.sol";

interface IERC20 {
    function allowance(address owner, uint256 spender)
        external
        returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address recipient, uint256 amount)
        external
        returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);
}

contract LocationEscrow is RrpRequesterV0 {
    address public buyer;
    address public seller;
    int256 public closingTargetLatitude;
    int256 public closingTargetLongitude;
    uint256 public deposit;
    uint256 public immutable expiryTime;
    uint256 public radius;
    bool isExpired;
    bool isClosed;
    IERC20 public ierc20;
    string description;
    mapping(address => bool) public parties; //map whether an address is a party to the transaction for restricted() modifier
    mapping(bytes32 => bool) public incomingFulfillments;
    mapping(bytes32 => int256) public latitude;
    mapping(bytes32 => int256) public longitude;

    event DealExpired(bool isExpired);
    event DealClosed(
        bool isClosed,
        uint256 effectiveTime,
        int256 latitude,
        int256 longitude
    ); //event provides exact blockstamp Unix time of closing and oracle information

    error BuyerAddress();
    error Expired(uint256 time);
    error FundsNotInEscrow();
    error OnlyBuyer();
    error OracleConditionNotSatisfied();
    error TransferFailed();

    modifier restricted() {
        require(parties[msg.sender], "Only parties[]");
        _;
    }

    /// @notice deployer (buyer) initiates escrow with parameters specified and agreed in underlying legal agreements
    /// @param _description: brief identifier of the deal - perhaps as to parties/underlying asset/documentation reference/hash
    /// @param _deposit: the purchase price which will be deposited in the smart escrow contract
    /// @param _closingTargetLatitude: target asset location latitude coordinate for closing
    /// @param _closingTargetLongitude: target asset location longitude coordinate for closing
    /// @param _radius: maximum permitted number of degrees away from each of _closingTargetLatitude and _closingTargetLongitude for closing
    /// @param _seller: seller's address, who will receive the deposited purchase price if the deal closes
    /// @param _stablecoin: the token contract address for the stablecoin to be sent as deposit
    /// @param _secsUntilExpiry: number of seconds until the deal expires, which can be converted to days for front end input or the code can be adapted accordingly
    /// @param _airnodeRrp: the AirnodeRrp.sol protocol contract address on the relevant blockchain used for this contract; see: https://docs.api3.org/airnode/v0.2/reference/airnode-addresses.html
    constructor(
        string memory _description,
        int256 _closingTargetLatitude,
        int256 _closingTargetLongitude,
        uint256 _deposit,
        uint256 _radius,
        uint256 _secsUntilExpiry,
        address _seller,
        address _stablecoin,
        address _airnodeRrp
    ) RrpRequesterV0(_airnodeRrp) {
        if (_seller == msg.sender) revert BuyerAddress();
        buyer = msg.sender;
        deposit = _deposit;
        ierc20 = IERC20(_stablecoin);
        description = _description;
        seller = _seller;
        closingTargetLatitude = _closingTargetLatitude;
        closingTargetLongitude = _closingTargetLongitude;
        radius = _radius;
        parties[msg.sender] = true;
        parties[_seller] = true;
        parties[address(this)] = true;
        expiryTime = block.timestamp + _secsUntilExpiry;
    }

    /// @notice party may confirm seller's recipient address as extra security measure or change seller address
    /// @param _seller: the new recipient address of seller
    function designateSeller(address _seller) external restricted {
        if (_seller == buyer) revert BuyerAddress();
        if (isExpired) revert Expired(block.timestamp);
        parties[_seller] = true;
        seller = _seller;
    }

    /// ********* DEPLOYER MUST SEPARATELY APPROVE (by calling ierc20.approve() this contract address for the deposit amount (keep decimals in mind) ********
    /// @notice buyer deposits in address(this) after separately ERC20-approving address(this)
    function depositInEscrow() external returns (bool, uint256) {
        require(
            ierc20.allowance(msg.sender, address(this)) >= deposit,
            "address(this) allowance too low"
        );
        if (msg.sender != buyer) revert OnlyBuyer();
        ierc20.transferFrom(buyer, address(this), deposit);
        return (true, ierc20.balanceOf(address(this)));
    }

    /// @notice check if expired, and if so, return balance to buyer
    function checkIfExpired() external returns (bool) {
        if (expiryTime <= block.timestamp) {
            isExpired = true;
            _returnDeposit();
            emit DealExpired(true);
        } else {
            isExpired = false;
        }
        return (isExpired);
    }

    /// @notice call the applicable airnode when deposit in escrow and ready to close to check location of asset
    /// @dev inbound API parameters which may already be ABI encoded. Source: https://docs.api3.org/airnode/v0.2/grp-developers/call-an-airnode.html
    /// @param sponsorWallet: the wallet created via mnemonic by the sponsor with the Admin CLI, funds within used by the airnode to pay gas. See https://docs.api3.org/airnode/v0.2/grp-developers/requesters-sponsors.html#what-is-a-sponsor
    /// @param parameters: specify the API and reserved parameters (see Airnode ABI specifications at https://docs.api3.org/airnode/v0.2/reference/specifications/airnode-abi-specifications.html for how these are encoded)
    /// @return requestId: so parties may later verify assetLatitude and assetLongitude mappings
    function requestLocation(bytes32 endpointId, bytes calldata parameters)
        external
        returns (bytes32)
    {
        if (ierc20.balanceOf(address(this)) < deposit)
            revert FundsNotInEscrow();
        bytes32 requestId = airnodeRrp.makeFullRequest(
            airnode,
            endpointId,
            address(this),
            sponsorWallet,
            address(this),
            this.fulfill.selector,
            parameters
        );
        incomingFulfillments[requestId] = true;
        return (requestId);
    }

    /// @dev the AirnodeRrp.sol protocol contract will callback here to fulfill the request
    /// @notice incoming fulfillment from RRP protocol contract, which will feed the decoded data to _closeDeal()
    /// @param requestId: generated when making the request and passed here as a reference to identify which request the response is for
    /// @param data: for a successful response, the requested data which has been encoded. Decode by the function decode() from the abi object
    function fulfill(bytes32 requestId, bytes calldata data)
        external
        onlyAirnodeRrp
    {
        require(incomingFulfillments[requestId], "No Request");
        delete incomingFulfillments[requestId];
        int256[2] memory _decodedData = abi.decode(data, (int256[2]));
        _closeDeal(_decodedData[0], _decodedData[1]);
    }

    /// @dev set parameters for airnodeRrp.makeFullRequest
    /// @param _airnode: the address of the relevant API provider's airnode
    /// @param _sponsorWallet: derived sponsor wallet address
    /// @param _endpointId: endpointID for the location API
    /// @notice derive sponsorWallet via https://docs.api3.org/airnode/v0.6/concepts/sponsor.html#derive-a-sponsor-wallet
    function setRequestParameters(
        address _airnode,
        bytes32 _endpointId,
        address payable _sponsorWallet
    ) external restricted {
        airnode = _airnode;
        endpointId = _endpointId;
        sponsorWallet = _sponsorWallet;
    }

    /// @notice convenience function to send msg.value to sponsorWallet to ensure payment of Airnode gas fees
    function fundSponsorWallet() external payable {
        require(msg.value != 0, "msg.value == 0");
        (bool sent, ) = sponsorWallet.call{value: msg.value}("");
        if (!sent) revert TransferFailed();
    }

    /// @notice to check if deposit is in address(this)
    function checkEscrow() external view returns (uint256) {
        return ierc20.balanceOf(address(this));
    }

    /// @notice checks if both buyer and seller are ready to close and expiration has not been met; if so, address(this) closes deal and pays seller; if not, deposit returned to buyer
    /// @dev if properly closes, emits event with effective time of closing. This function is private to prevent external submission of valid _decodedData to trigger closing.
    /// @param _latitude: location latitude response passed by airnode in fulfill()
    /// @param _longitude: location longitude response passed by airnode in fulfill()
    function _closeDeal(int256 _latitude, int256 _longitude)
        private
        returns (bool)
    {
        if (_latitude < closingTargetLatitude - radius)
            revert OracleConditionNotSatisfied();
        if (_latitude > closingTargetLatitude + radius)
            revert OracleConditionNotSatisfied();
        if (_longitude < closingTargetLongitude - radius)
            revert OracleConditionNotSatisfied();
        if (_longitude > closingTargetLongitude + radius)
            revert OracleConditionNotSatisfied();
        if (expiryTime <= block.timestamp) {
            isExpired = true;
            _returnDeposit();
            emit DealExpired(true);
        } else {
            isClosed = true;
            _paySeller();
            emit DealClosed(true, block.timestamp, _latitude, _longitude); // confirmation of deal closing and effective time upon payment to seller
        }
        return (isClosed);
    }

    /// @notice address(this) returns deposit to buyer
    function _returnDeposit() private returns (bool, uint256) {
        ierc20.transfer(buyer, deposit);
        return (true, ierc20.balanceOf(address(this)));
    }

    /// @notice address(this) sends deposit to seller
    function _paySeller() private returns (bool, uint256) {
        ierc20.transfer(seller, deposit);
        return (true, ierc20.balanceOf(address(this)));
    }
}
