// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { Script } from "forge-std/Script.sol";
import { HelperConfig } from "script/HelperConfig.s.sol";
import { DecentralisedStableCoin } from "../src/DecentralisedStableCoin.sol";
import { DSCEngine } from "../src/DSCEngine.sol";

contract DeployDSC is Script {
    address[] public tokenAddresses; 
    address[] public priceFeedAddresses;

    // Run this script to power whole protocol

    function run() external returns (DecentralisedStableCoin, DSCEngine, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig(); // This comes with our mocks!

        (address wethUsdPriceFeedSepolia, address wbtcUsdPriceFeedSepolia, address wethSepolia, address wbtcSepolia, /*uint256*/string memory deployerKeySepolia) =
            helperConfig.activeNetworkConfigSepolia(); // Setting the Helperconfig's activeNetworkConfig struct depending on detected chainId during deployment
        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, uint256 deployerKey) =
            helperConfig.activeNetworkConfig();
        tokenAddresses = [weth, wbtc]; //setting token[] for dscEngine constructor
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed]; //setting priceFeedAddress[] for dscEngine constructor sequentially for each corresponding token in tokenAddresses[]

        vm.startBroadcast();
        // Powering up each of the contracts
        DecentralisedStableCoin dsc = new DecentralisedStableCoin();
        DSCEngine dscEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
        dsc.transferOwnership(address(dscEngine));
        vm.stopBroadcast();
        return (dsc, dscEngine, helperConfig);
    }
}