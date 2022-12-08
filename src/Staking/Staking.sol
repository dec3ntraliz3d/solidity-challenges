// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.13;

import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {IERC20} from "openzeppelin-contracts/interfaces/IERC20.sol";
import {Pausable} from "openzeppelin-contracts/security/Pausable.sol";
import {ISignatureTransfer} from "permit2/interfaces/ISignatureTransfer.sol";

interface IPermit2 {
    function permitTransferFrom(
        ISignatureTransfer.PermitTransferFrom memory permit,
        ISignatureTransfer.SignatureTransferDetails calldata transferDetails,
        address owner,
        bytes calldata signature
    ) external;
}

contract Staking is Ownable, Pausable {
    IERC20 public immutable stakingToken;
    IERC20 public immutable rewardToken;
    uint256 public rewardsPerToken;
    uint256 public totalSupply;
    uint256 public rewardRate;
    uint256 public duration;
    uint256 public finishAt;
    uint256 public lastUpdatedAt;
    bool isRewardRateSet;
    IPermit2 permit2;
    mapping(address => uint256) public balanceOf;
    mapping(address => uint256) rewardsEarned;
    mapping(address => uint256) rewardsPerTokenPaid;

    event Stake(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event Claim(address indexed user, uint256 amount);

    error AmountGreaterThanAvailable();
    error AmountCantBeZero();
    error RewardRateAlreadySet();
    error IncorrectTransferToAddress();

    modifier updateRewards(address _account) {
        // Calculate reward per token based on Reward rate and staked amount.
        rewardsPerToken = _calculateRewardsPerToken();
        lastUpdatedAt = min(block.timestamp, finishAt);
        rewardsEarned[msg.sender] = earned(_account);
        rewardsPerTokenPaid[msg.sender] = rewardsPerToken;
        _;
    }

    constructor(
        address _stakingToken,
        address _rewardToken,
        address _permit2
    ) {
        stakingToken = IERC20(_stakingToken);
        rewardToken = IERC20(_rewardToken);
        permit2 = IPermit2(_permit2);
        _pause();
    }

    function pause() public whenNotPaused onlyOwner {
        _pause();
    }

    function unPause() public whenPaused onlyOwner {
        _unpause();
    }

    // Can only be called once by owner.
    function setRewardRate(uint256 _amount, uint256 _duration)
        external
        onlyOwner
    {
        if (isRewardRateSet) revert RewardRateAlreadySet();
        isRewardRateSet = true;
        rewardToken.transferFrom(msg.sender, address(this), _amount);
        duration = _duration;
        rewardRate = _amount / _duration;
        finishAt = block.timestamp + _duration;
        lastUpdatedAt = block.timestamp;
    }

    /*
     * Everytime user stakes, unstakes we need below.
     * Calculate new reward per token -
     * current_reward_per_token += reward_rate/total_staked * (current_time - last_update_time)
     * Update rewards earned by user -
     * rewards[user] += user_staked_amount * (reward_per_token - reward_per_token_paid[user])
     * Update users reward per token paid
     * rewards_per_token_paid[user] = reward_per_token
     * Update last_update_time
     * Update user_balance
     * Update total_supply
     */

    function stakeWithPermit2(
        ISignatureTransfer.PermitTransferFrom calldata permit,
        ISignatureTransfer.SignatureTransferDetails calldata transferDetails,
        bytes calldata signature
    ) external whenNotPaused updateRewards(msg.sender) {
        if (transferDetails.to != address(this))
            revert IncorrectTransferToAddress();
        uint256 _amount = transferDetails.requestedAmount;
        if (_amount == 0) revert AmountCantBeZero();
        permit2.permitTransferFrom(
            permit,
            transferDetails,
            msg.sender,
            signature
        );
        balanceOf[msg.sender] += _amount;
        totalSupply += _amount;
        emit Stake(msg.sender, _amount);
    }

    function stake(uint256 _amount)
        external
        whenNotPaused
        updateRewards(msg.sender)
    {
        if (_amount == 0) revert AmountCantBeZero();
        stakingToken.transferFrom(msg.sender, address(this), _amount);
        balanceOf[msg.sender] += _amount;
        totalSupply += _amount;
        emit Stake(msg.sender, _amount);
    }

    function withdraw(uint256 _amount)
        external
        whenNotPaused
        updateRewards(msg.sender)
    {
        if (_amount > balanceOf[msg.sender])
            revert AmountGreaterThanAvailable();
        balanceOf[msg.sender] -= _amount;
        totalSupply -= _amount;
        stakingToken.transfer(msg.sender, _amount);
        emit Withdraw(msg.sender, _amount);
    }

    function claim() external whenNotPaused updateRewards(msg.sender) {
        // calculate rewards and transfer reward to user
        uint256 rewards = rewardsEarned[msg.sender];
        if (rewards > 0) {
            rewardsEarned[msg.sender] = 0;
            rewardToken.transfer(msg.sender, rewards);
            emit Claim(msg.sender, rewards);
        }
    }

    function earned(address _account) public view returns (uint256) {
        // Returns total rewards earned by _user address
        return
            rewardsEarned[_account] +
            (balanceOf[_account] *
                (_calculateRewardsPerToken() - rewardsPerTokenPaid[_account])) /
            1e18;
    }

    function _calculateRewardsPerToken() private view returns (uint256) {
        if (totalSupply == 0) {
            return rewardsPerToken;
        }

        return
            rewardsPerToken +
            ((rewardRate * (min(block.timestamp, finishAt) - lastUpdatedAt)) *
                1e18) /
            totalSupply;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
