//SPDX-License-Identifier: MIT
/**** 
***** this code and any deployments of this code are strictly provided as-is; no guarantee, representation or warranty is being made, express or implied, as to the safety or correctness of the code 
***** or any smart contracts or other software deployed from these files, in accordance with the disclosures and licenses found here: https://github.com/ErichDylus/API3/blob/main/contracts/README.md
***** this code is not audited, and users, developers, or adapters of these files should proceed with caution and use at their own risk.
****/

pragma solidity ^0.8.0;

/// @title Swap to USDC and Send to Treasury
/// @notice uses Sushiswap router to swap incoming ETH for USDC tokens, then sends to the secondary API3 treasury
/// simple programmatic conversion to USDC for future grant usage

interface IUniswapV2Router02 {
    function swapExactETHForTokens(uint256 amountOutMin, address[] calldata path, address to, uint256 deadline) external payable returns (uint256[] memory amounts);
    function WETH() external pure returns (address);
}

contract SwaptoUSDCandSendtoTreasury {

    address constant USDC_TOKEN_ADDR = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC mainnet ETH token address
    address constant WETH_ADDR = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // WETH mainnet token address, alteratively could call sushiRouter.WETH() for the path
    address constant SUSHI_ROUTER_ADDR = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F; // Sushiswap router contract address
    address constant API3_SECONDARY_TREASURY = 0x556ECbb0311D350491Ba0EC7E019c354D7723CE0; // API3 DAO secondary treasury contract address, which holds API3's USDC for grants

    IUniswapV2Router02 public sushiRouter;

    constructor() payable {
        sushiRouter = IUniswapV2Router02(SUSHI_ROUTER_ADDR);
    }

    receive() external payable {
        sushiRouter.swapExactETHForTokens{ value: msg.value }(0, _getPathForETHtoUSDC(), API3_SECONDARY_TREASURY, block.timestamp);
    }
    
    /// @return the router path for ETH/USDC swap for the receiveAndSwap() function
    function _getPathForETHtoUSDC() internal pure returns (address[] memory) {
        address[] memory path = new address[](2);
        path[0] = WETH_ADDR;
        path[1] = USDC_TOKEN_ADDR;
        return path;
    }
}
