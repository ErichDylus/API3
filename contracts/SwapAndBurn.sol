//SPDX-License-Identifier: MIT
// IN PROCESS AND INCOMPLETE, DO NOT USE FOR ANY PURPOSE
// unaudited, provided without warranty of any kind, and subject to all disclosures, licenses, and caveats of this repo

pragma solidity ^0.8.0;

/// @title Sushiswap and Burn API3
/// @author Varia LLC
/// @notice uses Sushiswap router to swap incoming ETH for API3 tokens, then burns the API3 tokens

interface IUniswapV2Router02 {
    // note: consider swapExactETHForTokensSupportingFeeOnTransferTokens() for sushiswap, same params
    function swapExactETHForTokens(uint256 amountOutMin, address[] calldata path, address to, uint256 deadline) external payable returns (uint256[] memory amounts);
    function WETH() external pure returns (address);
}

interface IERC20 { 
    function approve(address spender, uint256 amount) external returns (bool); 
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function updateBurnerStatus(bool burnerStatus) external;
    function burn(uint256 amount) external;
}

contract SwapAndBurnAPI3 {

    address constant API3_TOKEN_ADDR = 0x0b38210ea11411557c13457D4dA7dC6ea731B88a; // API3 token address
    address constant SUSHI_ROUTER_ADDR = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F; // Sushiswap router contract address

    IUniswapV2Router02 public sushiRouter;
    IERC20 public iAPI3Token;

    error NoETHSent();
    error NoAPI3();

    constructor() payable {
        sushiRouter = IUniswapV2Router02(SUSHI_ROUTER_ADDR);
        iAPI3Token = IERC20(API3_TOKEN_ADDR);
        //iAPI3Token.approve(address(this),1e24);
        //iAPI3Token.updateBurnerStatus(true);
    }

    function receiveAndSwap() public payable {
        if (msg.value == 0) revert NoETHSent();
        sushiRouter.swapExactETHForTokens{ value: msg.value }(0, _getPathForETHtoAPI3(), address(this), block.timestamp+100);
        _burnAPI3();
    }

    function _burnAPI3() internal {
        if (iAPI3Token.balanceOf(address(this)) == 0) revert NoAPI3();
        iAPI3Token.burn(iAPI3Token.balanceOf(address(this)));
    }
    
    /// @return the router path for ETH/API3 swap for the receiveAndSwap() function
    function _getPathForETHtoAPI3() internal view returns (address[] memory) {
        address[] memory path = new address[](2);
        path[0] = sushiRouter.WETH();
        path[1] = API3_TOKEN_ADDR;
        return path;
    }

    receive() payable external {}
}
