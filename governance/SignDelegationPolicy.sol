// SPDX-License-Identifier: MIT
// IN PROCESS, FOR DEMONSTRATION ONLY, unaudited, not recommended to be used for any purpose, carries absolutely no warranty of any kind
// @dev sign an API3 Token Delegation and Voting Policy, with reference to their own Delegation Disclosure
// only if address has staked API3 in API3 governance contract

pragma solidity ^0.8.6;

// Delegator deploys and signs their Token Delegation and Voting Policy and signs
// this interface allows a delegate to indicate their assent by EthSign

interface VoteDelegateDisclosure {
    function sign(string calldata details) external; 
}

contract SignDelegationPolicy {

    address owner;
    address constant API3governance = 0x6dd655f10d4b9E242aE186D9050B68F725c76d76; // API3 governance staking pool
    string public disclosureLink;
    VoteDelegateDisclosure public policyContract;
    mapping(address => string) disclosureHash;
    
    event DelegateDisclosure(address indexed delegate, string signature, string IPFSlink);
    
    // deployer sets token address and address of Token Delegation and Voting Policy (https://github.com/LeXpunK-Army/Token-Delegation-And-Voting-Policy)
    constructor(address _policyContract) { 
        policyContract = VoteDelegateDisclosure(_policyContract);
        owner = msg.sender;
    }
    
    
    function signPolicy(string memory _disclosureLink, string calldata _signature) external {
        //require(hasStaked, "Signatory isn't an API3 DAO governor.");
        disclosureHash[msg.sender] = _disclosureLink;
        policyContract.sign(_signature);
        emit DelegateDisclosure(msg.sender, _signature, _disclosureLink);
    }
    
    //check msg.sender has staked in API3 governance
    function checkStake() external {
    }

}
