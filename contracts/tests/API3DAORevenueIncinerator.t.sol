// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.12;

import "forge-std/Test.sol";
import "src/API3DAORevenueIncinerator.sol";

// Mainnet fork (MAINNET RPC URL): https://eth.llamarpc.com; see https://ethereumnodes.com/ for alternatives
// forge test --fork-url https://eth.llamarpc.com

/// @notice test contract for API3DAORevenueIncinerator using Foundry
contract API3DAORevenueIncineratorTest is Test {
    API3DAORevenueIncinerator public incinerator;

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

    /** function testSwapUSDCtoAPI3AndLP() public {
        // approve USDC allowance for incinerator
        IERC20 usdc = IERC20(USDC_TOKEN_ADDR);
        require(
            usdc.approve(address(incinerator), 1000),
            "approve USDC failed"
        );

        uint256 _index = incinerator.lpAddIndex();

        (uint256 _withdrawTime, uint256 _amount) = incinerator.liquidityAdds(
            _index
        );
        assertGt(_amount, 0, "add liquidity amount should not be zero");
        assertGt(
            _withdrawTime,
            0,
            "liquidity withdraw time should not be zero"
        );
        assertGt(
            _index,
            incinerator.lpAddIndex(),
            "lpAddIndex did not increment"
        );
        uint256 deadline = block.timestamp + 1 hours;
        incinerator.addLiquidity(usdc, 500, 0, 0, deadline);

        // swap USDC to API3 and LP
        uint256 api3Amount = incinerator.swapUSDCtoAPI3AndLP(100, deadline);
        assertGt(api3Amount, 0, "API3 amount should not be zero");
    }

    function testSwapEthToAPI3() public payable {
        // swap ETH to API3
        uint256 api3Amount = incinerator.swapEthToAPI3{value: 1 ether}(100);
        assertGt(api3Amount, 0, "API3 amount should not be zero");
    }

    function testRedeemLiquidity() public {
        // approve USDC allowance for incinerator
        IERC20 usdc = IERC20(USDC_TOKEN_ADDR);
        require(
            usdc.approve(address(incinerator), 1000),
            "approve USDC failed"
        );

        // add liquidity to incinerator
        uint256 deadline = block.timestamp + 1 hours;
        incinerator.addLiquidity(usdc, 500, 0, 0, deadline);

        // redeem LP tokens from incinerator
        uint256 lpAmount = 1;
        uint256 api3Amount = incinerator.redeemLiquidity(lpAmount, deadline);
        assertGt(api3Amount, 0, "API3 amount should not be zero");
    }*/
}
