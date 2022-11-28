// SPDX-License-Identifier: MIT

pragma solidity >=0.8.16;

/// subject to all disclosures and licenses found here: https://github.com/ErichDylus/API3/blob/main/contracts/README.md
/// @notice interface for https://github.com/ErichDylus/API3/blob/main/contracts/SwapUSDCAndBurnAPI3.sol, immutable USDC revenue conversion and API3 token burn
/// @dev may be added to an API3 DAO revenue-producing contract in order to programmatically send USDC to the SwapUSDCAndBurnAPI3 contract and call its defined functions

interface ISwapUSDCAndBurnAPI3 {
    function swapUSDCToAPI3AndLpWithETHPair() external;

    function redeemLP() external;

    function redeemSpecificLP(uint256 lpRedeemIndex) external;
}
