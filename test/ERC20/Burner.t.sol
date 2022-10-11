// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {Burner} from "../../src/ERC20/Burner.sol";

contract BurnerTest is Test {
    Burner token;
    address treasury;
    address alice;

    function setUp() public {
        token = new Burner("Burner", "BURN", 18);
        treasury = address(
            uint160(uint256(keccak256(abi.encodePacked("treasury"))))
        );
        vm.label(treasury, "Treasury");
        alice = address(uint160(uint256(keccak256(abi.encodePacked("alice")))));
        vm.label(alice, "Alice");
        token.updateTreasuryAddr(treasury);
    }

    function testTransferWithTax(uint256 amount) public {
        vm.assume(amount <= 21_000_000e18); // Limiting fuzzing to maximum 21_000_000e18 ether which is the total supply of token.
        token.transfer(alice, amount);
        assertEq(token.balanceOf(alice) + token.balanceOf(treasury), amount);
    }

    function testTransferFromWithTax(uint256 amount) public {
        token.approve(alice, type(uint256).max);
        vm.assume(amount <= 21_000_000e18); // Limiting fuzzing to maximum 21_000_000e18 which is the total supply of token.
        vm.prank((alice));
        token.transferFrom(address(this), alice, amount);
        assertEq(token.balanceOf(alice) + token.balanceOf(treasury), amount);
    }

    function testTransferFailsWhenPaused(uint256 amount) public {
        token.pause();
        vm.assume(amount <= 21_000_000e18); // Limiting fuzzing to maximum 21_000_000e18 ether which is the total supply of token.
        vm.expectRevert("Pausable: paused");
        token.transfer(alice, amount);
    }

    function testPauseUnpauseOnlyOwner() public {
        token.pause();
        assert(token.paused());
        token.unpause();
        assertFalse(token.paused());
    }

    function testPausUnpauseFailByOtherUser() public {
        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        token.pause();
    }

    function testBurn() public {
        token.burn(1 ether);
        assertEq(token.totalSupply(), token.MAX_SUPPLY() - 1 ether);
        vm.prank(alice);
        vm.expectRevert(Burner.CantBurnMoreThanAvailable.selector);
        token.burn(1 ether);
    }
}
