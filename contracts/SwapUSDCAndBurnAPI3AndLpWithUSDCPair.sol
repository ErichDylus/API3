//SPDX-License-Identifier: MIT
/*****
 ***** this code and any deployments of this code are strictly provided as-is;
 ***** no guarantee, representation or warranty is being made, express or implied, as to the safety or correctness of the code
 ***** or any smart contracts or other software deployed from these files,
 ***** in accordance with the disclosures and licenses found here: https://github.com/ErichDylus/API3/blob/main/contracts/README.md
 ***** this code is not audited, and users, developers, or adapters of these files should proceed with caution and use at their own risk.
 ****/

pragma solidity >=0.8.16;

/// @title Swap USDC and Burn API3 and LP with USDC Pair
/** @notice simple programmatic token burn per API3 whitepaper: uses Sushiswap router to swap USDC held by this contract for API3 tokens,
 ** LPs half (redeemable to this contract after the lpWithdrawDelay provided in constructor), then burns all remaining API3 tokens via the token contract;
 ** also auto-swaps any ETH sent directly to this contract for API3 tokens, which are then burned via the token contract */
/** @dev adaptation of https://github.com/ErichDylus/API3/blob/main/contracts/SwapUSDCAndBurnAPI3.sol to an API3/USDC pair lp and swap;
 ** API3/USDC pair could be used to implement https://docs.uniswap.org/protocol/V2/concepts/core-concepts/oracles */

interface IUniswapV2Pair {
    function getReserves()
        external
        view
        returns (
            uint112 reserve0,
            uint112 reserve1,
            uint32 blockTimestampLast
        );
}

interface IUniswapV2Router02 {
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        external
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        );

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);

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

interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address to, uint256 value) external returns (bool);
}

