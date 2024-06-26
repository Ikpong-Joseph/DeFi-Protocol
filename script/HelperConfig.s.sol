// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { MockV3Aggregator } from "../test/mocks/MockV3Aggregator.sol";
import { Script } from "forge-std/Script.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract HelperConfig is Script {
    NetworkConfig public activeNetworkConfig;
    NetworkConfigSepolia public activeNetworkConfigSepolia;

    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 2000e8;
    int256 public constant BTC_USD_PRICE = 1000e8;

    struct NetworkConfig {
        address wethUsdPriceFeed;
        address wbtcUsdPriceFeed;
        address weth;
        address wbtc;
        uint256 deployerKey;
    }

    struct NetworkConfigSepolia {
        address wethUsdPriceFeed;
        address wbtcUsdPriceFeed;
        address weth;
        address wbtc;
        string deployerKey;
    }

    uint256 public DEFAULT_ANVIL_PRIVATE_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80; // Careful Jose!!

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfigSepolia = getSepoliaEthConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getSepoliaEthConfig() public view returns (NetworkConfigSepolia memory sepoliaNetworkConfig) {
        sepoliaNetworkConfig = NetworkConfigSepolia({
            wethUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306, // ETH / USD https://docs.chain.link/data-feeds/price-feeds/addresses?network=ethereum&page=1
            wbtcUsdPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43, // BTC / USD https://docs.chain.link/data-feeds/price-feeds/addresses?network=ethereum&page=1
            weth: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
            wbtc: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063, // Collateral token address gotten from?
            deployerKey: vm.envString("ETH_KEYSTORE_ACCOUNT") // Reads SEPOLIA_PRIVATE_KEY from .env file. **PRIVATE STUFF!**

        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory anvilNetworkConfig) {
        // Check to see if we set an active network config
        if (activeNetworkConfig.wethUsdPriceFeed != address(0)) {
            return activeNetworkConfig;
        }


        // ERC20Mock requires in its constructor(name, symbol, initialAccount, initialBalance) for token mocks
        // MockV3Aggregator requires in its constructor(decimals, initialPrice)
        vm.startBroadcast();
        MockV3Aggregator ethUsdPriceFeed = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE);
        ERC20Mock wethMock = new ERC20Mock("WETH", "WETH", msg.sender, 1000e8); // Creates new instance of the ERC20Mock contract and called wethMock

        MockV3Aggregator btcUsdPriceFeed = new MockV3Aggregator(DECIMALS, BTC_USD_PRICE);
        ERC20Mock wbtcMock = new ERC20Mock("WBTC", "WBTC", msg.sender, 1000e8); // Creates new instance of the ERC20Mock contract and called wbtcMock
        vm.stopBroadcast();

        anvilNetworkConfig = NetworkConfig({
            wethUsdPriceFeed: address(ethUsdPriceFeed), // ETH / USD
            weth: address(wethMock), /**Gotten from line 51 */
            wbtcUsdPriceFeed: address(btcUsdPriceFeed),
            wbtc: address(wbtcMock), /**Gotten from line 54 */
            deployerKey: DEFAULT_ANVIL_PRIVATE_KEY
        });
    }

    /////////////////////////
    // GETTERS
    ////////////

    function getDecimals() external pure returns(uint8) {
        return DECIMALS;
    }

    function getEthInitialPrice() external pure returns(int256) {
        return ETH_USD_PRICE;
    }

    function getBtcInitialPrice() external pure returns(int256) {
        return BTC_USD_PRICE;
    }
}