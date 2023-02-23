//SPDX-License-Identifier: MIT
/**** INCOMPLETE
 ***** this code and any deployments of this code are strictly provided as-is; no guarantee, representation or warranty is being made, express or implied, as to the safety or correctness of the code
 ***** or any smart contracts or other software deployed from these files, in accordance with the disclosures and licenses found here: https://github.com/ErichDylus/API3/blob/main/contracts/README.md
 ***** this code is not audited, and users, developers, or adapters of these files should proceed with caution and use at their own risk.
 ****/
pragma solidity >=0.8.9;

/// @title Airnode ETH Escrow
/// @notice bilateral smart escrow contract, with ETH as payment, expiration denominated in seconds, deposit refunded if contract expires before closeDeal() called, contingent on valid Airnode response as parameterized in _closeDeal()
/// TODO: allow a partial deposit
import {RrpRequesterV0} from "https://github.com/api3dao/airnode/blob/master/packages/airnode-protocol/contracts/rrp/requesters/RrpRequesterV0.sol";

contract AirnodeEthEscrow is RrpRequesterV0 {
    address payable public immutable buyer;
    address payable public seller;
    uint256 public immutable deposit;
    uint256 public immutable expiryTime;
    bool public sellerApproved;
    bool public buyerApproved;
    bool isExpired;
    bool isClosed;

    string description;

    mapping(bytes32 => bool) public incomingFulfillments;
    mapping(bytes32 => int256) public fulfilledData;

    event DealExpired(uint256 effectiveTime);
    event DealClosed(bool isClosed, uint256 effectiveTime); //event provides exact blockstamp Unix time of closing and oracle information

    error BuyerAddress();
    error DepositAmount();
    error Expired();
    error NoRequest();
    error NotApproved();
    error OnlyBuyer();
    error OnlyBuyerOrSeller();
    error OracleConditionNotSatisfied();
    error PaymentFailed();

    /// @notice deployer (buyer) initiates escrow with description, deposit amount in USD, address of stablecoin, seconds until expiry, and designate recipient seller
    /// @param _description should be a brief identifier of the deal in question - perhaps as to parties/underlying asset/documentation reference/hash
    /// @param _deposit is the purchase price in wei which will be deposited in the smart escrow contract
    /// @param _seller is the seller's address, who will receive the purchase price if the deal closes
    /// @param _secsUntilExpiry is the number of seconds until the deal expires, which can be converted to days for front end input or the code can be adapted accordingly
    /// @param _airnodeRrp is the public address of the AirnodeRrp.sol protocol contract on the relevant blockchain used for this contract; see: https://docs.api3.org/airnode/v0.2/reference/airnode-addresses.html
    constructor(
        string memory _description,
        uint256 _deposit,
        uint256 _secsUntilExpiry,
        address _seller,
        address _airnodeRrp
    ) RrpRequesterV0(_airnodeRrp) {
        if (_seller == msg.sender) revert BuyerAddress();
        buyer = payable(msg.sender);
        deposit = _deposit;
        description = _description;
        seller = payable(_seller);
        expiryTime = block.timestamp + _secsUntilExpiry;
    }

    /// @notice buyer may confirm seller's recipient address as extra security measure or change seller address
    /// @param _seller is the new recipient address of seller
    function designateSeller(address payable _seller) external {
        if (_seller == buyer) revert BuyerAddress();
        if (msg.sender != buyer || msg.sender != seller)
            revert OnlyBuyerOrSeller();
        if (isExpired) revert Expired();
        seller = _seller;
    }

    /// @notice buyer deposits in this contract, requires exact wei deposit amount
    function depositInEscrow() external payable returns (bool, uint256) {
        if (msg.sender != buyer) revert OnlyBuyer();
        if (msg.value != deposit) revert DepositAmount();
        (bool sent, ) = address(this).call{value: deposit}("");
        if (!sent) revert PaymentFailed();

        return (true, address(this).balance);
    }

    /// @notice check if expired, and if so, return balance to buyer
    function checkIfExpired() external returns (bool) {
        if (expiryTime <= block.timestamp) {
            isExpired = true;
            _returnDeposit();
            emit DealExpired(block.timestamp);
        } else {
            isExpired = false;
        }
        return (isExpired);
    }

    /// @notice for seller to check if deposit is in escrow
    function checkEscrow() external view returns (uint256) {
        return address(this).balance;
    }

    /// if buyer wishes to initiate dispute over seller breach of off chain agreement or repudiate, simply may wait for expiration without sending deposit nor calling this function
    /// @notice for 'buyer' and 'seller' to each call this method when ready to close, in order for _closeDeal() to execute
    function readyToClose() external returns (bool, bool) {
        if (msg.sender == seller) {
            sellerApproved = true;
        } else if (msg.sender == buyer) {
            buyerApproved = true;
        }
        return (sellerApproved, buyerApproved);
    }

    /// @notice call the applicable airnode when ready to close
    /// @dev inbound API parameters which may already be ABI encoded. Source: https://docs.api3.org/airnode/v0.2/grp-developers/call-an-airnode.html
    /// @param airnode the address of the relevant API provider's airnode
    /// @param endpointId identifier for the specific endpoint desired to access via the airnode
    /// @param sponsor address of the entity that pays for the fulfillment of a request & gas costs the Airnode will incur. These costs will be withdrawn from the sponsorWallet of the Airnode when the requester calls it.
    /// @param sponsorWallet the wallet created via mnemonic by the sponsor with the Admin CLI, funds within used by the airnode to pay gas. See https://docs.api3.org/airnode/v0.2/grp-developers/requesters-sponsors.html#what-is-a-sponsor
    /// @param parameters specify the API and reserved parameters (see Airnode ABI specifications at https://docs.api3.org/airnode/v0.2/reference/specifications/airnode-abi-specifications.html for how these are encoded)
    function callAirnode(
        address airnode,
        bytes32 endpointId,
        address sponsor,
        address sponsorWallet,
        bytes calldata parameters
    ) external {
        if (!sellerApproved || !buyerApproved) revert NotApproved();
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
    /// @notice incoming fulfillment from RRP protocol contract, which will feed the decoded data to _closeDeal()
    /// @param requestId generated when making the request and passed here as a reference to identify which request the response is for
    /// @param data for a successful response, the requested data which has been encoded. Decode by the function decode() from the abi object
    function fulfill(bytes32 requestId, bytes calldata data)
        external
        onlyAirnodeRrp
    {
        if (!incomingFulfillments[requestId]) revert NoRequest();
        delete incomingFulfillments[requestId];
        int256 _decodedData = abi.decode(data, (int256));
        fulfilledData[requestId] = _decodedData;
        _closeDeal(_decodedData);
    }

    /// @notice checks if both buyer and seller are ready to close and expiration has not been met; if so, closes deal and pays seller; if not, deposit returned to buyer
    /// @dev if properly closes, emits event with effective time of closing. This function is private to prevent external submission of valid _decodedData to trigger closing.
    /// @param _decodedData airnode response passed by fulfill()
    function _closeDeal(int256 _decodedData) internal returns (bool) {
        if (_decodedData <= 0) revert OracleConditionNotSatisfied(); //change this condition for applicable triggering data/params/range etc. from Airnode
        if (expiryTime <= block.timestamp) {
            isExpired = true;
            _returnDeposit();
            emit DealExpired(block.timestamp);
        } else {
            isClosed = true;
            (bool sent, ) = seller.call{value: deposit}("");
            if (!sent) revert PaymentFailed();
            emit DealClosed(true, block.timestamp); // confirmation of deal closing and effective time upon payment to seller
        }
        return (isClosed);
    }

    /// @notice this contract returns deposit to buyer
    function _returnDeposit() internal returns (bool, uint256) {
        (bool sent, ) = buyer.call{value: deposit}("");
        if (!sent) revert PaymentFailed();
        return (true, address(this).balance);
    }
}
