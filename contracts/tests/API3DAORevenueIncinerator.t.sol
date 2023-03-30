// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.12;

import "forge-std/Test.sol";
import "src/API3DAORevenueIncinerator.sol";

/// @notice foundry framework testing of OSS_Tech's contract provided here: https://forum.api3.org/t/api3-dao-revenue-incinerator/1781/7
/** @dev test using mainnet fork in order to use actual live relevant liquidity conditions for the Uniswap v2 pairs of API3-ETH and ETH-USDC, example commands:
 *** forge test -vvvv --fork-url https://eth.llamarpc.com
 *** forge test -vvvv --fork-url https://eth-mainnet.gateway.pokt.network/v1/5f3453978e354ab992c4da79
 *** or see https://ethereumnodes.com/ for alternatives */

/// @dev for allowance tests
interface IERC20Token {
    function allowance(
        address owner,
        address spender
    ) external returns (uint256);
}

/// @notice test contract for API3DAORevenueIncinerator using Foundry
contract API3DAORevenueIncineratorTest is Test {
    API3DAORevenueIncinerator public incinerator;

    /// @dev these variables are internal in 'API3DAORevenueIncinerator', so they've been repeated here
    address internal constant API3_TOKEN_ADDR =
        0x0b38210ea11411557c13457D4dA7dC6ea731B88a;
    address internal constant LP_TOKEN_ADDR =
        0x4Dd26482738bE6C06C31467a19dcdA9AD781e8C4;
    address internal constant UNI_ROUTER_ADDR =
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address internal constant USDC_TOKEN_ADDR =
        0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    uint256 internal constant YEAR_IN_SECONDS = 31557600;

    error EthCallFailed();

    function setUp() public {
        incinerator = new API3DAORevenueIncinerator();
    }

    function testConstructor() public {
        assertEq(
            address(incinerator.router()),
            UNI_ROUTER_ADDR,
            "router address did not initialize"
        );
        assertEq(
            address(incinerator.iAPI3Token()),
            API3_TOKEN_ADDR,
            "API3 token address did not initialize"
        );
        assertEq(
            IERC20Token(API3_TOKEN_ADDR).allowance(
                address(incinerator),
                UNI_ROUTER_ADDR
            ),
            type(uint256).max,
            "API3 approval failed"
        );
        assertEq(
            IERC20Token(USDC_TOKEN_ADDR).allowance(
                address(incinerator),
                UNI_ROUTER_ADDR
            ),
            type(uint256).max,
            "USDC approval failed"
        );
        assertEq(
            IERC20Token(LP_TOKEN_ADDR).allowance(
                address(incinerator),
                UNI_ROUTER_ADDR
            ),
            type(uint256).max,
            "LP approval failed"
        );
    }

    /// @notice test the 'receive()' function, fuzzing amount of wei sent
    /// @param weiAmount: amount of wei to be sent to 'receive()' in incinerator
    /// @dev maximum constraint on weiAmount is 1e20 for now (100 ETH)
    function testReceive(uint256 weiAmount) public payable {
        // assume 'weiAmount' is nonzero, as otherwise 'receive()' will not be invoked anyway
        vm.assume(weiAmount > 0);
        vm.assume(weiAmount < 1e20);
        vm.deal(address(this), weiAmount);

        (bool sent, ) = address(incinerator).call{value: weiAmount}("");
        if (!sent) revert EthCallFailed();

        // all msg.value should have been swapped to API3 tokens
        assertEq(
            address(incinerator).balance,
            0,
            "Not all ETH was swapped to API3"
        );
        // all API3 tokens in the incinerator should be burned via the call to '_burnAPI3()'
        assertEq(
            IERC20(API3_TOKEN_ADDR).balanceOf(address(incinerator)),
            0,
            "Not all API3 tokens were burned"
        );
    }

    /// @notice test the 'swapUSDCToAPI3AndLpWithETHPair()' function, fuzzing amounts of USDC
    /// @param usdcBalance: amount of USDC to give to the incinerator to test 'swapUSDCToAPI3AndLpWithETHPair()', fuzz
    function testSwapUSDCtoAPI3AndLPWithETHPair(uint256 usdcBalance) public {
        /// assume an amount of USDC that is low enough for the current amount of liquidity (less than 10,000, incl. 6 USDC decimals)
        /// @dev we know too high of a USDC amount in a swap will revert due to slippage so we assume a < 10000 'usdcBalance'; this threshold will increase over time as liquidity increases
        vm.assume(usdcBalance < 1e10);

        // don't run out of gas
        vm.prank(address(1));
        vm.deal(address(1), 10000 ether);

        // mint 'usdcBalance' amount of USDC to the incinerator
        deal(USDC_TOKEN_ADDR, address(incinerator), usdcBalance, false);

        // store to test index increment and _withdrawTime later, and '_revert' to only access test assert statements if the incinerator call does not revert
        uint256 _index = incinerator.lpAddIndex();
        uint256 _deadline = (block.timestamp + YEAR_IN_SECONDS) - 1;
        bool _revert;

        // expect a revert if usdcBalance == 0
        if (IERC20(USDC_TOKEN_ADDR).balanceOf(address(incinerator)) == 0) {
            _revert = true;
            vm.expectRevert();
        }

        // call 'swapUSDCToAPI3AndLpWithETHPair()'
        incinerator.swapUSDCToAPI3AndLpWithETHPair{gas: gasleft()}();

        if (!_revert) {
            (uint256 _withdrawTime, uint256 _amount) = incinerator
                .liquidityAdds(_index);
            assertGt(_amount, 0, "add liquidity amount should be > 0");
            assertGt(
                incinerator.lpAddIndex(),
                _index,
                "lpAddIndex did not increment"
            );
            assertGt(
                _withdrawTime,
                _deadline,
                "withdraw time should be at least a year from block.timestamp"
            );
            // all USDC tokens in the incinerator should have been swapped
            assertEq(
                IERC20(USDC_TOKEN_ADDR).balanceOf(address(incinerator)),
                0,
                "Not all USDC tokens were swapped"
            );
        }
    }

    /// @notice test the 'swapFractionUSDCToAPI3AndLpWithETHPair()' function, fuzzing amounts of USDC and divisors
    /// @param usdcBalance: amount of USDC to give to the incinerator to test 'swapUSDCToAPI3AndLpWithETHPair()', fuzz
    /// @param divisor divisor for division operation of this contract's USDC balance to then swap and LP, which must be > 0.
    function testswapFractionUSDCToAPI3AndLpWithETHPair(
        uint256 usdcBalance,
        uint256 divisor
    ) public {
        // assume an amount of USDC that is low enough for the current amount of liquidity (less than 10,000, incl. 6 USDC decimals)
        /// @dev we know too high of a USDC amount in a swap will revert due to slippage so we assume a < 10000 'usdcBalance'; this threshold will increase over time as liquidity increases
        vm.assume(usdcBalance < 1e10);

        // don't run out of gas
        vm.prank(address(1));
        vm.deal(address(1), 10000 ether);

        // mint 'usdcBalance' amount of USDC to the incinerator
        deal(USDC_TOKEN_ADDR, address(incinerator), usdcBalance, false);

        // store to test index increment and '_withdrawTime' later, and '_revert' to only access test assert statements if the incinerator call does not revert
        uint256 _index = incinerator.lpAddIndex();
        uint256 _deadline = (block.timestamp + YEAR_IN_SECONDS) - 1;
        bool _revert;
        uint256 _swapAmount;
        if (divisor > 0)
            _swapAmount =
                IERC20(USDC_TOKEN_ADDR).balanceOf(address(incinerator)) /
                divisor;

        // expect revert if 'divisor' == 0 or if 'usdcBalance' is < 'divisor', as this will result in a swap amount of 0
        if (
            divisor == 0 ||
            IERC20(USDC_TOKEN_ADDR).balanceOf(address(incinerator)) == 0 ||
            _swapAmount == 0
        ) {
            _revert = true;
            vm.expectRevert();
        }
        // call 'swapFractionUSDCToAPI3AndLpWithETHPair()' passing 'divisor'
        incinerator.swapFractionUSDCToAPI3AndLpWithETHPair{gas: gasleft()}(
            divisor
        );
        // the following assertions should hold if the 'swapFractionUSDCToAPI3AndLpWithETHPair()' call did not revert
        if (!_revert) {
            (uint256 _withdrawTime, uint256 _amount) = incinerator
                .liquidityAdds(_index);
            assertGt(_amount, 0, "add liquidity amount should be > 0");
            assertGt(
                incinerator.lpAddIndex(),
                _index,
                "lpAddIndex did not increment"
            );
            assertGt(
                _withdrawTime,
                _deadline,
                "withdraw time should be at least a year from block.timestamp"
            );
            // post-swap balance of USDC in the incinerator should equal the starting balance minus (usdcBalance / divisor), which is the '_swapAmount'
            assertEq(
                usdcBalance - _swapAmount,
                IERC20(USDC_TOKEN_ADDR).balanceOf(address(incinerator)),
                "USDC balance post-call should equal the start balance minus the _swapAmount"
            );
        }
    }

    /// @notice test the 'redeemLP()' function which attempts to redeem the LP tokens corresponding to the 'lpRedeemIndex' state variable, then increments it
    function testredeemLP() public {
        uint256 _currentLpRedeemIndex = incinerator.lpRedeemIndex();
        (uint256 _withdrawTime, ) = incinerator.liquidityAdds(
            _currentLpRedeemIndex
        );

        // redeemLP should revert because a year has not yet passed from the time liquidity has been provided
        if (_withdrawTime > block.timestamp) vm.expectRevert();
        incinerator.redeemLP();

        // set block.timestamp to a year and a second from now to test redeem
        vm.warp(block.timestamp + YEAR_IN_SECONDS + 1);

        incinerator.redeemLP();

        // regardless of whether there were redeemable LP tokens, the 'lpRedeemIndex' should increment
        assertGt(
            incinerator.lpRedeemIndex(),
            _currentLpRedeemIndex,
            "lpRedeemIndex did not increment"
        );
        // all ETH in the incinerator should have been swapped to API3 tokens
        assertEq(
            address(incinerator).balance,
            0,
            "Not all ETH was swapped to API3"
        );
        // all API3 tokens in the incinerator should be burned via the call to '_burnAPI3()'
        assertEq(
            IERC20(API3_TOKEN_ADDR).balanceOf(address(incinerator)),
            0,
            "Not all API3 tokens were burned"
        );
    }

    /// @notice test the 'redeemSpecificLP()' function, fuzzing 'lpRedeemIndex'
    /// @dev attempts to redeem the LP tokens corresponding to the passed 'lpRedeemIndex' parameter; if no tokens to be redeemed, deletes the 'liquidityAdds' mapping
    /// @param lpRedeemIndex: index of liquidity in liquidityAdds[] mapping to be redeemed
    function testredeemSpecificLP(uint256 lpRedeemIndex) public {
        (uint256 _withdrawTime, ) = incinerator.liquidityAdds(lpRedeemIndex);

        // 'redeemSpecificLP()' should revert because a year has not yet passed from the time liquidity has been provided
        if (_withdrawTime > block.timestamp) vm.expectRevert();
        incinerator.redeemSpecificLP(lpRedeemIndex);

        // set block.timestamp to a year and a second from now to test redeem
        vm.warp(block.timestamp + YEAR_IN_SECONDS + 1);

        incinerator.redeemSpecificLP(lpRedeemIndex);

        //regardless of whether there were redeemable LP tokens, the 'liquidityAdds' mapping should be deleted, resetting the withdrawTime struct member to default value of 0
        (uint256 _updatedWithdrawTime, ) = incinerator.liquidityAdds(
            lpRedeemIndex
        );
        assertEq(
            _updatedWithdrawTime,
            0,
            "liquidityAdds mapping for 'lpRedeemIndex' was not deleted"
        );
        // all ETH in the incinerator should have been swapped to API3 tokens
        assertEq(
            address(incinerator).balance,
            0,
            "Not all ETH was swapped to API3"
        );
        // all API3 tokens in the incinerator should be burned via the call to '_burnAPI3()'
        assertEq(
            IERC20(API3_TOKEN_ADDR).balanceOf(address(incinerator)),
            0,
            "Not all API3 tokens were burned"
        );
    }
}
