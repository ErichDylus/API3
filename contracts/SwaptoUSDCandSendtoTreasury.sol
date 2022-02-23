//SPDX-License-Identifier: MIT
// FOR TESTING ONLY, DO NOT USE
// unaudited, provided without warranty of any kind, and subject to all disclosures, licenses, and caveats of this repo

pragma solidity ^0.8.0;

/// @title Swap to USDC and Send to Treasury
/// @notice uses Sushiswap router to swap incoming ETH for USDC tokens, then sends to the secondary API3 treasury
/// simple programmatic conversion of excess fees received to USDC for future grant usage

interface IUniswapV2Router02 {
    function swapExactETHForTokens(uint256 amountOutMin, address[] calldata path, address to, uint256 deadline) external payable returns (uint256[] memory amounts);
    function WETH() external pure returns (address);
}

interface IUSDC  { 
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
}

contract SwaptoUSDCandSendtoTreasury {

    address constant USDC_TOKEN_ADDR = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC mainnet ETH token address
    address constant SUSHI_ROUTER_ADDR = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F; // Sushiswap router contract address
    address constant API3_SECONDARY_TREASURY = 0x556ECbb0311D350491Ba0EC7E019c354D7723CE0; // API3 DAO secondary treasury contract address, which holds API3's USDC for grants

    IUniswapV2Router02 public sushiRouter;
    IUSDC public iUSDCToken;

    error NoETHSent();
    error NoUSDC();

    constructor() payable {
        sushiRouter = IUniswapV2Router02(SUSHI_ROUTER_ADDR);
        iUSDCToken = IUSDC(USDC_TOKEN_ADDR);
    }

    /// @notice FOR TESTING ONLY - DO NOT USE
    function receiveAndSwap() public payable {
        if (msg.value == 0) revert NoETHSent();
        sushiRouter.swapExactETHForTokens{ value: msg.value }(0, _getPathForETHtoUSDC(), address(this), block.timestamp+100);
        _sendUSDC();
    }

    function _sendUSDC() internal {
        if (iUSDCToken.balanceOf(address(this)) == 0) revert NoUSDC();
        iUSDCToken.transfer(API3_SECONDARY_TREASURY, iUSDCToken.balanceOf(address(this)));
    }
    
    /// @return the router path for ETH/USDC swap for the receiveAndSwap() function
    function _getPathForETHtoUSDC() internal view returns (address[] memory) {
        address[] memory path = new address[](2);
        path[0] = sushiRouter.WETH(); //0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2
        path[1] = USDC_TOKEN_ADDR;
        return path;
    }

    receive() payable external {}
}
