//SPDX-License-Identifier: MIT
/*****
 ***** this code and any deployments of this code are strictly provided as-is;
 ***** no guarantee, representation or warranty is being made, express or implied, as to the safety or correctness of the code
 ***** or any smart contracts or other software deployed from these files,
 ***** in accordance with the disclosures and licenses found here: https://github.com/ErichDylus/API3/blob/main/contracts/README.md
 ***** this code is not audited, and users, developers, or adapters of these files should proceed with caution and use at their own risk.
 ****/

pragma solidity >=0.8.16;

import "https://github.com/ErichDylus/API3/blob/main/contracts/SwapUSDCAndBurnAPI3.sol";
import "https://github.com/paulrberg/prb-test/blob/main/src/PRBTest.sol";

/// @title Swap USDC and Burn API3 Test

contract SwapUSDCAndBurnAPI3Test is SwapUSDCAndBurnAPI3, PRBTest {
    address public tester;
    SwapUSDCAndBurnAPI3 public contracttest;

    function beforeEach() public {
        contracttest = new SwapUSDCAndBurnAPI3();
        tester = msg.sender;
    }

    function checkSwapAndBurn() public {
        (bool success, ) = address(contracttest).delegatecall(
            abi.encodeWithSignature("swapUSDCToAPI3AndBurn()")
        );
        require(success, "call failed");
    }

    function checkSwapAndLpAndBurn() public {
        (bool success, ) = address(contracttest).delegatecall(
            abi.encodeWithSignature("swapUSDCToAPI3AndLpAndBurn()")
        );
        require(success, "call failed");
    }

    function checkRedeemLp() public {
        uint256 _redeemIndex = contracttest.lpRedeemIndex();
        (bool success, ) = address(contracttest).delegatecall(
            abi.encodeWithSignature("redeemLP()")
        );
        require(success, "call failed");
        return
            assertEq(
                contracttest.lpRedeemIndex(),
                _redeemIndex + 1,
                "redeemIndex did not increment"
            );
    }

    function checkRedeemSpecificLp() public {
        uint256 _redeemIndex = contracttest.lpRedeemIndex();
        (bool success, ) = address(contracttest).delegatecall(
            abi.encodeWithSignature("redeemSpecificLP(uint256)", _lpRedeemIndex)
        );
        require(success, "call failed");
        return
            assertEq(
                contracttest.lpRedeemIndex(),
                _redeemIndex + 1,
                "redeemIndex did not increment"
            );
    }

    function checkETHpath() public {
        address[] memory testpath = new address[](2);
        testpath = _getPathForUSDCtoETH();
        assertEq(
            testpath[0],
            0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
            "path incorrect"
        );
        assertEq(
            testpath[1],
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            "path incorrect"
        );
    }

    function checkAPI3path() public {
        address[] memory testpath = new address[](2);
        testpath = _getPathForETHtoAPI3();
        assertEq(
            testpath[0],
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            "path incorrect"
        );
        assertEq(
            testpath[1],
            0x0b38210ea11411557c13457D4dA7dC6ea731B88a,
            "path incorrect"
        );
    }
}
