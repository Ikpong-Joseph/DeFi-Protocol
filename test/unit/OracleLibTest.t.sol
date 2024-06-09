//SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import { MockV3Aggregator } from "../mocks/MockV3Aggregator.sol";
import { OracleLib, AggregatorV3Interface} from "src/libraries/OracleLib.sol";

import {DeployDSC} from "script/DeployDSC.s.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

contract OracleLibTest is Test{
    using OracleLib for AggregatorV3Interface; 

    address wethUsdPriceFeed;
    address wbtcUsdPriceFeed;
    address weth;
    address wbtc;

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

        HelperConfig public helperConfig;


    function setUp() public {
        DeployDSC deployer = new DeployDSC();
        (/* dsc */, /* dscEngine */, helperConfig) = deployer.run();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc, ) = helperConfig
            .activeNetworkConfig();

        MockV3Aggregator wethUsdPriceFeed = new MockV3Aggregator( helperConfig.getDecimals(), helperConfig.getEthInitialPrice());


    }

    function testgetTimeout() external{
        uint256 expectedTimeout = 3 hours;
        uint256 actualTimeout = OracleLib.getTimeout(AggregatorV3Interface(wethUsdPriceFeed));
        assert(actualTimeout == expectedTimeout);
    }

    function testPriceRevertsOnStaleCheck() public {
        // vm.warp Sets block.timestamp.
        // In this case it sets time to: now + 4hrs + 1s
        // This exceeds OraclLib 3hr TIMEOUT by 1hr and 1s.
        vm.warp(block.timestamp + 4 hours + 1 seconds);

        // vm.roll Sets block.number.
        // Simply mines an extra block where this transaction resides
        vm.roll(block.number + 1);

        vm.expectRevert(OracleLib.OracleLib__StalePrice.selector);
        AggregatorV3Interface(wethUsdPriceFeed).staleCheckLatestRoundData();
    }

    function testPriceRevertsOnBadAnsweredInRound() public {
        uint80 _roundId = 0;
        int256 _answer = 0;
        uint256 _timestamp = 0;
        uint256 _startedAt = 0;

        // Update data into MockV3Aggregator
        MockV3Aggregator (wethUsdPriceFeed) .updateRoundData(_roundId, _answer, _timestamp, _startedAt);

        vm.expectRevert(OracleLib.OracleLib__StalePrice.selector);
        AggregatorV3Interface(wethUsdPriceFeed).staleCheckLatestRoundData();
    }
}