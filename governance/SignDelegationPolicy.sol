// SPDX-License-Identifier: MIT
// FOR DEMONSTRATION ONLY, unaudited, not recommended to be used for any purpose, carries absolutely no warranty of any kind
// @dev sign an API3 Token Delegation and Voting Policy, with reference to their own Delegation Disclosure
// only if address has staked API3 in API3 governance contract

pragma solidity ^0.8.6;

// Delegator deploys contract with link to disclosure and signs their Token Delegation and Voting Policy by EthSign

interface VoteDelegateDisclosure {
    function sign(string calldata details) external; 
}

interface API3Pool {
    function userSharesAt(address userAddress, uint256 _block) external view returns (uint256);
}

contract SignDelegationPolicy {

    address constant API3governance = 0x6dd655f10d4b9E242aE186D9050B68F725c76d76; // API3 governance staking pool contract address
    VoteDelegateDisclosure public ipolicyContract;
    API3Pool public iAPI3Pool;
    
    event DelegateDisclosure(address indexed delegate, string signature, string disclosureLink);
    
    // deployer sets address of Token Delegation and Voting Policy (https://github.com/LeXpunK-Army/Token-Delegation-And-Voting-Policy)
    constructor(address _policyContract) { 
        ipolicyContract = VoteDelegateDisclosure(_policyContract);
        iAPI3Pool = API3Pool(API3governance);
    }
    
    
    function signPolicy(string memory _disclosureLink, string calldata _signature) external {
        require(iAPI3Pool.userSharesAt(msg.sender, block.number) > 0, "Signatory isn't staked in the API3 DAO governance contract.");
        ipolicyContract.sign(_signature);
        emit DelegateDisclosure(msg.sender, _signature, _disclosureLink);
    }
    
    //check msg.sender has staked in API3 governance
    function checkStake() external view returns (uint256) {
        return iAPI3Pool.userSharesAt(msg.sender, block.number);
    }
}
