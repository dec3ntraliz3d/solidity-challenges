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
    mapping(address => VestingDetails) public tokenVaults;
    VestingDetails public ethVault;

    struct VestingDetails {
        uint256 amountReleased;
        uint64 unlockTime;
        uint64 startTime;
        uint64 duration;
        bool funded;
    }

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
        if (tokenVaults[_token].funded) revert AlreadyFunded();
        tokenVaults[_token].funded = true;
        if (_durationSeconds == 0) revert DurationCantBeZero();
        tokenVaults[_token].duration = _durationSeconds;
        tokenVaults[_token].unlockTime = _unlockTimestamp;
        tokenVaults[_token].startTime = uint64(block.timestamp);
        IERC20(_token).transferFrom(msg.sender, address(this), _amount);
    }

    function fundETH(uint64 _unlockTimestamp, uint64 _durationSeconds)
        public
        payable
        onlyOwner
    {
        // Funding is an one time action.
        if (ethVault.funded) revert AlreadyFunded();
        ethVault.funded = true;
        if (_durationSeconds == 0) revert DurationCantBeZero();
        ethVault.duration = _durationSeconds;
        ethVault.unlockTime = _unlockTimestamp;
        ethVault.startTime = uint64(block.timestamp);
    }

    function withdrawToken(address _token, uint256 _amount) external {
        if (block.timestamp < tokenVaults[_token].unlockTime)
            revert NotVested();
        if (msg.sender != beneficiary) revert NotBenificiary();
        if (_amount > tokenAvailableToWithdraw(_token))
            revert AmountGreaterThanAvailable();
        tokenVaults[_token].amountReleased += _amount;
        IERC20(_token).transfer(msg.sender, _amount);
    }

    function withdrawETH(uint256 _amount) public {
        if (block.timestamp < ethVault.unlockTime) revert NotVested();
        if (msg.sender != beneficiary) revert NotBenificiary();
        if (_amount > ethAvailableToWithdraw())
            revert AmountGreaterThanAvailable();
        ethVault.amountReleased += _amount;
        (bool sent, ) = payable(msg.sender).call{value: _amount}("");
        if (!sent) revert ETHTransferFailed();
    }

    function tokenAvailableToWithdraw(address _token)
        public
        view
        returns (uint256)
    {
        if (!tokenVaults[_token].funded) return 0;

        uint256 totalToken = IERC20(_token).balanceOf(address(this)) +
            tokenVaults[_token].amountReleased;

        // If Vesting duration is complete. All token available for withdraw.
        if (
            block.timestamp - tokenVaults[_token].startTime >=
            tokenVaults[_token].duration
        ) return (totalToken - tokenVaults[_token].amountReleased);

        return
            ((totalToken * (block.timestamp - tokenVaults[_token].startTime)) /
                tokenVaults[_token].duration) -
            tokenVaults[_token].amountReleased;
    }

    function ethAvailableToWithdraw() public view returns (uint256) {
        if (!ethVault.funded) return 0;
        uint256 totalEth = address(this).balance + ethVault.amountReleased;

        // Vesting duration is complete. All eth available for withdraw.
        if (block.timestamp - ethVault.startTime >= ethVault.duration)
            return (totalEth - ethVault.amountReleased);

        return
            ((totalEth * (block.timestamp - ethVault.startTime)) /
                ethVault.duration) - ethVault.amountReleased;
    }
}
