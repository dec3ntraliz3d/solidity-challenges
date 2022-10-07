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
    uint256 public tokenReleased;
    uint256 public ethReleased;
    uint64 public tokenUnlockTimestamp;
    uint64 public ethUnlockTimestamp;
    uint64 public tokenVestingStartTime;
    uint64 public ethVestingStartTime;
    uint64 public tokenVestingDurationSeconds;
    uint64 public ethVestingDurationSeconds;
    bool public tokenFunded;
    bool public ethFunded;

    error AlreadyFunded();
    error NotBenificiary();
    error NotVested();
    error ETHTransferFailed();
    error AmountGreaterThanAvailable();

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
        if (tokenFunded) revert AlreadyFunded();
        tokenFunded = true;
        IERC20(_token).transferFrom(msg.sender, address(this), _amount);
        tokenUnlockTimestamp = _unlockTimestamp;
        tokenVestingDurationSeconds = _durationSeconds;
        tokenVestingStartTime = uint64(block.timestamp);
    }

    function fundETH(uint64 _unlockTimestamp, uint64 _durationSeconds)
        public
        payable
        onlyOwner
    {
        // Funding is an one time action.
        if (ethFunded) revert AlreadyFunded();
        ethFunded = true;
        ethUnlockTimestamp = _unlockTimestamp;
        ethVestingDurationSeconds = _durationSeconds;
        ethVestingStartTime = uint64(block.timestamp);
    }

    function withdrawToken(address _token, uint256 _amount) external {
        if (block.timestamp < tokenUnlockTimestamp) revert NotVested();
        if (msg.sender != beneficiary) revert NotBenificiary();
        if (_amount > tokenAvailableToWithdraw(_token))
            revert AmountGreaterThanAvailable();
        tokenReleased += _amount;
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
        uint256 totalToken = IERC20(_token).balanceOf(address(this)) +
            tokenReleased;
        return
            ((totalToken * (block.timestamp - tokenVestingStartTime)) /
                tokenVestingDurationSeconds) - tokenReleased;
    }

    function ethAvailableToWithdraw() public view returns (uint256) {
        uint256 totalEth = address(this).balance + ethReleased;
        return
            ((totalEth * (block.timestamp - ethVestingStartTime)) /
                ethVestingDurationSeconds) - ethReleased;
    }
}
