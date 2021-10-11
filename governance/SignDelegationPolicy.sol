// SPDX-License-Identifier: MIT
// FOR DEMONSTRATION ONLY, unaudited, not recommended to be used for any purpose, carries absolutely no warranty of any kind
// @dev ETHsign an API3 Token Delegation and Voting Policy, with reference to their own Delegation Disclosure
// only if address has staked API3 in API3 governance contract

pragma solidity ^0.8.6;

// Delegator deploys contract with link to disclosure and signs their Token Delegation and Voting Policy by EthSign

interface VoteDelegateDisclosure {
    function sign(string calldata details) external; // interface to API3 Delegation and Voting Policy version stamped on-chain
}

interface API3Pool {
    function userSharesAt(address userAddress, uint256 block) external view returns (uint256); // interface to check signer's voting power in API3 governance pool contract
}

contract SignDelegationPolicy {

    address constant API3governance = 0x6dd655f10d4b9E242aE186D9050B68F725c76d76; // API3 governance staking pool contract address
    VoteDelegateDisclosure public ipolicyContract;
    API3Pool public iAPI3Pool;
    
    event DelegateDisclosure(address indexed delegate, string signature, string disclosureLink);
    
    //@param _policyContract: address of API3 Token Delegation and Voting Policy indicated on-chain, to be confirmed by API3 DAO vote
    constructor(address _policyContract) { 
        ipolicyContract = VoteDelegateDisclosure(_policyContract);
        iAPI3Pool = API3Pool(API3governance);
    }
    
    //@param _disclosureLink: msg.sender submits link to their own vote delegation disclosure, which may be IPFS or merely Github (indicated version at time of signature)
    //@param _signature: msg.sender signs (i.e. /s/ [NAME]), indicating their acknowledgment of and agreement to the API3 policy and memorializing their own disclosure
    function signPolicy(string calldata _disclosureLink, string calldata _signature) external {
        require(iAPI3Pool.userSharesAt(msg.sender, block.number) > 0, "Signatory isn't staked in the API3 DAO governance contract.");
        ipolicyContract.sign(_signature);
        emit DelegateDisclosure(msg.sender, _signature, _disclosureLink);
    }
    
    //for msg.sender to check their current voting power in API3 governance
    function checkStake() external view returns (uint256) {
        return iAPI3Pool.userSharesAt(msg.sender, block.number);
    }
}
