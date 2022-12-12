//SPDX-License-Identifier: MIT
/*****
 ***** this code and any deployments of this code are strictly provided as-is;
 ***** no guarantee, representation or warranty is being made, express or implied, as to the safety or correctness of the code
 ***** or any smart contracts or other software deployed from these files,
 ***** in accordance with the disclosures and disclaimers found here: https://github.com/ErichDylus/API3/blob/main/contracts/README.md
 ***** this code is not audited, and users, developers, or adapters of these files should proceed with caution and use at their own risk.
 ****/

pragma solidity >=0.8.4;

/// @title Swap USDC and Burn API3
/** @notice simple programmatic token burn of excess USDC revenue per API3 whitepaper: uses AMM DEX
 *** to swap half of USDC held by this contract for API3 tokens, half for ETH, to LP;
 *** entire LP is redeemable to this contract after one year, then burns all remaining API3 tokens via the token contract;
 *** also auto-swaps any ETH sent directly to this contract for API3 tokens, which are then burned via the token contract */
/// @dev UniV2 router and LP token addresses provided in constructor. In the event of ETH-API3 imbalance (causing _lpApi3Eth() to revert),
/// swapUSDCToAPI3AndBurn() may be called to swap all held USDC and ETH to API3, and burn all API3

import {
    mulDivDown
} from "https://github.com/Sol-DAO/solbase/blob/main/src/utils/FixedPointMath.sol"; // SolDAO FixedPointMath

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
}

