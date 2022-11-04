// SPX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../../src/Flashloan/FlashloanReceiverAave.sol";
import "../../src/Flashloan/Interfaces.sol";

interface IWETH9 is IERC20 {
    function deposit() external payable;

    function withdraw(uint256) external;
}

contract FlashloanReceiverAaveTest is Test {
    FlashloanReceiverAave flashloanReceiver;
    IWETH9 weth = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address public constant USDC_WHALE =
        0xb4df85cC20B5604496bE657b27194926BD878cee;

    function setUp() public {
        // fork mainnet
        vm.createSelectFork(
            "https://eth-mainnet.g.alchemy.com/v2/<Your_Alchemy_API_Key>"
        );
        flashloanReceiver = new FlashloanReceiverAave();
        vm.prank(USDC_WHALE);
        usdc.transfer(address(this), 1000000e6);
        weth.deposit{value: 1000 ether}();
        assertEq(weth.balanceOf(address(this)), 1000 ether);
        weth.approve(address(flashloanReceiver), type(uint256).max);

        assertEq(usdc.balanceOf(address(this)), 1000000e6);
        usdc.approve(address(flashloanReceiver), type(uint256).max);
    }

    function testFlashloan() public {
        address[] memory assets = new address[](2);
        assets[0] = address(weth);
        assets[1] = address(usdc);

        uint256[] memory modes = new uint256[](2);
        modes[0] = 0;
        modes[1] = 0;

        flashloanReceiver.getFlashloan(assets, modes);
    }
}