contract SwapUSDCAndBurnAPI3AndLpWithUSDCPair {
    struct Liquidity {
        uint32 withdrawTime;
        uint224 amount;
    }

    address public constant API3_TOKEN_ADDR =
        0x0b38210ea11411557c13457D4dA7dC6ea731B88a;
    address public constant SUSHI_ROUTER_ADDR =
        0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    address public constant USDC_TOKEN_ADDR =
        0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant WETH_ADDR =
        0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    uint256 public immutable lpWithdrawDelay;

    IUniswapV2Router02 public sushiRouter;
    IUniswapV2Pair public usdcApi3Pair;
    IAPI3 public iAPI3Token;
    IERC20 public iUSDCToken;
    IERC20 public iLPToken;

    uint256 public lpAddIndex;
    uint256 public lpRedeemIndex;
    mapping(uint256 => Liquidity) public liquidityAdds;

    error NoAPI3Tokens();
    error NoRedeemableLPTokens();
    error NoUSDCTokens();

    event API3Burned(uint256 amountBurned);
    event LiquidityProvided(uint256 liquidityAdded, uint256 indexed lpIndex);
    event LiquidityRemoved(uint256 liquidityRemoved, uint256 indexed lpIndex);

    /// @param _lpTokenAddr: address of API3/USDC pair LP token contract
    /// @param _lpWithdrawDelay: delay (in seconds) before liquidity may be withdrawn, e.g. 31557600 for one year
    constructor(address _lpTokenAddr, uint256 _lpWithdrawDelay) payable {
        lpWithdrawDelay = _lpWithdrawDelay;
        sushiRouter = IUniswapV2Router02(SUSHI_ROUTER_ADDR);
        usdcApi3Pair = IUniswapV2Pair(_lpTokenAddr);
        iAPI3Token = IAPI3(API3_TOKEN_ADDR);
        iUSDCToken = IERC20(USDC_TOKEN_ADDR);
        iLPToken = IERC20(_lpTokenAddr);
        iAPI3Token.updateBurnerStatus(true);
        iAPI3Token.approve(SUSHI_ROUTER_ADDR, type(uint256).max);
        iUSDCToken.approve(SUSHI_ROUTER_ADDR, type(uint256).max);
        iLPToken.approve(SUSHI_ROUTER_ADDR, type(uint256).max);
    }

    /// @notice receives ETH sent to address(this) except if from AMM router, swaps for API3 tokens, and calls _burnAPI3()
    /// also useful for burning any leftover/dust API3 tokens held by or sent to this contract
    receive() external payable {
        if (msg.sender != SUSHI_ROUTER_ADDR) {
            sushiRouter.swapExactETHForTokens{value: msg.value}(
                1,
                _getPathForETHtoAPI3(),
                address(this),
                block.timestamp
            );
            _burnAPI3();
        } else {}
    }

    /** @notice if at least 50000 USDC reserves in API3/USDC pool, swaps 3/4 of USDC held by address(this) for API3 tokens.
     ** If the API3/USDC does not have sufficient reserves, 3/4 of the USDC is swapped for ETH, which is then swapped for API3 tokens.
     ** Then calls _lpAndBurn(). Callable by anyone. */
    /// @dev checks API3/USDC liquidity to prevent manipulation/MEV attacks if too low, in which case the API3/ETH pair is used.
    function swapUSDCToAPI3AndLP() external {
        uint256 usdcBal = iUSDCToken.balanceOf(address(this));
        if (usdcBal == 0) revert NoUSDCTokens();
        // check if API3/USDC pair has sufficient liquidity (currently at least 50000 USDC reserve) to swap, otherwise use API3/ETH pair
        // USDC_TOKEN_ADDR has a higher sort order than API3_TOKEN_ADDR, so USDC_TOKEN_ADDR is token1 in usdcApi3Pair
        // see: https://docs.uniswap.org/protocol/V2/reference/smart-contracts/pair#token0
        (, uint112 reserveUsdc, ) = usdcApi3Pair.getReserves();
        if (reserveUsdc > 50000000000) {
            sushiRouter.swapExactTokensForTokens(
                (usdcBal * 3) / 4,
                1,
                _getPathForUSDCtoAPI3(),
                address(this),
                block.timestamp
            );
        } else {
            sushiRouter.swapExactTokensForETH(
                (usdcBal * 3) / 4,
                0,
                _getPathForUSDCtoETH(),
                payable(address(this)),
                block.timestamp
            );
            sushiRouter.swapExactETHForTokens{value: (address(this).balance)}(
                1,
                _getPathForETHtoAPI3(),
                address(this),
                block.timestamp
            );
        }
        // use remaining USDC to LP
        _lpAndBurn(usdcBal - ((usdcBal * 3) / 4));
    }

    /** @dev checks earliest Liquidity struct to see if any LP tokens are redeemable,
     ** then redeems that amount of liquidity to this address (which is entirely converted and burned in API3 tokens),
     ** then deletes that mapped struct in liquidityAdds[] and increments the lpRedeemIndex */
    /// @notice redeems the earliest available liquidity; redeemed API3 tokens are burned via _burnAPI3() and redeemed ETH is converted to API3 tokens and burned
    function redeemLP() external {
        Liquidity memory liquidity = liquidityAdds[lpRedeemIndex];
        if (uint256(liquidity.withdrawTime) > block.timestamp)
            revert NoRedeemableLPTokens();
        uint256 _redeemableLpTokens = uint256(liquidity.amount);
        if (_redeemableLpTokens == 0) {
            delete liquidityAdds[lpRedeemIndex];
            unchecked {
                ++lpRedeemIndex;
            }
        } else {
            _redeemLP(_redeemableLpTokens);
        }
    }

    /** @dev checks applicable Liquidity struct to see if any LP tokens are redeemable,
     ** then redeems that amount of liquidity to this address (which is entirely converted and burned in API3 tokens),
     ** then deletes that mapped struct in liquidityAdds[]. Implemented in case of lpAddIndex--lpRedeemIndex mismatch */
    /// @notice redeems specifically indexed liquidity; redeemed API3 tokens are burned via _burnAPI3 and redeemed ETH is converted to API3 tokens and burned
    /// @param _lpRedeemIndex: index of liquidity in liquidityAdds[] mapping to be redeemed
    function redeemSpecificLP(uint256 _lpRedeemIndex) external {
        Liquidity memory liquidity = liquidityAdds[_lpRedeemIndex];
        if (uint256(liquidity.withdrawTime) > block.timestamp)
            revert NoRedeemableLPTokens();
        uint256 _redeemableLpTokens = uint256(liquidity.amount);
        if (_redeemableLpTokens == 0) {
            delete liquidityAdds[_lpRedeemIndex];
        } else {
            _redeemSpecificLP(_redeemableLpTokens, _lpRedeemIndex);
        }
    }

    /// @notice burns all API3 tokens held by this contract
    function _burnAPI3() internal {
        uint256 api3Bal = iAPI3Token.balanceOf(address(this));
        if (api3Bal == 0) revert NoAPI3Tokens();
        iAPI3Token.burn(api3Bal);
        emit API3Burned(api3Bal);
    }

    /// @notice LPs the remaining ETH and 1/3 of the API3 tokens, and calls _burnAPI3()
    /** @dev LP has 10% buffer. Liquidity locked for lpWithdrawDelay. To implement one-way liquidity,
     ** insert "iLPToken.transfer(address(0), iLPToken.balanceOf(address(this)));" before _burnAPI3()
     ** and remove redeemLP() and redeemSpecificLP() functions. */
    function _lpAndBurn(uint256 _usdcBal) internal {
        uint256 api3Bal = iAPI3Token.balanceOf(address(this));
        if (api3Bal == 0) revert NoAPI3Tokens();
        (, , uint256 liquidity) = sushiRouter.addLiquidity(
            API3_TOKEN_ADDR,
            USDC_TOKEN_ADDR,
            api3Bal / 3,
            _usdcBal,
            ((api3Bal * 3) / 10), // 90% of 1/3 of the api3Bal
            ((_usdcBal * 9) / 10), // 90% of the _usdcBal, which should be approx. 1/3 of the api3Bal in value
            address(this),
            block.timestamp
        );
        emit LiquidityProvided(liquidity, lpAddIndex);
        liquidityAdds[lpAddIndex] = Liquidity(
            uint32(block.timestamp + lpWithdrawDelay),
            uint224(liquidity)
        );
        unchecked {
            ++lpAddIndex;
        }
        _burnAPI3();
    }

    /// @notice redeems the LP for the current index, swaps redeemed ETH for API3 tokens, and burns all API3 tokens
    function _redeemLP(uint256 _redeemableLpTokens) internal {
        sushiRouter.removeLiquidity(
            API3_TOKEN_ADDR,
            USDC_TOKEN_ADDR,
            _redeemableLpTokens,
            0,
            0,
            payable(address(this)),
            block.timestamp
        );
        delete liquidityAdds[lpRedeemIndex];
        emit LiquidityRemoved(_redeemableLpTokens, lpRedeemIndex);
        unchecked {
            ++lpRedeemIndex;
        }
        sushiRouter.swapExactTokensForTokens(
            iUSDCToken.balanceOf(address(this)),
            1,
            _getPathForUSDCtoAPI3(),
            address(this),
            block.timestamp
        );
        _burnAPI3();
    }

    /// @notice redeems the LP for the index submitted as a param to redeemSpecificLP(), swaps redeemed ETH for API3 tokens, and burns all API3 tokens
    function _redeemSpecificLP(
        uint256 _redeemableLpTokens,
        uint256 _lpRedeemIndex
    ) internal {
        sushiRouter.removeLiquidity(
            API3_TOKEN_ADDR,
            USDC_TOKEN_ADDR,
            _redeemableLpTokens,
            0,
            0,
            address(this),
            block.timestamp
        );
        delete liquidityAdds[_lpRedeemIndex];
        emit LiquidityRemoved(_redeemableLpTokens, _lpRedeemIndex);
        sushiRouter.swapExactTokensForTokens(
            iUSDCToken.balanceOf(address(this)),
            1,
            _getPathForUSDCtoAPI3(),
            address(this),
            block.timestamp
        );
        _burnAPI3();
    }

    /// @return path: the router path for ETH/API3 swap
    function _getPathForETHtoAPI3() internal pure returns (address[] memory) {
        address[] memory path = new address[](2);
        path[0] = WETH_ADDR;
        path[1] = API3_TOKEN_ADDR;
        return path;
    }

    /// @return path: the router path for USDC/API3 swap
    function _getPathForUSDCtoAPI3() internal pure returns (address[] memory) {
        address[] memory path = new address[](2);
        path[0] = USDC_TOKEN_ADDR;
        path[1] = API3_TOKEN_ADDR;
        return path;
    }

    /// @return path: the router path for USDC/ETH swap
    function _getPathForUSDCtoETH() internal pure returns (address[] memory) {
        address[] memory path = new address[](2);
        path[0] = USDC_TOKEN_ADDR;
        path[1] = WETH_ADDR;
        return path;
    }
}
