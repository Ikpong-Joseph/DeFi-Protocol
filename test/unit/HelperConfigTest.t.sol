// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {HelperConfig } from "script/HelperConfig.s.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {ERC20Mock} from"@openzeppelin/contracts/mocks/ERC20Mock.sol";
import { StdCheats } from "forge-std/StdCheats.sol";


contract TestHelperConfig is Test {
    HelperConfig helperConfig;
    string sepolia = vm.envString("sepolia");

    function setUp() public {
        // Default to a hypothetical Anvil chain ID for tests
        // vm.createSelectFork("anvil", 1); // Forcing the chain ID to Anvil
        uint sepolia = vm.createFork(sepolia);
        helperConfig = new HelperConfig();
    }

    function testActiveNetworkConfig() public {
        // Check which configuration is active
        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, )  = helperConfig.activeNetworkConfig();

        // Ensure the default Anvil configuration is active
        assertEq(wethUsdPriceFeed != address(0), true, "ETH/USD price feed should be set");
        assertEq(wbtcUsdPriceFeed != address(0), true, "BTC/USD price feed should be set");
        assertEq(weth != address(0), true, "WETH mock should be set");
        assertEq(wbtc != address(0), true, "WBTC mock should be set");
    }

    function testAnvilEthConfig() public {
        HelperConfig.NetworkConfig memory config = helperConfig.getOrCreateAnvilEthConfig();

        // Validate the mock price feeds and ERC20Mock contracts created
        MockV3Aggregator ethUsdAggregator = MockV3Aggregator(config.wethUsdPriceFeed);
        assertEq(ethUsdAggregator.decimals(), 8, "Decimals should be 8 for ETH/USD");
        assertEq(ethUsdAggregator.latestAnswer(), 2000e8, "ETH/USD price should be 2000e8");

        MockV3Aggregator btcUsdAggregator = MockV3Aggregator(config.wbtcUsdPriceFeed);
        assertEq(btcUsdAggregator.decimals(), 8, "Decimals should be 8 for BTC/USD");
        assertEq(btcUsdAggregator.latestAnswer(), 1000e8, "BTC/USD price should be 1000e8");

        ERC20Mock wethMock = ERC20Mock(config.weth);
        assertEq(wethMock.name(), "WETH", "WETH mock should be named WETH");
        assertEq(wethMock.symbol(), "WETH", "WETH mock symbol should be WETH");
        assertEq(wethMock.balanceOf(address(this)), 1000e8, "Initial balance should be 1000e8");

        ERC20Mock wbtcMock = ERC20Mock(config.wbtc);
        assertEq(wbtcMock.name(), "WBTC", "WBTC mock should be named WBTC");
        assertEq(wbtcMock.symbol(), "WBTC", "WBTC mock symbol should be WBTC");
        assertEq(wbtcMock.balanceOf(address(this)), 1000e8, "Initial balance should be 1000e8");
    }

    function testSepoliaEthConfig() public {
        // Change the chain ID to Sepolia and reinitialize the HelperConfig
        
        vm.createSelectFork("sepolia"); // Forcing the chain ID to Sepolia
        helperConfig = new HelperConfig();
        

       (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, )  = helperConfig.activeNetworkConfig();

    //    assertEq(vm.activeFork(), sepolia);

        // Validate the fixed addresses in the Sepolia config
        assertEq(wethUsdPriceFeed, 0x694AA1769357215DE4FAC081bf1f309aDC325306, "ETH/USD price feed should match expected");
        assertEq(wbtcUsdPriceFeed, 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43, "BTC/USD price feed should match expected");
        assertEq(weth, 0xdd13E55209Fd76AfE204dBda4007C227904f0a81, "WETH address should match expected");
        assertEq(wbtc, 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063, "WBTC address should match expected");
    }
}
