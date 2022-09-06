//SPDX-License-Identifier: MIT
/****
 ***** IN PROCESS AND INCOMPLETE
 *****
 ***** this code and any deployments of this code are strictly provided as-is;
 ***** no guarantee, representation or warranty is being made,
 ***** express or implied, as to the safety or correctness of the code
 ***** or any smart contracts or other software deployed from these files,
 ***** in accordance with the disclosures and licenses
 ***** found here: https://github.com/ErichDylus/API3/blob/main/contracts/README.md
 ***** this code is not audited, and users, developers, or adapters of these files
 ***** should proceed with caution and use at their own risk.
 ****/
pragma solidity >=0.8.16;

/// @title dQRNG
/** @notice decentralized API for multi-source quantum random number */
/** @dev uses API3 QRNG and access NFTs in requester address. Sponsor wallets handled by dQRNG client.
 ** requester specifies airnodes and relayer addresses. Currently, deployer specifies valid relayer and NFT addresses. */

interface ERC721 {
    function balanceOf(address owner) external returns (uint256);
}

contract Dqrng {
    address public immutable deployer;

    mapping(address => address) public airnodeToNFT;
    mapping(address => address) public requesterToRelayer;
    mapping(address => bool) public isRelayer;

    error OnlyDeployer();
    error NoNFT1();
    error NoNFT2();
    error NoNFT3();
    error NoRelayer();
    error NoRequest();
    error SignatureMissing();

    event RelayerRequested(
        address indexed relayer,
        address requester,
        address airnode1,
        address airnode2,
        address airnode3
    );

    /// @dev must derive, designate and fund sponsorWallet after deployment
    constructor() {
        deployer = msg.sender;
    }

    /// @notice request dQRNG via relayer, provided requester is holding necessary access NFTs
    /// @dev each relayer will listen for RelayerRequested events where it is specified as relayer
    /// @param _airnode1: first QRNG airnode contract address, see https://docs.api3.org/qrng/providers.html
    /// @param _airnode2: second QRNG airnode contract address, see https://docs.api3.org/qrng/providers.html
    /// @param _airnode3: third QRNG airnode contract address, see https://docs.api3.org/qrng/providers.html
    /// @param _relayer: address which coordinates commit-reveal scheme using the airnode addresses and responds using the sponsorWallet
    function requestDQRNG(
        address _airnode1,
        address _airnode2,
        address _airnode3,
        address _relayer
    ) external {
        if (_relayer == address(0)) revert NoRelayer();
        if (ERC721(airnodeToNFT[_airnode1]).balanceOf(msg.sender) == 0)
            revert NoNFT1();
        if (ERC721(airnodeToNFT[_airnode2]).balanceOf(msg.sender) == 0)
            revert NoNFT2();
        if (ERC721(airnodeToNFT[_airnode3]).balanceOf(msg.sender) == 0)
            revert NoNFT3();

        requesterToRelayer[msg.sender] = _relayer;

        emit RelayerRequested(
            _relayer,
            msg.sender,
            _airnode1,
            _airnode2,
            _airnode3
        );
    }

    /// @dev relayer responds with the aggregated random number and all signatures here
    /// @param _requester: address of dQRNG requester
    /// @param _airnode1Sig: signature from airnode1
    /// @param _airnode2Sig: signature from airnode2
    /// @param _airnode3Sig: signature from airnode3
    /// @param _randomNumber: aggregated quantum random number
    function fulfill(
        address _requester,
        bytes32 _airnode1Sig,
        bytes32 _airnode2Sig,
        bytes32 _airnode3Sig,
        uint256 _randomNumber
    ) external returns (uint256) {
        if (!isRelayer[msg.sender]) revert NoRelayer();
        if (requesterToRelayer[_requester] == address(0)) revert NoRequest();
        if (_airnode1Sig == 0 || _airnode2Sig == 0 || _airnode3Sig == 0)
            revert SignatureMissing();

        delete (requesterToRelayer[_requester]);
        return (_randomNumber);
    }

    /// @notice for deployer to designate valid and active relayer addresses
    /// @param _relayer: address of dQRNG relayer to activate
    function designateRelayer(address _relayer) external {
        if (msg.sender != deployer) revert OnlyDeployer();
        isRelayer[_relayer] = true;
    }

    /// @notice for deployer to revoke a relayer address
    /// @param _relayer: address of dQRNG relayer to revoke
    function revokeRelayer(address _relayer) external {
        if (msg.sender != deployer) revert OnlyDeployer();
        delete (isRelayer[_relayer]);
    }

    /// @notice for deployer to specify access NFT address mapped to airnode address
    /** @dev deployer may also amend or revoke by pointing the mapping to a new address or address(0);
     ** airnodeToNFT[] also ensures validity of airnode addresses passed to requestDQRNG() */
    /// @param _airnode: QRNG provider airnode address
    /// @param _nft: contract address of access NFT corresponding to _airnode
    function registerAccessNFT(address _airnode, address _nft) external {
        if (msg.sender != deployer) revert OnlyDeployer();
        airnodeToNFT[_airnode] = _nft;
    }
}
