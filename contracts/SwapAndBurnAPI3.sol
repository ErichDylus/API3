//SPDX-License-Identifier: MIT
/*****
 ***** this code and any deployments of this code are strictly provided as-is;
 ***** no guarantee, representation or warranty is being made, express or implied, as to the safety or correctness of the code
 ***** or any smart contracts or other software deployed from these files,
 ***** in accordance with the disclosures and licenses found here: https://github.com/ErichDylus/API3/blob/main/contracts/README.md
 ***** this code is not audited, and users, developers, or adapters of these files should proceed with caution and use at their own risk.
 ****/

pragma solidity >=0.8.4;

/// @title Swap and Burn API3
/** @notice simple programmatic token burn per API3 whitepaper: uses Sushiswap router to swap USDC held by this contract for API3 tokens,
 *** LPs half (redeemable to this contract after the lpWithdrawDelay provided in constructor), then burns all remaining API3 tokens via the token contract;
 *** also auto-swaps any ETH sent directly to this contract for API3 tokens, which are then burned via the token contract */

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

    function removeLiquidityETH(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountToken, uint256 amountETH);

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

contract SwapAndBurnAPI3 {
    struct Liquidity {
        uint32 withdrawTime;
        uint224 amount;
    }

    address public constant API3_TOKEN_ADDR =
        0x0b38210ea11411557c13457D4dA7dC6ea731B88a;
    address public constant LP_TOKEN_ADDR =
        0xA8AEC03d5Cf2824fD984ee249493d6D4D6740E61;
    address public constant SUSHI_ROUTER_ADDR =
        0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    address public constant USDC_TOKEN_ADDR =
        0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant WETH_ADDR =
        0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    uint256 public immutable lpWithdrawDelay;

    IUniswapV2Router02 public sushiRouter;
    IAPI3 public iAPI3Token;
    IERC20 public iUSDCToken;
    IERC20 public iLPToken;

    uint256 lpAddIndex;
    uint256 lpRedeemIndex;
    mapping(uint256 => Liquidity) public liquidityAdds;

    error NoAPI3Tokens();
    error NoRedeemableLPTokens();
    error NoUSDCTokens();

    event API3Burned(uint256 amountBurned);
    event LiquidityProvided(uint256 liquidityAdded, uint256 indexed lpIndex);
    event LiquidityRemoved(uint256 liquidityRemoved, uint256 indexed lpIndex);

    /// @param _lpWithdrawDelay: delay (in seconds) before liquidity may be withdrawn, e.g. 31557600 for one year
    constructor(uint256 _lpWithdrawDelay) payable {
        lpWithdrawDelay = _lpWithdrawDelay;
        sushiRouter = IUniswapV2Router02(SUSHI_ROUTER_ADDR);
        iAPI3Token = IAPI3(API3_TOKEN_ADDR);
        iUSDCToken = IERC20(USDC_TOKEN_ADDR);
        iLPToken = IERC20(LP_TOKEN_ADDR);
        iAPI3Token.updateBurnerStatus(true);
        iAPI3Token.approve(SUSHI_ROUTER_ADDR, type(uint256).max);
        iUSDCToken.approve(SUSHI_ROUTER_ADDR, type(uint256).max);
        iLPToken.approve(SUSHI_ROUTER_ADDR, type(uint256).max);
    }

    /// @notice receives ETH sent to address(this) except if from sushiRouter, swaps for API3, and calls the internal _burnAPI3() function
    receive() external payable {
        if (msg.sender != SUSHI_ROUTER_ADDR) {
            uint256 amountEth = msg.value + address(this).balance;
            sushiRouter.swapExactETHForTokens{value: amountEth}(
                0,
                _getPathForETHtoAPI3(),
                address(this),
                block.timestamp
            );
            _burnAPI3();
        } else {}
    }

    fallback() external payable {}

    /// @notice swaps USDC held by address(this) for ETH, swaps 3/4 of the ETH for API3
    function swapUSDCToAPI3AndEth() external {
        uint256 usdcBal = iUSDCToken.balanceOf(address(this));
        if (usdcBal == 0) revert NoUSDCTokens();
        sushiRouter.swapExactTokensForETH(
            usdcBal,
            0,
            _getPathForUSDCtoETH(),
            payable(address(this)),
            block.timestamp
        );
        sushiRouter.swapExactETHForTokens{
            value: (address(this).balance * 3) / 4
        }(0, _getPathForETHtoAPI3(), address(this), block.timestamp);
    }

    /// @notice LPs the remaining ETH and 1/3 of the API3, and calls the internal _burnAPI3() function
    /** @dev LP has 10% buffer. Liquidity locked for a year.
     ** To implement one-way liquidity, insert "iLPToken.transfer(address(0), iLPToken.balanceOf(address(this)));" before _burnAPI3(). Callable by anyone. */
    // current error: INSUFFICIENT_B_AMOUNT; check calculation of ETH
    function lpAndBurn() external {
        uint256 api3Bal = iAPI3Token.balanceOf(address(this));
        require(api3Bal != 0, "Nothing to LP");
        uint256 ethBal = address(this).balance;
        (, , uint256 liquidity) = sushiRouter.addLiquidityETH{
            value: ethBal
        }(
            API3_TOKEN_ADDR,
            api3Bal / 3,
            (api3Bal * 3) / 10, // 90% of 1/3 of the api3Bal
            (ethBal * 9) / 10, // 90% of the ethBal, which should be approx. 1/3 of the api3Bal in value
            payable(address(this)),
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

    /** @dev checks earliest Liquidity struct to see if any LP tokens are redeemable,
     ** then redeems that amount of liquidity to this address (which is entirely burned in API3, either by receive() or _burnAPI3()),
     ** then deletes that mapped struct in liquidityAdds[] and increments the lpRedeemIndex */
    /// @notice redeems the earliest available liquidity; redeemed API3 is burned via _burnAPI3 and redeemed ETH is burned in API3 via receive()
    /// @return _redeemableLpTokens: the amount of redeemed liquidity
    function redeemLP() external returns (uint256) {
        Liquidity memory liquidity = liquidityAdds[lpRedeemIndex];
        if (liquidity.withdrawTime > uint32(block.timestamp))
            revert NoRedeemableLPTokens();
        uint256 _redeemableLpTokens = uint256(liquidity.amount);
        if (_redeemableLpTokens == 0) {
            delete liquidityAdds[lpRedeemIndex];
            unchecked {
                ++lpRedeemIndex;
            }
        } else {
            sushiRouter.removeLiquidityETH(
                LP_TOKEN_ADDR,
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
            _burnAPI3();
        }
        return (_redeemableLpTokens);
    }

    /** @dev checks applicable Liquidity struct to see if any LP tokens are redeemable,
     ** then redeems that amount of liquidity to this address (which is entirely burned in API3, either by receive() or _burnAPI3()),
     ** then deletes that mapped struct in liquidityAdds[]. Implemented in case of lpAddIndex--lpRedeemIndex mismatch */
    /// @notice redeems specifically indexed liquidity; redeemed API3 is burned via _burnAPI3 and redeemed ETH is burned in API3 via receive()
    /// @param _lpRedeemIndex: index of liquidity in liquidityAdds[] mapping to be redeemed
    /// @return _redeemableLpTokens: the amount of redeemed liquidity
    function redeemSpecificLP(uint256 _lpRedeemIndex)
        external
        returns (uint256)
    {
        Liquidity memory liquidity = liquidityAdds[_lpRedeemIndex];
        if (liquidity.withdrawTime > uint32(block.timestamp))
            revert NoRedeemableLPTokens();
        uint256 _redeemableLpTokens = uint256(liquidity.amount);
        if (_redeemableLpTokens == 0) {
            delete liquidityAdds[_lpRedeemIndex];
        } else {
            sushiRouter.removeLiquidityETH(
                LP_TOKEN_ADDR,
                _redeemableLpTokens,
                0,
                0,
                payable(address(this)),
                block.timestamp
            );
            delete liquidityAdds[_lpRedeemIndex];
            emit LiquidityRemoved(_redeemableLpTokens, _lpRedeemIndex);
            _burnAPI3();
        }
        return (_redeemableLpTokens);
    }

    function _burnAPI3() internal {
        uint256 api3Bal = iAPI3Token.balanceOf(address(this));
        if (api3Bal == 0) revert NoAPI3Tokens();
        iAPI3Token.burn(api3Bal);
        emit API3Burned(api3Bal);
    }

    /// @return path: the router path for ETH/API3 swap
    function _getPathForETHtoAPI3() internal pure returns (address[] memory) {
        address[] memory path = new address[](2);
        path[0] = WETH_ADDR;
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
