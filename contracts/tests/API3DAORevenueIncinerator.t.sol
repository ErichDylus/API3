// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.12;

import "forge-std/Test.sol";
import "src/API3DAORevenueIncinerator.sol";

/// @notice foundry framework testing of OSS_Tech's contract provided here: https://forum.api3.org/t/api3-dao-revenue-incinerator/1781/7
/** @dev test using mainnet fork due to internal constants in contract being tested, and relevant liquidity conditions, example commands:
*** forge test -vvvv --fork-url https://eth.llamarpc.com
*** forge test -vvvv --fork-url https://eth-mainnet.gateway.pokt.network/v1/5f3453978e354ab992c4da79
*** or see https://ethereumnodes.com/ for alternatives */

/// @notice test contract for API3DAORevenueIncinerator using Foundry
contract API3DAORevenueIncineratorTest is Test {
    API3DAORevenueIncinerator public incinerator;

    // these variables are internal in 'API3DAORevenueIncinerator"
    address internal constant USDC_TOKEN =
        0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    uint256 internal constant YEAR_SECONDS = 31557600;

    error SendETH();

    function setUp() public {
        incinerator = new API3DAORevenueIncinerator();
    }

    function testConstructor() public {
        assertEq(
            address(incinerator.router()),
            0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D,
            "router address did not initialize"
        );
        assertEq(
            address(incinerator.iAPI3Token()),
            0x0b38210ea11411557c13457D4dA7dC6ea731B88a,
            "API3 token address did not initialize"
        );
    }

    function testReceive() public payable {
        vm.deal(address(this), 1 ether);

        (bool sent, ) = address(incinerator).call{value: 1 ether}("");
        require(sent, "Failed to send Ether");
    }

    /// @notice test the swapUSDCToAPI3AndLpWithETHPair function with varying amounts of USDC
    /// @param usdcBalance: amount of USDC to give to the incinerator to test 'swapUSDCToAPI3AndLpWithETHPair()', fuzz
    function testSwapUSDCtoAPI3AndLPWithETHPair(uint256 usdcBalance) public {
        // assume an amount of USDC that is low enough for the current amount of liquidity (greater than 1 but less than 10,000, incl. 6 USDC decimals)
        vm.assume(usdcBalance > 1e6);
        vm.assume(usdcBalance < 1e10);

        // don't run out of gas
        vm.prank(address(1));
        vm.deal(address(1), 10000 ether);

        // deal 'usdcBalance' amount of USDC to the incinerator
        deal(USDC_TOKEN, address(incinerator), usdcBalance, false);

        // store to test index increment and _withdrawTime later
        uint256 _index = incinerator.lpAddIndex();
        uint256 _deadline = (block.timestamp + YEAR_SECONDS) - 1;

        // call 'swapUSDCToAPI3AndLpWithETHPair()'
        incinerator.swapUSDCToAPI3AndLpWithETHPair{gas: gasleft()}();

        (uint256 _withdrawTime, uint256 _amount) = incinerator.liquidityAdds(
            _index
        );
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
    }

    /// @notice test the 'swapFractionUSDCToAPI3AndLpWithETHPair()' function with varying amounts of USDC and varying divisors
    /// @param usdcBalance: amount of USDC to give to the incinerator to test 'swapUSDCToAPI3AndLpWithETHPair()', fuzz
    /// @param divisor divisor for division operation of this contract's USDC balance to then swap and LP, which must be > 0.
    function testswapFractionUSDCToAPI3AndLpWithETHPair(
        uint256 usdcBalance,
        uint256 divisor
    ) public {
        // assume an amount of USDC that is low enough for the current amount of liquidity (greater than 1 but less than 10,000, incl. 6 USDC decimals)
        vm.assume(usdcBalance > 1e6);
        vm.assume(usdcBalance < 1e10);

        // don't run out of gas
        vm.prank(address(1));
        vm.deal(address(1), 10000 ether);

        // deal 'usdcBalance' amount of USDC to the incinerator
        deal(USDC_TOKEN, address(incinerator), usdcBalance, false);

        // store to test index increment and '_withdrawTime' later
        uint256 _index = incinerator.lpAddIndex();
        uint256 _deadline = (block.timestamp + YEAR_SECONDS) - 1;
        bool _revert;

        // expect revert if 'divisor' == 0 or if 'usdcBalance' is < 'divisor', as this will result in a swap amount of 0
        if (divisor == 0 || (usdcBalance / divisor) == 0) {
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
        vm.warp(block.timestamp + YEAR_SECONDS + 1);

        incinerator.redeemLP();

        //regardless of whether there were redeemable LP tokens, the 'lpRedeemIndex' should increment
        assertGt(
            incinerator.lpRedeemIndex(),
            _currentLpRedeemIndex,
            "lpRedeemIndex did not increment"
        );
    }

    /// @notice test the 'redeemSpecificLP()' function which attempts to redeem the LP tokens corresponding to the passed 'lpRedeemIndex' parameter; if no tokens to be redeemed, deletes the 'liquidityAdds' mapping
    /// @param lpRedeemIndex: index of liquidity in liquidityAdds[] mapping to be redeemed
    function testredeemSpecificLP(uint256 lpRedeemIndex) public {
        (uint256 _withdrawTime, ) = incinerator.liquidityAdds(lpRedeemIndex);

        // 'redeemSpecificLP()' should revert because a year has not yet passed from the time liquidity has been provided
        if (_withdrawTime > block.timestamp) vm.expectRevert();
        incinerator.redeemSpecificLP(lpRedeemIndex);

        // set block.timestamp to a year and a second from now to test redeem
        vm.warp(block.timestamp + YEAR_SECONDS + 1);

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
    }
}
