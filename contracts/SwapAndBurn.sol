//SPDX-License-Identifier: MIT
// IN PROCESS AND INCOMPLETE, DO NOT USE FOR ANY PURPOSE
// unaudited, provided without warranty of any kind, and subject to all disclosures, licenses, and caveats of this repo
// https://soliditydeveloper.com/sushi-swap 

pragma solidity ^0.8.0;

/// @title Sushiswap and Burn API3
/// @author Varia LLC
/// @notice uses Sushiswap router to swap incoming ETH for API3 tokens, then burns the API3 tokens

import "https://github.com/sushiswap/sushiswap/blob/canary/contracts/uniswapv2/interfaces/IUniswapV2Router02.sol";

interface IERC20 { 
    function approve(address spender, uint256 amount) external returns (bool); 
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
}

contract SushiswapAndBurnAPI3 {

    address private API3Token = 0x0b38210ea11411557c13457D4dA7dC6ea731B88a; // API3 token address
    address internal constant SUSHI_ROUTER_ADDR = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F; // Sushiswap router contract address

    IUniswapV2Router02 public sushiRouter;

    error NoETHSent();

    constructor() payable {
        sushiRouter = IUniswapV2Router02(SUSHI_ROUTER_ADDR);
        IERC20(API3Token).approve(address(this),1e24);
    }

    function receiveAndSwap() public payable {
        if (msg.value == 0) revert NoETHSent();
        sushiRouter.swapExactETHForTokens{ value: msg.value }(0, _getPathForETHtoAPI3(), address(this), block.timestamp+100);
    }
    
    function _getPathForETHtoAPI3() private view returns (address[] memory) {
        address[] memory path = new address[](2);
        path[0] = sushiRouter.WETH();
        path[1] = API3Token;
        return path;
    }

    receive() payable external {}
}
