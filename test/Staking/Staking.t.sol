// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {ERC20Token} from "../../src/Staking/ERC20Token.sol";
import {Staking} from "../../src/Staking/Staking.sol";
import {Permit2} from "permit2/Permit2.sol";
import {ISignatureTransfer} from "permit2/interfaces/ISignatureTransfer.sol";

contract StakingTest is Test {
    uint256 public constant TOTAL_REWARD = 1_000_000 ether;
    uint256 public constant DURATION = 7 days;
    ERC20Token stakingToken;
    ERC20Token rewardToken;
    Staking stakingContract;
    address alice;
    address bob;
    address lizzy;
    uint256 permitSignerPrivateKey = 0x123456;
    address permitSigner = vm.addr(permitSignerPrivateKey);
    Permit2 permit2;

    bytes32 public constant _TOKEN_PERMISSIONS_TYPEHASH =
        keccak256("TokenPermissions(address token,uint256 amount)");

    bytes32 public constant _PERMIT_TRANSFER_FROM_TYPEHASH =
        keccak256(
            "PermitTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline)TokenPermissions(address token,uint256 amount)"
        );

    function setUp() public {
        alice = address(uint160(uint256(keccak256(abi.encodePacked("alice")))));
        vm.label(alice, "Alice");
        bob = address(uint160(uint256(keccak256(abi.encodePacked("bob")))));
        vm.label(bob, "Bob");
        lizzy = address(uint160(uint256(keccak256(abi.encodePacked("lizzy")))));
        vm.label(lizzy, "lizzy");

        stakingToken = new ERC20Token("Staking", "STK", 18);
        stakingToken.transfer(alice, 1000 ether);
        stakingToken.transfer(bob, 2000 ether);
        stakingToken.transfer(lizzy, 2000 ether);
        stakingToken.transfer(permitSigner, 500 ether);
        permit2 = new Permit2();
        rewardToken = new ERC20Token("Reward", "RWD", 18);

        stakingContract = new Staking(
            address(stakingToken),
            address(rewardToken),
            address(permit2)
        );

        // Aprove staking token transfer
        rewardToken.approve(address(stakingContract), type(uint256).max);
        vm.startPrank(alice);
        stakingToken.approve(address(stakingContract), type(uint256).max);
        vm.stopPrank();
        vm.prank(bob);
        stakingToken.approve(address(stakingContract), type(uint256).max);
        vm.prank(lizzy);
        stakingToken.approve(address(stakingContract), type(uint256).max);

        // Fund staking contract with Rewards
        stakingContract.setRewardRate(TOTAL_REWARD, DURATION);
    }

    function testCanStake() public {
        unpause();
        vm.prank(alice);
        stakingContract.stake(100 ether);
        assertEq(stakingContract.balanceOf(alice), 100 ether);
        vm.warp(block.timestamp + 1 days);
        assertGt(stakingContract.earned(alice), 0);
    }

    function testCanStakeWithPermit2() public {
        unpause();
        vm.prank(permitSigner);
        // One time approval of Permit2 address
        stakingToken.approve(address(permit2), type(uint256).max);

        // Create permit details
        ISignatureTransfer.TokenPermissions
            memory permitted = ISignatureTransfer.TokenPermissions({
                token: address(stakingToken),
                amount: 500 ether
            });
        ISignatureTransfer.PermitTransferFrom
            memory _permit = ISignatureTransfer.PermitTransferFrom({
                permitted: permitted,
                nonce: 0,
                deadline: block.timestamp + 1 days
            });

        bytes32 tokenPermissions = keccak256(
            abi.encode(_TOKEN_PERMISSIONS_TYPEHASH, _permit.permitted)
        );
        bytes32 msgHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                permit2.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        _PERMIT_TRANSFER_FROM_TYPEHASH,
                        tokenPermissions,
                        address(stakingContract),
                        _permit.nonce,
                        _permit.deadline
                    )
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            permitSignerPrivateKey,
            msgHash
        );

        bytes memory signature = bytes.concat(r, s, bytes1(v));

        // Create transfer details

        ISignatureTransfer.SignatureTransferDetails
            memory transferDetails = ISignatureTransfer
                .SignatureTransferDetails({
                    to: address(stakingContract),
                    requestedAmount: 100 ether
                });
        vm.prank(permitSigner);
        stakingContract.stakeWithPermit2(_permit, transferDetails, signature);

        assertEq(stakingContract.balanceOf(permitSigner), 100 ether);
    }

    function testMultipleAccountsCanStake() public {
        unpause();
        vm.prank(alice);
        stakingContract.stake(100 ether);
        vm.warp(block.timestamp + 10 hours);
        vm.prank(bob);
        stakingContract.stake(69 ether);
        vm.warp(block.timestamp + 1 days);
        vm.prank(lizzy);
        stakingContract.stake(420 ether);
        vm.warp(block.timestamp + 5 days);
        assertEq(stakingContract.balanceOf(alice), 100 ether);
        assertEq(stakingContract.balanceOf(bob), 69 ether);
        assertEq(stakingContract.balanceOf(lizzy), 420 ether);
    }

    function testCanStakeFuzzy(uint256 _amount) public {
        unpause();
        vm.assume(_amount <= stakingToken.balanceOf(alice));
        vm.prank(alice);
        if (_amount == 0) {
            vm.expectRevert(Staking.AmountCantBeZero.selector);
        }
        stakingContract.stake(_amount);
        assertEq(stakingContract.balanceOf(alice), _amount);
    }

    function testCannotStakeWhenPaused() public {
        vm.prank(alice);
        vm.expectRevert("Pausable: paused");
        stakingContract.stake(100 ether);
    }

    function testCanWithdraw() public {
        unpause();
        vm.startPrank(alice);
        stakingContract.stake(100 ether);
        uint256 walletBalanceAlice = stakingToken.balanceOf(alice);
        uint256 stakedBalanceAlice = stakingContract.balanceOf(alice);
        vm.warp(block.timestamp + 10 hours);
        stakingContract.withdraw(10 ether);
        vm.stopPrank();
        assertEq(stakingToken.balanceOf(alice), walletBalanceAlice + 10 ether);
        assertEq(
            stakingContract.balanceOf(alice),
            stakedBalanceAlice - 10 ether
        );
    }

    function testCanClaimRewards() public {
        unpause();
        vm.prank(alice);
        stakingContract.stake(100 ether);
        vm.warp(block.timestamp + 10 hours);
        vm.prank(bob);
        stakingContract.stake(69 ether);
        vm.warp(block.timestamp + 1 days);
        vm.prank(lizzy);
        stakingContract.stake(420 ether);
        vm.warp(block.timestamp + 4 days);
        vm.prank(alice);
        stakingContract.claim();
        vm.prank(bob);
        stakingContract.claim();
        vm.prank(alice);
        stakingContract.stake(100 ether);

        // Move vm past reward finish date
        vm.warp(block.timestamp + 10 days);
        vm.prank(lizzy);
        stakingContract.claim();
        vm.prank(alice);
        stakingContract.claim();
        assertGt(rewardToken.balanceOf(alice), 0);
        assertGt(rewardToken.balanceOf(bob), 0);
        assertGt(rewardToken.balanceOf(lizzy), 0);
    }

    function unpause() private {
        stakingContract.unPause();
    }

    function testCannotSetRewardOnceSet() public {
        unpause();
        vm.expectRevert(Staking.RewardRateAlreadySet.selector);
        stakingContract.setRewardRate(TOTAL_REWARD, DURATION);
    }

    function testRewardMath() public {
        unpause();
        vm.prank(alice);
        stakingContract.stake(100 ether);
        vm.warp(block.timestamp + 1 days);
        vm.prank(bob);
        stakingContract.stake(69 ether);
        vm.warp(block.timestamp + 8 hours);
        vm.prank(lizzy);
        stakingContract.stake(420 ether);
        vm.warp(block.timestamp + 8 hours);
        vm.prank(alice);
        stakingContract.claim();
        vm.prank(alice);
        stakingContract.withdraw(50 ether);
        // Move vm past reward finish date
        vm.warp(block.timestamp + 9 days);
        vm.prank(bob);
        stakingContract.claim();
        vm.prank(lizzy);
        stakingContract.claim();
        vm.prank(alice);
        stakingContract.claim();

        // At the end of the duration alice rewards + bob's rewards + lizzy's rewards =~ total rewards
        assertApproxEqAbs(
            rewardToken.balanceOf(alice) +
                rewardToken.balanceOf(bob) +
                rewardToken.balanceOf(lizzy),
            TOTAL_REWARD,
            (TOTAL_REWARD * 2) / 1e6
            // 0.0002 % accurate . This is due to division amount/duration and solidity
            // taking the floor of the division.
        );
    }
}
