// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./Interfaces.sol";
import "forge-std/console.sol";

contract FlashloanReceiverAave {
    ILendingPoolAddressesProvider public constant lendingPoolAddressProvider =
        ILendingPoolAddressesProvider(
            0xB53C1a33016B2DC2fF3653530bfF1848a515c8c5
        );
    IAaveProtocolDataProvider dataProvider =
        IAaveProtocolDataProvider(0x057835Ad21a177dbdd3090bB1CAE03EaCF78Fc6d);

    function getFlashloan(address[] calldata _assets, uint256[] calldata _modes)
        external
    {
        address lendingPoolAddress = lendingPoolAddressProvider
            .getLendingPool();
        bytes memory params = abi.encode(msg.sender);
        uint256[] memory _amounts = new uint256[](_assets.length);

        for (uint8 i = 0; i < _assets.length; i++) {
            (_amounts[i], , , , , , , , , ) = dataProvider.getReserveData(
                _assets[i]
            ); // borrow all available liquidity from aave pool.
        }

        ILendingPool(lendingPoolAddress).flashLoan(
            address(this),
            _assets,
            _amounts,
            _modes,
            address(this),
            params,
            0
        );
    }

    // Flashloan callback function

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external returns (bool) {
        // Verify the caller is Aave lending pool
        require(
            msg.sender == lendingPoolAddressProvider.getLendingPool(),
            "Unauthorized"
        );
        require(initiator == address(this), "Unauthorized");
        address caller = abi.decode(params, (address));

        // Do something with the flashloan

        // Repay flashloan
        for (uint8 i = 0; i < assets.length; i++) {
            IERC20(assets[i]).transferFrom(caller, address(this), premiums[i]);
            IERC20(assets[i]).approve(msg.sender, amounts[i] + premiums[i]);
        }

        return true;
    }
}
