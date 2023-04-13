//SPDX-License-Identifier: MIT
/****
 ***** this code and any deployments of this code are strictly provided as-is;
 ***** no guarantee, representation or warranty is being made, express or implied,
 ***** as to the safety or correctness of the code
 ***** or any smart contracts or other software deployed from these files,
 ***** in accordance with the disclosures and licenses found in the README of this repo.
 ***** this code is not audited, and users, developers, or adapters of these files
 ***** should proceed with caution and use at their own risk.
 ****/

pragma solidity >=0.8.12;

/// @title Swap to USDC and Send to API3 Treasury
/// @notice uses UniswapV2 router to auto-convert incoming ETH for USDC tokens, then sends the USDC to the secondary API3 treasury

interface IUniswapV2Router02 {
    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);
}

contract SwaptoUSDCandSendtoAPI3Treasury {
    address constant USDC_ADDR = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH_ADDR = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant API3_SECONDARY_TREASURY =
        0x556ECbb0311D350491Ba0EC7E019c354D7723CE0; // API3 DAO secondary treasury contract address, which holds API3's USDC for grants
    address constant UNI_ROUTER_ADDR =
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    IUniswapV2Router02 internal immutable uniRouter;

    constructor() payable {
        uniRouter = IUniswapV2Router02(UNI_ROUTER_ADDR);
    }

    receive() external payable {
        uniRouter.swapExactETHForTokens{value: msg.value}(
            1,
            _getPathForETHtoUSDC(),
            API3_SECONDARY_TREASURY,
            block.timestamp
        );
    }

    /// @return the router path for ETH/USDC swap
    function _getPathForETHtoUSDC() internal pure returns (address[] memory) {
        address[] memory path = new address[](2);
        path[0] = WETH_ADDR;
        path[1] = USDC_ADDR;
        return path;
    }
}
