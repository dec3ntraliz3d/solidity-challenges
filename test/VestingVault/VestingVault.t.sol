// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../../src/VestingVault/VestingVault.sol";
import {VestingToken} from "../../src/VestingVault/VestingToken.sol";

contract VestingVaultTest is Test {
    VestingVault vault;
    VestingToken token;
    address beneficiary;

    function setUp() public {
        beneficiary = address(
            uint160(uint256(keccak256(abi.encodePacked("beneficiary"))))
        );
        vault = new VestingVault(address(beneficiary));
        token = new VestingToken("Vesting Token", "VEST");
    }

    function testOwnerCanFundToken() public {
        token.approve(address(vault), type(uint256).max);

        vault.fundToken(
            address(token),
            100 ether,
            uint64(block.timestamp) + 2 days,
            5 days
        );

        assertEq(token.balanceOf(address(vault)), 100 ether);
        assert(vault.tokenFunded(address(token)));
    }

    function testOwnerCanFundEth() public {
        vault.fundETH{value: 10 ether}(
            uint64(block.timestamp) + 2 days,
            5 days
        );
        assertEq(address(vault).balance, 10 ether);
        assert(vault.ethFunded());
    }

    function testOneTimeTokenFunding() public {
        token.approve(address(vault), type(uint256).max);

        vault.fundToken(
            address(token),
            100 ether,
            uint64(block.timestamp) + 2 days,
            5 days
        );

        vm.expectRevert(VestingVault.AlreadyFunded.selector);
        vault.fundToken(
            address(token),
            5 ether,
            uint64(block.timestamp) + 2 days,
            5 days
        );
    }

    function testOneTimeETHFunding() public {
        vault.fundETH{value: 10 ether}(
            uint64(block.timestamp) + 2 days,
            5 days
        );
        vm.expectRevert(VestingVault.AlreadyFunded.selector);

        vault.fundETH{value: 1 ether}(uint64(block.timestamp) + 2 days, 5 days);
    }

    function testCannotWithdrawTokenBeforeVesting() public {
        // Fund token
        token.approve(address(vault), type(uint256).max);
        vault.fundToken(
            address(token),
            100 ether,
            uint64(block.timestamp) + 2 days,
            5 days
        );

        // Forward EVM by one day
        vm.warp(block.timestamp + 1 days);
        vm.prank(beneficiary);
        vm.expectRevert(VestingVault.NotVested.selector);
        vault.withdrawToken(address(token), 10);
    }

    function testWithdrawETHBeforeVesting() public {
        // Fund ETH
        vault.fundETH{value: 10 ether}(
            uint64(block.timestamp) + 2 days,
            5 days
        );
        // Forward EVM by one day
        vm.warp(block.timestamp + 1 days);
        vm.prank(beneficiary);
        vm.expectRevert(VestingVault.NotVested.selector);
        vault.withdrawETH(1 ether);
    }

    function testWithdrawTokenAfterVestingCliff() public {
        // Fund token
        token.approve(address(vault), type(uint256).max);
        vault.fundToken(
            address(token),
            100 ether,
            uint64(block.timestamp) + 2 days,
            5 days
        );

        // Forward EVM by 50 hours
        vm.warp(block.timestamp + 50 hours);
        vm.prank(beneficiary);
        // After 50 hours beneficiary should be able to withdraw 41.66 token
        vault.withdrawToken(address(token), 41.66 ether);
        assertEq(token.balanceOf(beneficiary), 41.66 ether);
    }

    function testWithdrawAllTokenAfterVestingCompletion() public {
        // Fund token
        token.approve(address(vault), type(uint256).max);
        vault.fundToken(
            address(token),
            100 ether,
            uint64(block.timestamp) + 2 days, //Cliff
            5 days //Total duration
        );
        vm.warp(block.timestamp + 7 days);
        vm.startPrank(beneficiary);
        // Should be able to withdraw all token after vesting period has completed.
        uint256 tokenAvailable = vault.tokenAvailableToWithdraw(address(token));
        vault.withdrawToken(address(token), tokenAvailable);
        assertEq(token.balanceOf(beneficiary), tokenAvailable);
        vm.stopPrank();
    }

    function testWithdrawETHAfterVestingCliff() public {
        // Fund ETH
        vault.fundETH{value: 10 ether}(
            uint64(block.timestamp) + 2 days,
            5 days
        );

        // Forward EVM by 50 hours . Cliff is after 48 hours
        vm.warp(block.timestamp + 50 hours);
        vm.prank(beneficiary);
        // After 50 hours beneficiary should be able to withdraw 4.16 eth
        vault.withdrawETH(4.16 ether);
        assertEq(beneficiary.balance, 4.16 ether);
    }

    function testWithdrawAllETHAfterVestingCompletion() public {
        // Fund ETH
        vault.fundETH{value: 10 ether}(
            uint64(block.timestamp) + 2 days,
            5 days
        );
        vm.warp(block.timestamp + 7 days);
        uint256 ethAvailable = vault.ethAvailableToWithdraw();
        vm.startPrank(beneficiary);
        uint256 currentEthBalance = beneficiary.balance;
        // Should be able to withdraw all ETH after vesting period has completed.
        vault.withdrawETH(ethAvailable);
        vm.stopPrank();
        assertEq(beneficiary.balance, currentEthBalance + ethAvailable);
    }

    function testCannotWithdrawMoreTokenThanVested() public {
        // Fund token
        token.approve(address(vault), type(uint256).max);
        vault.fundToken(
            address(token),
            100 ether,
            uint64(block.timestamp) + 2 days,
            5 days
        );

        vm.warp(block.timestamp + 50 hours);
        vm.startPrank(beneficiary);
        // After 50 hours beneficiary should be able to withdraw 41.66 token
        vault.withdrawToken(address(token), 41.66 ether);
        vm.expectRevert(VestingVault.AmountGreaterThanAvailable.selector);
        // Can't withdraw again until more tokens have been vested.
        vault.withdrawToken(address(token), 1 ether);
    }

    function testCannotWithdrawMoreETHThanVested() public {
        // Fund Eth

        vault.fundETH{value: 10 ether}(
            uint64(block.timestamp) + 2 days,
            5 days
        );
        vm.warp(block.timestamp + 50 hours);
        vm.startPrank(beneficiary);
        // After 50 hours beneficiary should be able to withdraw 4.16 ETH
        vault.withdrawETH(4.16 ether);
        vm.expectRevert(VestingVault.AmountGreaterThanAvailable.selector);
        // Can't withdraw again until more ETH have been vested.
        vault.withdrawETH(1 ether);
    }

    function testTokenAvailableToWithdraw() public {
        assertEq(vault.tokenAvailableToWithdraw(address(token)), 0);
    }

    function testEthAvailableToWithdraw() public {
        assertEq(vault.ethAvailableToWithdraw(), 0);
    }
}