contract SwapUSDCAndBurnAPI3 {
    struct Liquidity {
        uint256 withdrawTime;
        uint256 amount;
    }

    address public constant API3_TOKEN_ADDR =
        0x0b38210ea11411557c13457D4dA7dC6ea731B88a;
    address public constant LP_TOKEN_ADDR =
        0x4Dd26482738bE6C06C31467a19dcdA9AD781e8C4;
    address public constant UNI_ROUTER_ADDR =
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public constant USDC_TOKEN_ADDR =
        0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant WETH_TOKEN_ADDR =
        0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    IUniswapV2Router02 public immutable router;
    IAPI3 public immutable iAPI3Token;

    uint256 public lpAddIndex;
    uint256 public lpRedeemIndex;
    mapping(uint256 => Liquidity) public liquidityAdds;

    error NoAPI3Tokens();
    error NoRedeemableLPTokens();
    error NoUSDCTokens();

    event API3Burned(uint256 amountBurned);
    event LiquidityProvided(uint256 liquidityAdded, uint256 indexed lpIndex);
    event LiquidityRemoved(uint256 liquidityRemoved, uint256 indexed lpIndex);

    constructor() payable {
        address uniRouter = UNI_ROUTER_ADDR;
        router = IUniswapV2Router02(uniRouter);
        iAPI3Token = IAPI3(API3_TOKEN_ADDR);
        IAPI3(API3_TOKEN_ADDR).updateBurnerStatus(true);
        IAPI3(API3_TOKEN_ADDR).approve(uniRouter, type(uint256).max);
        IERC20(USDC_TOKEN_ADDR).approve(uniRouter, type(uint256).max);
        IERC20(LP_TOKEN_ADDR).approve(uniRouter, type(uint256).max);
    }

    /// @notice receives ETH sent to address(this) except if from router, swaps for API3 tokens, and calls _burnAPI3()
    /// also useful for burning any leftover/dust API3 tokens held by or sent to this contract
    receive() external payable {
        if (msg.sender != UNI_ROUTER_ADDR) {
            router.swapExactETHForTokens{value: msg.value}(
                1,
                _getPathForETHtoAPI3(),
                address(this),
                block.timestamp
            );
            _burnAPI3();
        } else {}
    }

    /// @notice swap all USDC for ETH, swap 1/2 of the ETH for API3 tokens, and LP API3/ETH
    /// @dev swaps USDC held by address(this) for ETH, swaps 1/2 of the ETH for API3 tokens, then calls _lpApi3Eth(). Callable by anyone.
    function swapUSDCToAPI3AndLpWithETHPair() external {
        uint256 usdcBal = IERC20(USDC_TOKEN_ADDR).balanceOf(address(this));
        if (usdcBal == 0) revert NoUSDCTokens();
        router.swapExactTokensForETH(
            usdcBal,
            0,
            _getPathForUSDCtoETH(),
            payable(address(this)),
            block.timestamp
        );
        router.swapExactETHForTokens{
            value: mulDivDown(address(this).balance, 1, 2)
        }(0, _getPathForETHtoAPI3(), address(this), block.timestamp);
        _lpApi3Eth();
    }

    /** @dev checks earliest Liquidity struct to see if any LP tokens are redeemable,
     ** then redeems that amount of liquidity to this address (which is entirely converted and burned in API3 tokens via _burnAPI3()),
     ** then deletes that mapped struct in liquidityAdds[] and increments the lpRedeemIndex */
    /// @notice redeems the earliest available liquidity; redeemed API3 tokens are burned and redeemed ETH is converted to API3 tokens and burned
    function redeemLP() external {
        if (liquidityAdds[lpRedeemIndex].withdrawTime > block.timestamp)
            revert NoRedeemableLPTokens();
        uint256 _redeemableLpTokens = liquidityAdds[lpRedeemIndex].amount;
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
     ** then redeems that amount of liquidity to this address (which is entirely converted and burned in API3 tokens via _burnAPI3()),
     ** then deletes that mapped struct in liquidityAdds[]. Implemented in case of lpAddIndex--lpRedeemIndex mismatch */
    /// @notice redeems specifically indexed liquidity; redeemed API3 tokens are burned and redeemed ETH is converted to API3 tokens and burned
    /// @param _lpRedeemIndex: index of liquidity in liquidityAdds[] mapping to be redeemed
    function redeemSpecificLP(uint256 _lpRedeemIndex) external {
        if (liquidityAdds[_lpRedeemIndex].withdrawTime > block.timestamp)
            revert NoRedeemableLPTokens();
        uint256 _redeemableLpTokens = liquidityAdds[_lpRedeemIndex].amount;
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

    /// @notice LPs ETH and API3 tokens to API3/ETH pair
    /// @dev LP has 10% buffer. Liquidity locked for 31557600 seconds (one year).
    function _lpApi3Eth() internal {
        uint256 api3Bal = iAPI3Token.balanceOf(address(this));
        if (api3Bal == 0) revert NoAPI3Tokens();
        uint256 ethBal = address(this).balance;
        (, , uint256 liquidity) = router.addLiquidityETH{value: ethBal}(
            API3_TOKEN_ADDR,
            api3Bal,
            mulDivDown(api3Bal, 9, 10), // 90% of the api3Bal
            mulDivDown(ethBal, 9, 10), // 90% of the ethBal
            payable(address(this)),
            block.timestamp
        );
        emit LiquidityProvided(liquidity, lpAddIndex);
        unchecked {
            liquidityAdds[lpAddIndex] = Liquidity(
                block.timestamp + 31557600, // will not overflow on human timelines
                liquidity
            );
            ++lpAddIndex;
        }
    }

    /// @notice redeems the LP for the current index, swaps redeemed ETH for API3 tokens, and burns all API3 tokens
    function _redeemLP(uint256 _redeemableLpTokens) internal {
        router.removeLiquidityETH(
            API3_TOKEN_ADDR,
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
        router.swapExactETHForTokens{value: address(this).balance}(
            1,
            _getPathForETHtoAPI3(),
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
        router.removeLiquidityETH(
            API3_TOKEN_ADDR,
            _redeemableLpTokens,
            0,
            0,
            payable(address(this)),
            block.timestamp
        );
        delete liquidityAdds[_lpRedeemIndex];
        emit LiquidityRemoved(_redeemableLpTokens, _lpRedeemIndex);
        router.swapExactETHForTokens{value: address(this).balance}(
            1,
            _getPathForETHtoAPI3(),
            address(this),
            block.timestamp
        );
        _burnAPI3();
    }

    /// @return path: the router path for ETH/API3 swap
    function _getPathForETHtoAPI3() internal pure returns (address[] memory) {
        address[] memory path = new address[](2);
        path[0] = WETH_TOKEN_ADDR;
        path[1] = API3_TOKEN_ADDR;
        return path;
    }

    /// @return path: the router path for USDC/ETH swap
    function _getPathForUSDCtoETH() internal pure returns (address[] memory) {
        address[] memory path = new address[](2);
        path[0] = USDC_TOKEN_ADDR;
        path[1] = WETH_TOKEN_ADDR;
        return path;
    }
}
