//SPDX-License-Identifier: MIT
/****
 ***** this code and any deployments of this code are strictly provided as-is;
 ***** no guarantee, representation or warranty is being made, express or implied, as to the safety or correctness of the code
 ***** or any smart contracts or other software deployed from these files,
 ***** in accordance with the disclosures and licenses found here: https://github.com/ErichDylus/API3/blob/main/contracts/README.md
 ***** this code is not audited, and users, developers, or adapters of these files should proceed with caution and use at their own risk.
 ****/

pragma solidity >=0.8.4;

/// @title Swap and Burn API3
/** @notice simple programmatic token burn per API3 whitepaper: uses Sushiswap router to swap USDC or ETH for API3 tokens,
*** LPs half, then burns all remaining API3 tokens via the token contract */

interface IUniswapV2Router02 {
    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
        external
        payable
        returns (
            uint256 amountToken,
            uint256 amountETH,
            uint256 liquidity
        );

    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

interface IAPI3 {
    function approve(address spender, uint256 amount) external returns (bool);
    
    function balanceOf(address account) external view returns (uint256);

    function burn(uint256 amount) external;

    function updateBurnerStatus(bool burnerStatus) external;
}

interface IUSDC {
    function approve(address spender, uint256 amount) external returns (bool);

    function balanceOf(address account) external view returns (uint256);
}

contract SwapAndBurnAPI3 {
    address public constant API3_TOKEN_ADDR =
        0x0b38210ea11411557c13457D4dA7dC6ea731B88a;
    address public constant SUSHI_ROUTER_ADDR =
        0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    address public constant USDC_TOKEN_ADDR =
        0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant WETH_ADDR =
        0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    IUniswapV2Router02 public sushiRouter;
    IAPI3 public iAPI3Token;
    IUSDC public iUSDCToken;

    error NoAPI3Tokens();
    error NoUSDCTokens();

    constructor() payable {
        sushiRouter = IUniswapV2Router02(SUSHI_ROUTER_ADDR);
        iAPI3Token = IAPI3(API3_TOKEN_ADDR);
        iAPI3Token.updateBurnerStatus(true);
        iUSDCToken = IUSDC(USDC_TOKEN_ADDR);
        iAPI3Token.approve(SUSHI_ROUTER_ADDR, type(uint256).max);
        iUSDCToken.approve(SUSHI_ROUTER_ADDR, type(uint256).max);
    }

    /// @notice swaps half of USDC held by address(this) for ETH and API3 to LP, swaps the other half for API3, and calls the internal _burnAPI3() function
    /// @dev amountOutMin is set to 1 to prevent successful call if the router is empty. LP has 10% buffer. Callable by anyone.
    function swapUSDCToAPI3AndLPAndBurn() external {
        if (iUSDCToken.balanceOf(address(this)) == 0) revert NoUSDCTokens();
        uint256 usdcBal = iUSDCToken.balanceOf(address(this));
        uint256 lpShare = usdcBal / 4;
        uint256 api3Share = usdcBal - lpShare;
        sushiRouter.swapExactTokensForETH(
            lpShare,
            1,
            _getPathForUSDCtoETH(),
            address(this),
            block.timestamp
        );
        sushiRouter.swapExactTokensForTokens(
            api3Share,
            1,
            _getPathForUSDCtoAPI3(),
            address(this),
            block.timestamp
        );
        sushiRouter.addLiquidityETH(
            API3_TOKEN_ADDR,
            lpShare,
            (lpShare * 9) / 10,
            (address(this).balance * 9) / 10,
            address(this),
            block.timestamp
        );
        _burnAPI3();
    }

    /// @notice receives ETH sent to address(this), swaps for API3, and calls the internal _burnAPI3() function
    receive() external payable {
        sushiRouter.swapExactETHForTokens{value: msg.value}(
            1,
            _getPathForETHtoAPI3(),
            address(this),
            block.timestamp
        );
        _burnAPI3();
    }

    function _burnAPI3() internal {
        if (iAPI3Token.balanceOf(address(this)) == 0) revert NoAPI3Tokens();
        iAPI3Token.burn(iAPI3Token.balanceOf(address(this)));
    }

    /// @return path the router path for ETH/API3 swap
    function _getPathForETHtoAPI3() internal pure returns (address[] memory) {
        address[] memory path = new address[](2);
        path[0] = WETH_ADDR;
        path[1] = API3_TOKEN_ADDR;
        return path;
    }

    /// @return path the router path for USDC/API3 swap
    function _getPathForUSDCtoAPI3() internal pure returns (address[] memory) {
        address[] memory path = new address[](2);
        path[0] = USDC_TOKEN_ADDR;
        path[1] = API3_TOKEN_ADDR;
        return path;
    }

    /// @return path the router path for USDC/ETH swap
    function _getPathForUSDCtoETH() internal pure returns (address[] memory) {
        address[] memory path = new address[](2);
        path[0] = USDC_TOKEN_ADDR;
        path[1] = WETH_ADDR;
        return path;
    }
}
