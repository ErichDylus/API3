// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.12;

import "ds-test/test.sol";
import "src/API3DAORevenueIncinerator.sol";
import "src/UniswapV2Router02.sol";
import "src/UniswapV2Factory.sol";
import "src/ERC20.sol";

/// INCOMPLETE, IN PROCESS

/// @notice test contract for API3DAORevenueIncinerator using Foundry
contract API3DAORevenueIncineratorTest is DSTest {
    API3DAORevenueIncinerator public incinerator;
    ERC20 public mockAPI3Token;
    ERC20 public mockUSDCToken;
    UniswapV2Factory public mockFactory;
    UniswapV2Router02 public mockRouter;

    function setUp() public {
        incinerator = new API3DAORevenueIncinerator();
        mockAPI3Token = new ERC20(address(this), address(incinerator));
        mockUSDCToken = new ERC20(address(this), address(incinerator));
        mockWETHToken = new ERC20(address(this), address(incinerator));
        mockFactory = new UniswapV2Factory();
        mockRouter = new UniswapV2Router02(
            address(mockFactory),
            address(mockWETHToken)
        );
        mockFactory.initialize(address(mockWETHToken), address(mockAPI3Token));
        mockFactory.initialize(address(mockUSDCToken), address(mockWETHToken));
    }

    function testAddETHLiquidity() public payable {
        uint256 _index = incinerator.lpAddIndex();

        // add liquidity to incinerator
        (bool sent, ) = address(incinerator).call{value: 1 ether}("");
        require(sent, "Failed to send Ether");

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
    }
}
