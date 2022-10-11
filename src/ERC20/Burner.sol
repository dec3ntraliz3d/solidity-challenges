// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {Pausable} from "openzeppelin-contracts/security/Pausable.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";

/**
 * @title ERC20 FixedSupply, Burnable, Pausable, Transfer Tax
 * @dev This is an extension of Solmate ERC20 base contract with additional features -
 * pausable, transfer tax, fixed supply
 */

contract Burner is ERC20, Pausable, Ownable {
    uint256 public constant MAX_SUPPLY = 21_000_000e18;
    address public treasury;

    error CantBurnMoreThanAvailable();

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) ERC20(_name, _symbol, _decimals) {
        _mint(msg.sender, MAX_SUPPLY);
        treasury = msg.sender;
    }

    function burn(uint256 amount) public {
        if (amount > balanceOf[msg.sender]) revert CantBurnMoreThanAvailable();
        _burn(msg.sender, amount);
    }

    function pause() public onlyOwner whenNotPaused {
        _pause();
    }

    function unpause() public onlyOwner whenPaused {
        _unpause();
    }

    function transfer(address to, uint256 amount)
        public
        override
        whenNotPaused
        returns (bool)
    {
        balanceOf[msg.sender] -= amount;
        uint256 tax = _tax(amount);
        unchecked {
            balanceOf[treasury] += tax;
            balanceOf[to] += amount - tax;
        }
        emit Transfer(msg.sender, treasury, tax);
        emit Transfer(msg.sender, to, amount - tax);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override whenNotPaused returns (bool) {
        uint256 allowed = allowance[from][msg.sender]; // Saves gas for limited approvals.

        if (allowed != type(uint256).max)
            allowance[from][msg.sender] = allowed - amount;

        balanceOf[from] -= amount;
        uint256 tax = _tax(amount);
        unchecked {
            balanceOf[treasury] += tax;
            balanceOf[to] += amount - tax;
        }
        emit Transfer(msg.sender, treasury, tax);
        emit Transfer(from, to, amount);
        return true;
    }

    function _tax(uint256 amount) internal pure returns (uint256) {
        return (amount * 3) / 100;
    }

    function updateTreasuryAddr(address _addr) external onlyOwner {
        treasury = _addr;
    }
}
