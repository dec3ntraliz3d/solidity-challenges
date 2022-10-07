// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {IERC20} from "openzeppelin-contracts/interfaces/IERC20.sol";

/**
 * @title VestingVault with a Cliff
 * @dev This contract handles the vesting of Eth and ERC20 tokens for a given beneficiary.
 * Only owner of the contract can fund the contract with ERC20 and ETH. Funding is a one time function.
 * Once the cliff is reached token/eth with be distributed linearly over the vesting duration.
 */

contract VestingVault is Ownable {
    address public immutable beneficiary;
    mapping(address => uint256) public tokenReleased;
    mapping(address => uint64) public tokenUnlockTimestamp;
    mapping(address => uint64) public tokenVaultStartTime;
    mapping(address => uint64) public tokenVestingDurationSeconds;
    mapping(address => bool) public tokenFunded;
    uint256 public ethReleased;
    uint64 public ethUnlockTimestamp;
    uint64 public ethVestingStartTime;
    uint64 public ethVestingDurationSeconds;
    bool public ethFunded;

    error AlreadyFunded();
    error NotBenificiary();
    error NotVested();
    error ETHTransferFailed();
    error AmountGreaterThanAvailable();
    error DurationCantBeZero();

    constructor(address _beneficiary) {
        beneficiary = _beneficiary;
    }

    function fundToken(
        address _token,
        uint256 _amount,
        uint64 _unlockTimestamp,
        uint64 _durationSeconds
    ) public onlyOwner {
        // Funding is an one time action.
        if (tokenFunded[_token]) revert AlreadyFunded();
        tokenFunded[_token] = true;
        if (_durationSeconds == 0) revert DurationCantBeZero();
        tokenVestingDurationSeconds[_token] = _durationSeconds;
        tokenUnlockTimestamp[_token] = _unlockTimestamp;
        tokenVaultStartTime[_token] = uint64(block.timestamp);
        IERC20(_token).transferFrom(msg.sender, address(this), _amount);
    }

    function fundETH(uint64 _unlockTimestamp, uint64 _durationSeconds)
        public
        payable
        onlyOwner
    {
        // Funding is an one time action.
        if (ethFunded) revert AlreadyFunded();
        ethFunded = true;
        if (_durationSeconds == 0) revert DurationCantBeZero();
        ethVestingDurationSeconds = _durationSeconds;
        ethUnlockTimestamp = _unlockTimestamp;
        ethVestingStartTime = uint64(block.timestamp);
    }

    function withdrawToken(address _token, uint256 _amount) external {
        if (block.timestamp < tokenUnlockTimestamp[_token]) revert NotVested();
        if (msg.sender != beneficiary) revert NotBenificiary();
        if (_amount > tokenAvailableToWithdraw(_token))
            revert AmountGreaterThanAvailable();
        tokenReleased[_token] += _amount;
        IERC20(_token).transfer(msg.sender, _amount);
    }

    function withdrawETH(uint256 _amount) public {
        if (block.timestamp < ethUnlockTimestamp) revert NotVested();
        if (msg.sender != beneficiary) revert NotBenificiary();
        if (_amount > ethAvailableToWithdraw())
            revert AmountGreaterThanAvailable();
        ethReleased += _amount;
        (bool sent, ) = payable(msg.sender).call{value: _amount}("");
        if (!sent) revert ETHTransferFailed();
    }

    function tokenAvailableToWithdraw(address _token)
        public
        view
        returns (uint256)
    {
        if (!tokenFunded[_token]) return 0;
        uint256 totalToken = IERC20(_token).balanceOf(address(this)) +
            tokenReleased[_token];
        return
            ((totalToken * (block.timestamp - tokenVaultStartTime[_token])) /
                tokenVestingDurationSeconds[_token]) - tokenReleased[_token];
    }

    function ethAvailableToWithdraw() public view returns (uint256) {
        if (!ethFunded) return 0;
        uint256 totalEth = address(this).balance + ethReleased;
        return
            ((totalEth * (block.timestamp - ethVestingStartTime)) /
                ethVestingDurationSeconds) - ethReleased;
    }
}
