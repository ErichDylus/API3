//SPDX-License-Identifier: MIT
/**** 
***** this code and any deployments of this code are strictly provided as-is; no guarantee, representation or warranty is being made, express or implied, as to the safety or correctness of the code 
***** or any smart contracts or other software deployed from these files, in accordance with the disclosures and licenses found here: https://github.com/ErichDylus/API3/blob/main/contracts/README.md
***** this code is not audited, and users, developers, or adapters of these files should proceed with caution and use at their own risk.
****/

pragma solidity ^0.8.0;

/// @title Swap and Burn API3
/// @notice uses Sushiswap router to swap incoming ETH for API3 tokens, then burns the API3 tokens via the token contract
/// simple programmatic token burn per API3 whitepaper 

interface IUniswapV2Router02 {
    function swapExactETHForTokens(uint256 amountOutMin, address[] calldata path, address to, uint256 deadline) external payable returns (uint256[] memory amounts);
    function WETH() external pure returns (address);
}

interface IAPI3 { 
    function balanceOf(address account) external view returns (uint256);
    function updateBurnerStatus(bool burnerStatus) external;
    function burn(uint256 amount) external;
}

contract SwapAndBurnAPI3 {

    address constant API3_TOKEN_ADDR = 0x0b38210ea11411557c13457D4dA7dC6ea731B88a; // API3 token address
    address constant WETH_ADDR = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // WETH mainnet token address, alteratively could call sushiRouter.WETH() for the path
    address constant SUSHI_ROUTER_ADDR = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F; // Sushiswap router contract address

    IUniswapV2Router02 public sushiRouter;
    IAPI3 public iAPI3Token;

    error NoAPI3Tokens();

    constructor() payable {
        sushiRouter = IUniswapV2Router02(SUSHI_ROUTER_ADDR);
        iAPI3Token = IAPI3(API3_TOKEN_ADDR);
        iAPI3Token.updateBurnerStatus(true);
    }

    /// @notice receives ETH sent to address(this), swaps for API3, and calls the internal _burnAPI3() function
    receive() external payable {
        sushiRouter.swapExactETHForTokens{ value: msg.value }(0, _getPathForETHtoAPI3(), address(this), block.timestamp);
        _burnAPI3();
    }

    function _burnAPI3() internal {
        if (iAPI3Token.balanceOf(address(this)) == 0) revert NoAPI3Tokens();
        iAPI3Token.burn(iAPI3Token.balanceOf(address(this)));
    }
    
    /// @return the router path for ETH/API3 swap
    function _getPathForETHtoAPI3() internal pure returns (address[] memory) {
        address[] memory path = new address[](2);
        path[0] = WETH_ADDR;
        path[1] = API3_TOKEN_ADDR;
        return path;
    }
}
