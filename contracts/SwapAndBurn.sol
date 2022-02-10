//SPDX-License-Identifier: MIT
// IN PROCESS AND INCOMPLETE, DO NOT USE FOR ANY PURPOSE
// unaudited, provided without warranty of any kind, and subject to all disclosures, licenses, and caveats of this repo
// https://github.com/sushiswap/sushiswap/blob/canary/contracts/uniswapv2/interfaces/IUniswapV2Pair.sol https://soliditydeveloper.com/sushi-swap 

pragma solidity ^0.8.10;

/// @title Swap and Burn API3
/// @author Varia LLC
/// @notice uses Sushiswap/Uniswap router to swap incoming ETH for API3 tokens, then burns the API3 tokens

interface IERC20 { 
    function approve(address spender, uint256 amount) external returns (bool); 
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

contract SushiswapAndBurnAPI3 {

    address constant API3Token = 0x0b38210ea11411557c13457D4dA7dC6ea731B88a; // API3 token address
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // Wrapper Ether token address 
    address constant SushiRouter = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F; // Sushiswap router contract address

    error NoETHSent();

    constructor() payable {
        IERC20(API3Token).approve(address(this),1e24);
        IERC20(WETH).approve(address(this),1e24);
    }

    function receiveAndSwap() public payable {
        if (msg.value == 0) revert NoETHSent();
        SushiRouter.swapExactETHForTokens(msg.value,0,[WETH,API3Token],address(this),block.timestamp+10000);
    }
}
