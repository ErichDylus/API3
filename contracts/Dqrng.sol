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
    mapping(address => bytes4) private requesterToSelector;

    error OnlyDeployer();
    error NoNFT(address airnode);
    error NoRelayer();
    error RequesterCallFailed();
    error RequesterRelayerMismatch();
    error SignatureMissing(uint256 sigIndex);

    event RelayerRequested(
        address indexed relayer,
        address requester,
        address[] airnodes
    );

    constructor() {
        deployer = msg.sender;
    }

    /// @notice request dQRNG via relayer, provided requester is holding necessary access NFTs (represent on-chain API key for each respective airnode address)
    /// @dev each relayer listens for RelayerRequested events where it is specified as relayer
    /// @param _airnodes: array of requested QRNG airnode contract addresses, see https://docs.api3.org/qrng/providers.html
    /// @param _relayer: address which coordinates commit-reveal scheme using the airnode addresses and responds
    /// @param _functionSelector: requester contract function identifier which will ultimately receive the random number from fulfull()
    function requestDqrng(
        address[] calldata _airnodes,
        address _relayer,
        bytes4 _functionSelector
    ) external {
        if (!isRelayer[_relayer]) revert NoRelayer();
        for (uint256 i = 0; i < _airnodes.length; ) {
            if (ERC721(airnodeToNFT[_airnodes[i]]).balanceOf(msg.sender) == 0)
                revert NoNFT(_airnodes[i]);
            unchecked {
                ++i;
            }
        }

        requesterToRelayer[msg.sender] = _relayer;
        requesterToSelector[msg.sender] = _functionSelector;

        emit RelayerRequested(_relayer, msg.sender, _airnodes);
    }

    /// @dev relayer responds with the aggregated random number and all signatures here; checks if each sig != 0
    /// @param _requester: address of dQRNG requester
    /// @param _airnodeSigs: array of signatures corresponding to requested airnodes
    /// @param _randomNumber: aggregated quantum random number
    function fulfill(
        address _requester,
        bytes32[] calldata _airnodeSigs,
        uint256 _randomNumber
    ) external {
        if (msg.sender != requesterToRelayer[_requester])
            revert RequesterRelayerMismatch();

        for (uint256 i = 0; i < _airnodeSigs.length; ) {
            if (_airnodeSigs[i] == 0) revert SignatureMissing(i);
            unchecked {
                ++i;
            }
        }

        // forward random number to requester contract's applicable function
        (bool success, ) = _requester.delegatecall(
            abi.encodeWithSelector(
                requesterToSelector[_requester],
                _randomNumber
            )
        );
        if (!success) revert RequesterCallFailed();
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

    /// @notice for deployer to specify access NFT contract address mapped to airnode address
    /** @dev deployer may also amend or revoke by pointing the mapping to a new address or address(0);
     ** airnodeToNFT[] also ensures validity of airnode addresses passed to requestDQRNG() */
    /// @param _airnode: QRNG provider airnode address
    /// @param _nft: contract address of access NFT corresponding to _airnode
    function registerAccessNFT(address _airnode, address _nft) external {
        if (msg.sender != deployer) revert OnlyDeployer();
        airnodeToNFT[_airnode] = _nft;
    }

    /// @notice convenience function to get function selector for requester before requestDqrng
    /// @param _function: requester's function to receive random number and any other arguments (but must include uint256), for example "receiveRandNum(uint256)"
    /// @return bytes4 function selector for requester to pass in requestDqrng as _functionSelector
    function getSelector(string calldata _function)
        external
        pure
        returns (bytes4)
    {
        return bytes4(keccak256(bytes(_function)));
    }
}
