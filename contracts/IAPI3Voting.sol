// SPDX-License-Identifier: MIT

pragma solidity >=0.8.4;

/// @notice interface for API3 governance voting information, API3 governance contract address 0x6dd655f10d4b9E242aE186D9050B68F725c76d76

interface IAPI3Voting {
    function delegatedToUser(address userAddress) external view returns (uint256); // delegation to user address
    function delegatedToUserAt(address userAddress, uint256 block) external view returns (uint256); // delegation to user address at specific block

    function userDelegate(address userAddress) external view returns (uint256); // amount user address is delegating
    function userDelegateAt(address userAddress, uint256 block) external view returns (uint256); // amount user address is delegating at specific block

    function userShares(address userAddress) external view returns (uint256); // amount of shares of user address
    function userSharesAt(address userAddress, uint256 block) external view returns (uint256); // amount of shares of user address at specific block

    function userVotingPower(address userAddress) external view returns (uint256); // total voting power of user address
    function userVotingPowerAt(address userAddress, uint256 block) external view returns (uint256); // total voting power of user address at specific block
}
