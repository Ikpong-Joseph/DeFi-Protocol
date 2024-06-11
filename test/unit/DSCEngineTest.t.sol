// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {DecentralisedStableCoin} from "src/DecentralisedStableCoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {ERC20Burnable, ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {MockFailedMintDSC} from "../mocks/MockFailedMintDSC.sol";
import {MockMoreDebtDSC} from "../mocks/MockMoreDebtDSC.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract DSCEngineTest is StdCheats, Test {
    DSCEngine public dscEngine;
    DecentralisedStableCoin public dsc;
    HelperConfig public helperConfig;

    address USER = makeAddr("user");
    address USER2 = makeAddr("user2");

    address LIQUIDATOR = makeAddr("liquidator");

    address wethUsdPriceFeed;
    address wbtcUsdPriceFeed;
    address weth;
    address wbtc;

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    uint public constant STARTING_COLLATERAL_BALANCE = 10 ether; // USD value = 20,000
    uint public constant AMOUNT_DSC_MINTED = 150e18; // USD value = 150. 1DSC = 1$
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // This means you need to be 200% over-collateralized
    uint256 private constant LIQUIDATION_BONUS = 10; // This means you get assets at a 10% discount when liquidating
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    /// @dev PRECISION is the standard decimal count for ETHER
    uint256 private constant PRECISION = 1e18;
    /// @dev ADDITIONAL_FEED_PRECISION is the additional decimals needed to round the returned 1e8 chainlink price to conform to the ETHER standard 1e18.
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant FEED_PRECISION = 1e8;

    /////////////
    // Modifiers
    ////////////

    modifier DscMinted() {
        vm.prank(USER);
        ERC20Mock(weth).approve(
            address(dscEngine),
            STARTING_COLLATERAL_BALANCE
        );

        // They call depositCollateral properly
        vm.prank(USER);
        dscEngine.depositCollateral(weth, STARTING_COLLATERAL_BALANCE);

        vm.prank(USER);
        dscEngine.mintDsc(AMOUNT_DSC_MINTED);
        _;
    }

    modifier collateralDeposited() {
        vm.prank(USER);
        ERC20Mock(weth).approve(
            address(dscEngine),
            STARTING_COLLATERAL_BALANCE
        );

        // They call depositCollateral properly
        vm.prank(USER);
        dscEngine.depositCollateral(weth, STARTING_COLLATERAL_BALANCE);
        _;
    }

    // function testCheckHealthFactor() external collateralDeposited{
    //     uint256 actualUsdValueWWeth = dscEngine.getUsdValue(weth, STARTING_COLLATERAL_BALANCE);
    //     uint256 maxAllowableDscMinted = 10000e18;
    //     uint256 excessDscMinted = 20000e18;
    //     // Protoocol is 200% collateralized
    //     /// We can only mint DSC worth half the USD value of our collateral
    //     // We deposited 10 weth. Each is $2000. Toal USD worth = 20,000
    //     // 1DSC = $1
    //     // 10,000 is max

    //     // CollateralAdjustedForThreshold = (collateralValueInUsd *LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
    //   //(collateralAdjustedForThreshold * PRECISION) / totalDscMinted;

    //     //( ((20000*50)/100)*1e18)/10000e18
    //     vm.prank(USER);
    //     dscEngine.mintDsc(excessDscMinted);
    //     uint256 healthFactor = dscEngine.getHealthFactor(USER);
    //     console.log("Actual USD value of WETH is ", actualUsdValueWWeth);
    //     console.log("Total collateral, WETH, deposited is ", STARTING_COLLATERAL_BALANCE);
    //     console.log("Total DSC minted is ", excessDscMinted);
    //     console.log("User health Factor is ", healthFactor);
    //     console.log("User health Factor should be 0.5");

    // }

    //////////
    // setUp
    //////////

    function setUp() public {
        DeployDSC deployer = new DeployDSC();
        (dsc, dscEngine, helperConfig) = deployer.run();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc, ) = helperConfig
            .activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_COLLATERAL_BALANCE);
    }

    ////////////////////
    // Constructor Tests
    /////////////////////

    function testRevertIfTokenAndPricefeedsLengthDontMatch() external {
        HelperConfig hConfig = new HelperConfig();
        (wethUsdPriceFeed, , weth, wbtc, ) = helperConfig.activeNetworkConfig();

        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed];
        vm.expectRevert();
        // DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch.selector
        // Why is my custom error not working?
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    function testWorksIfTokenAndPricefeedsLengthMatch() external {
        HelperConfig hConfig = new HelperConfig();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc, ) = helperConfig
            .activeNetworkConfig();

        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    ////////////////////////////
    // Deposit Collateral Tests
    /////////////////////////////

    // depositCollateralAndMintDsc()

    function testDepositCollateralWorks() external {
        // Deal user some weth or erc20

        vm.prank(USER);
        ERC20Mock(weth).approve(
            address(dscEngine),
            STARTING_COLLATERAL_BALANCE
        );
        console.log(
            "User weth balance is : ",
            (ERC20Mock(weth).balanceOf(USER)) / 1e18,
            "ether"
        );

        // They call depositCollateral properly
        vm.prank(USER);
        dscEngine.depositCollateral(weth, STARTING_COLLATERAL_BALANCE);
        // WE check that mmappings are updated
        uint256 depositedCollateral = dscEngine.getCollateralBalanceOfUser(
            USER,
            weth
        );
        assertEq(depositedCollateral, STARTING_COLLATERAL_BALANCE);
    }

    function testDepositCollateralRevertsWithZeroCollateralAmount() external {
        uint256 zeroCollateralDeposited = 0;
        console.log(
            "DSCEngine__NeedsMoreThanZero: You must deposit more than Zero collateral(weth)"
        );
        console.log(
            "User weth balance is : ",
            (ERC20Mock(weth).balanceOf(USER)) / 1e18,
            "ether. And they still try to deposit 0. Stingy much."
        );

        vm.prank(USER);
        ERC20Mock(weth).approve(
            address(dscEngine),
            STARTING_COLLATERAL_BALANCE
        );

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        // They call depositCollateral properly
        vm.prank(USER);
        dscEngine.depositCollateral(weth, zeroCollateralDeposited);
    }

    function testDepositCollateralRevertsWithWrongCollateralToken() external {
        ERC20Mock wt = new ERC20Mock(
            "Wrong Token",
            "WT",
            USER,
            STARTING_COLLATERAL_BALANCE
        ); // Creates new instance of the ERC20Mock contract and called wt

        vm.startPrank(USER);
        ERC20Mock(wt).approve(address(dscEngine), STARTING_COLLATERAL_BALANCE);
        console.log(
            "User wt balance is : ",
            (ERC20Mock(wt).balanceOf(USER)) / 1e18,
            "ether"
        );

        vm.expectRevert();
        console.log("DSCEngine__TokenNotAllowed(wt)");

        dscEngine.depositCollateral(address(wt), STARTING_COLLATERAL_BALANCE);
        vm.stopPrank();
    }

    //////////////////
    // Mint DSC Tests
    /////////////////

    function testRevertsIfMintFails() public {
        // Arrange - Setup
        MockFailedMintDSC mockDsc = new MockFailedMintDSC();
        tokenAddresses = [weth];
        priceFeedAddresses = [wethUsdPriceFeed];
        address owner = msg.sender;
        vm.prank(owner);
        DSCEngine mockDsce = new DSCEngine(
            tokenAddresses,
            priceFeedAddresses,
            address(mockDsc)
        );
        mockDsc.transferOwnership(address(mockDsce));
        // Arrange - User
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(mockDsce), STARTING_COLLATERAL_BALANCE);

        vm.expectRevert(DSCEngine.DSCEngine__MintFailed.selector);
        mockDsce.depositCollateralAndMintDsc(
            weth,
            STARTING_COLLATERAL_BALANCE,
            AMOUNT_DSC_MINTED
        );
        vm.stopPrank();
    }

    function testMintDscRevertsWithZeroDepositedCollateral() external {
        uint256 excessDscMinted = 20000e18;
        uint256 collateralValueInUsd = dscEngine.getUsdValue(
            weth,
            STARTING_COLLATERAL_BALANCE
        );
        uint256 userHealthFactor = dscEngine.calculateHealthFactor(
            excessDscMinted,
            collateralValueInUsd
        );
        // uint256 userHealthFactor2 = dscEngine.getHealthFactor(USER);

        vm.prank(USER);
        vm.expectRevert();
        console.log(
            "User health factor using dscEngine.calculateHealthFactor is ",
            userHealthFactor
        );
        // console.log("User health factor using dscEngine.getHealthFactor is ", userHealthFactor2);
        console.log(
            "For checking the revertIfHealthFactorIsBroken check, using dscEngine.calculateHealthFactor to directly calculate userHealthFactor is Ideal as compared to dscEngine.getHealthFactor which has to call from _getAccountInformation(user) before _calculateHealthFactor. Probably is appropriate to call after DSC minting (Check the commented testCheckHealthFactor() in DSCEngineTest.t.sol)."
        );

        console.log(
            "Error is DSCEngine__BreaksHealthFactor",
            (userHealthFactor),
            "."
        );
        // userHealthFactor == 0.50000000000000000
        dscEngine.mintDsc(excessDscMinted);
    }

    function testMintDscRevertsIfHealthFactorIsBroken()
        external
        collateralDeposited
    {
        uint256 excessDscMinted = 20000e18;
        uint256 userHealthFactor = dscEngine.calculateHealthFactor(
            excessDscMinted,
            dscEngine.getUsdValue(weth, STARTING_COLLATERAL_BALANCE)
        );

        vm.prank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__BreaksHealthFactor.selector,
                userHealthFactor
            )
        );
        dscEngine.mintDsc(excessDscMinted);
    }

    function testMintDscRevertsWithZeroDscAmount()
        external
        collateralDeposited
    {
        uint256 zeroDscMinted = 0;
        console.log(
            "DSCEngine__NeedsMoreThanZero: You must mint more than Zero DSC"
        );
        console.log(
            "User collateral(weth) balance is: ",
            (dscEngine.getCollateralBalanceOfUser(USER, weth)) / 1e18,
            "ether"
        );
        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.mintDsc(zeroDscMinted);
    }

    function testSuccessfulMint() external collateralDeposited {
        vm.prank(USER);
        dscEngine.mintDsc(AMOUNT_DSC_MINTED);

        uint256 usersMintedDscBalance = dscEngine.getTotalDscMinted(USER);

        assert(usersMintedDscBalance == AMOUNT_DSC_MINTED);
    }

    /////////////////
    // Burn DSC Tests
    /////////////////

    function testBurnDscWorks() external DscMinted {
        uint256 userInitialMintedDscBalance = dscEngine.getTotalDscMinted(USER);

        vm.startPrank(USER);
        // SInce our dsc is now an ERC20,
        // dsc must approve for its token, dsc, to be sent to address(0)
        // by dscEngine on behalf of caller. CONFUSING.
        // ERC20 implementation of approve
        //  approve(address spender, uint256 amount)
        // address owner = _msgSender();
        // _approve(owner, spender, amount);

        dsc.approve(address(dscEngine), AMOUNT_DSC_MINTED);

        dscEngine.burnDsc(AMOUNT_DSC_MINTED);

        vm.stopPrank();

        uint256 userFinalMintedDscBalance = dscEngine.getTotalDscMinted(USER);

        assert(userInitialMintedDscBalance == AMOUNT_DSC_MINTED);
        assert(dscEngine.getTotalDscMinted(USER) == 0);
    }

    function testBurnDscRevertsWithZeroAmount() external DscMinted {
        uint256 zeroAmountDsc = 0;

        vm.startPrank(USER);
        // SInce our dsc is now an ERC20,
        // dsc must approve for its token, dsc, to be sent to address(0)
        // by dscEngine on behalf of caller. CONFUSING.

        dsc.approve(address(dscEngine), AMOUNT_DSC_MINTED);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        console.log(
            "DSCEngine__NeedsMoreThanZero: You must burn more than Zero DSC"
        );
        dscEngine.burnDsc(zeroAmountDsc);

        vm.stopPrank();
    }

    /////////////////////////////////////////////
    // Deposit Collateral And mint DSC Tests
    //////////////////////////////////////////

    function testdepositCollateralAndMintDsc() external collateralDeposited {
        vm.prank(USER);
        dscEngine.mintDsc(AMOUNT_DSC_MINTED);
        uint256 usersTotalMintedDscA = dscEngine.getTotalDscMinted(USER);
        uint256 userCollateralValueInUsd = dscEngine.getAccountCollateralValue(
            USER
        );
        uint256 expectedCollateralUsdValue = 20000e18;

        assert(usersTotalMintedDscA == AMOUNT_DSC_MINTED);
        assert(userCollateralValueInUsd == expectedCollateralUsdValue);
    }

    ////////////////////////////
    // Redeem Collateral Tests
    /////////////////////////////

    function testredeemCollateralWontWorkForZeroAmount()
        external
        collateralDeposited
    {
        uint zeroAmountCollateral = 0;
        vm.prank(USER);
        vm.expectRevert();
        dscEngine.redeemCollateral(weth, zeroAmountCollateral);
    }

    function testredeemCollateralWontWorkForUndepositedCollateralToken()
        external
        collateralDeposited
    {
        // User deposited weth.
        // Check modifier collateralDeposited
        address undepositedCollateralToken = wbtc;
        vm.prank(USER);
        vm.expectRevert();
        dscEngine.redeemCollateral(
            undepositedCollateralToken,
            STARTING_COLLATERAL_BALANCE
        );
    }

    function testredeemCollateralWorks() external collateralDeposited {
        uint256 userWethBalanceAfterDepositingCollateral = ERC20Mock(weth)
            .balanceOf(USER);
        // Check that they have collateral balance
        uint256 userDepositedCollateralBeforeRedeeming = dscEngine
            .getCollateralBalanceOfUser(USER, weth);

        // Check that they have not minted DSC
        uint256 userDscBalance = dscEngine.getTotalDscMinted(USER);

        vm.prank(USER);
        dscEngine.redeemCollateral(weth, STARTING_COLLATERAL_BALANCE);

        uint256 userCollateralBalanceAfterRedeeming = dscEngine
            .getCollateralBalanceOfUser(USER, weth);
        uint256 userWethBalanceAfterRedeeming = ERC20Mock(weth).balanceOf(USER);

        assert(userDscBalance == 0);
        assert(userWethBalanceAfterDepositingCollateral == 0);
        assertEq(
            userDepositedCollateralBeforeRedeeming,
            STARTING_COLLATERAL_BALANCE
        );
        assert(userWethBalanceAfterRedeeming == STARTING_COLLATERAL_BALANCE);
    }

    function testRedeemCollateralWontWorkIfUserHasDsc() external DscMinted {
        // Instead of user calling redeemCollateralForDsc
        // You can only redeem Collateral if you burn your minted DSC. If you minted any.
        vm.prank(USER);
        vm.expectRevert();
        dscEngine.redeemCollateral(weth, STARTING_COLLATERAL_BALANCE);
    }

    ///////////////////////////////////
    // Redeem Collateral  For DSC Tests
    ////////////////////////////////////

    function testredeemCollateralForDscRevertsWithZeroCollateralAmount()
        external
        DscMinted
    {
        uint256 zeroCollateralAmount = 0;
        vm.startPrank(USER);
        dsc.approve(address(dscEngine), AMOUNT_DSC_MINTED);
        vm.expectRevert();
        console.log(
            "DSCEngine__NeedsMoreThanZero: You must redeem deposited collateral for minted DSC with   more than zero amount of deposited collateral."
        );
        dscEngine.redeemCollateralForDsc(
            weth,
            zeroCollateralAmount,
            AMOUNT_DSC_MINTED
        );
        vm.stopPrank();
    }

    function testredeemCollateralForDscRevertsWithUndepositedCollateralToken()
        external
        DscMinted
    {
        // USER deposited weth as collateral. Check modifier DscMinted
        // We test with wbtc
        vm.startPrank(USER);
        dsc.approve(address(dscEngine), AMOUNT_DSC_MINTED);
        vm.expectRevert();
        console.log(
            "DSCEngine__TokenNotAllowed(wbtc): You must redeem deposited collateral for minted DSC only with exact collateral token."
        );
        dscEngine.redeemCollateralForDsc(
            wbtc,
            STARTING_COLLATERAL_BALANCE,
            AMOUNT_DSC_MINTED
        );
        vm.stopPrank();
    }

    function testredeemCollateralForDscRevertsWithZeroDscAmount()
        external
        DscMinted
    {
        uint256 zeroDsc = 0;
        vm.startPrank(USER);
        dsc.approve(address(dscEngine), AMOUNT_DSC_MINTED);
        vm.expectRevert();
        console.log(
            "DSCEngine__NeedsMoreThanZero: You must redeem deposited collateral for more than zero amount of minted DSC."
        );
        dscEngine.redeemCollateralForDsc(
            weth,
            STARTING_COLLATERAL_BALANCE,
            zeroDsc
        );
        vm.stopPrank();
    }

    function testredeemCollateralForDscWorks() external DscMinted {
        // Check user DSC balance Before and after Collateral Redeedming
        uint256 userDscBalanceBeforeRedeemingCollateral = dscEngine
            .getTotalDscMinted(USER);

        uint256 userDepositedCollateralBeforeRedeemingCollateral = dscEngine
            .getCollateralBalanceOfUser(USER, weth);

        uint256 userWethBalanceBeforeRedeeming = ERC20Mock(weth).balanceOf(
            USER
        );

        // Check User weth Balance before and after redeeming collateral
        // Before you call any function that calls dscEngine._burnDsc
        // You must prank USER and approve dscEngine to spend token. WIERD.
        vm.startPrank(USER);
        dsc.approve(address(dscEngine), AMOUNT_DSC_MINTED);

        dscEngine.redeemCollateralForDsc(
            weth,
            STARTING_COLLATERAL_BALANCE,
            AMOUNT_DSC_MINTED
        );
        vm.stopPrank();
        uint256 userDscBalanceAfterRedeemingCollateral = dscEngine
            .getTotalDscMinted(USER);
        uint256 userWethBalanceAfterRedeeming = ERC20Mock(weth).balanceOf(USER);
        uint256 userDepositedCollateralAfterRedeemingCollateral = dscEngine
            .getCollateralBalanceOfUser(USER, weth);

        assert(userDscBalanceBeforeRedeemingCollateral == AMOUNT_DSC_MINTED);
        console.log(
            "User DSC balance before collateral redemption is ",
            userDscBalanceBeforeRedeemingCollateral
        );
        assert(
            userDepositedCollateralBeforeRedeemingCollateral ==
                STARTING_COLLATERAL_BALANCE
        );
        assert(userWethBalanceBeforeRedeeming == 0);
        console.log(
            "User DSC balance after collateral redemption is ",
            userDscBalanceAfterRedeemingCollateral
        );
        assert(userDscBalanceAfterRedeemingCollateral == 0);
        // assert(userDepositedCollateralAfterRedeemingCollateral == 0);
        // assert(userWethBalanceAfterRedeeming == STARTING_COLLATERAL_BALANCE);
    }

    /////////////////
    // Getters Tests
    /////////////////

    function testgetAccountCollateralValue() external collateralDeposited {
        // weth price was set to 2000e8 per weth in HelperConfig.sol
        // USER deposited 10 ether.
        // expectedCollateralUsdValue = weth price * deposited collateral.
        // Exact math in DSCEngine.sol; _getUsdValue
        uint256 expectedCollateralUsdValue = 20000e18;
        uint256 actualCollateralUsdValue = dscEngine.getAccountCollateralValue(
            USER
        );
        assert(expectedCollateralUsdValue == actualCollateralUsdValue);
    }

    function testGetUsdValue() external {
        // For wbtc
        // 1wbtc = $1000e8 == priceOfWbtc.
        // Check HelperConfig.s.sol

        uint256 amountOfWbtc = 10;

        // Logic of getUsdValue() in DSCEngine is
        // ((uint256(priceOfWbtc) * ADDITIONAL_FEED_PRECISION) * amountOfWbtc) / PRECISION
        // ADDITIONAL_FEED_PRECISION = 1e10 (Because oraccccccccle returns price as e8)
        // PRECISION = 1e18

        uint256 expectedUsdValueOfWbtc = 10000;
        uint256 actualUsdValueOfWbtc = dscEngine.getUsdValue(
            wbtc,
            amountOfWbtc
        );
        console.log("Actual USD value of wbtc is ", actualUsdValueOfWbtc);

        assert(expectedUsdValueOfWbtc == actualUsdValueOfWbtc);
    }

    function testGetTokenAmountFromUsd() external {
        // For weth
        // 1weth = $2000e8 == priceOfWeth.
        // Check HelperConfig.s.sol

        uint256 usdAmountInWei = 10000e18;

        // Logic of getUsdValue() in DSCEngine is
        // USD amount / Token price
        // (((usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION))
        // ADDITIONAL_FEED_PRECISION = 1e10 (Because oracle returns price as e8)
        // PRECISION = 1e18

        uint256 expectedWethAmount = 5e18;
        uint256 actualWethAmount = dscEngine.getTokenAmountFromUsd(
            weth,
            usdAmountInWei
        );
        console.log(
            "Actual weth gotten from $",
            usdAmountInWei / 1e18,
            " is ",
            actualWethAmount
        );

        assert(expectedWethAmount == actualWethAmount);
    }

    function testGetAccountInformation() external DscMinted {
        // Call the getAccountInformation function for the user
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine
            .getAccountInformation(USER);

        // Define the expected values
        uint256 expectedTotalDscMinted = dscEngine.getTotalDscMinted(USER);
        uint256 expectedCollateralValueInUsd = dscEngine
            .getAccountCollateralValue(USER);

        // Assert that the returned values match the expected values
        assert(totalDscMinted == expectedTotalDscMinted);
        assert(collateralValueInUsd == expectedCollateralValueInUsd);
    }

    function testCalculateHealthFactor() external DscMinted {
        // Define the total DSC minted and collateral value in USD
        uint256 totalDscMinted = dscEngine.getTotalDscMinted(USER);
        uint256 collateralValueInUsd = dscEngine.getAccountCollateralValue(
            USER
        ); // Example amount

        // Call the calculateHealthFactor function
        uint256 healthFactor = dscEngine.calculateHealthFactor(
            totalDscMinted,
            collateralValueInUsd
        );

        // Calculate the expected health factor
        // Assuming the health factor is calculated as (collateralValueInUsd * LIQUIDATION_THRESHOLD) / (totalDscMinted * PRECISION)
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd *
            LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        uint256 expectedHealthFactor = (collateralAdjustedForThreshold *
            PRECISION) / totalDscMinted;

        // Assert that the returned health factor matches the expected health factor
        assertEq(healthFactor, expectedHealthFactor);
    }

    function testGetHealthFactor() external DscMinted {
        vm.prank(USER);
        uint256 userHealthFactor = dscEngine.getHealthFactor(USER);
        uint256 mminimumHealthFactor = dscEngine.getMinHealthFactor();

        console.log("User health factor is ", userHealthFactor);
        console.log(
            "This protocols minimum user health factor is ",
            mminimumHealthFactor
        );

        assert(userHealthFactor > mminimumHealthFactor);
    }

    function testGetCollateralTokenPriceFeed() external {
        vm.prank(USER);
        address wethPriceFeed = dscEngine.getCollateralTokenPriceFeed(weth);
        address wbtcPriceFeed = dscEngine.getCollateralTokenPriceFeed(wbtc);

        assert(wethPriceFeed == wethUsdPriceFeed);
        assert(wbtcPriceFeed == wbtcUsdPriceFeed);
    }

    function testGetDscContractAddress() external {
        address dscContractAddress = dscEngine.getDsc();

        assert(dscContractAddress == address(dsc));
    }

    function testGetCollateralTokens() external {
        // Call the getCollateralTokens function
        address[] memory returnedCollateralTokens = dscEngine
            .getCollateralTokens();

        // Define the expected array of collateral token addresses
        // This should match the collateral tokens you've added to the s_collateralTokens array in your setup.
        address[2] memory expectedCollateralTokens = [weth, wbtc];

        // Assert that the length of the returned array matches the expected array
        assert(
            returnedCollateralTokens.length == expectedCollateralTokens.length
        );

        // Loop through the arrays and assert that each element matches
        for (uint i = 0; i < returnedCollateralTokens.length; i++) {
            assertEq(returnedCollateralTokens[i], expectedCollateralTokens[i]);
        }
    }

    function testGetLiquidationPrecision() external {
        uint256 liquidationPrecision = dscEngine.getLiquidationPrecision();

        assert(liquidationPrecision == 100);

        // LIQUIDATION_PRECISION is hardcoded 100 in DSCEngine.sol
    }

    function testGetLiquidationBonus() external {
        uint256 liquidationBonus = dscEngine.getLiquidationBonus();

        assert(liquidationBonus == 10);

        // LIQUIDATION_BONUS is hardcoded 10 in DSCEngine.sol
    }

    function testGetLiquidationThreshold() external {
        uint256 liquidationThreshold = dscEngine.getLiquidationThreshold();

        assert(liquidationThreshold == 50);

        // LIQUIDATION_THRESHOLD is hardcoded 50 in DSCEngine.sol
    }

    function testGetAdditionalFeedPrecision() external {
        uint256 AdditionalFeedPrecision = dscEngine
            .getAdditionalFeedPrecision();

        assert(AdditionalFeedPrecision == 1e10);

        // ADDITIONAL_FEED_PRECISION is hardcoded 1e10 in DSCEngine.sol
    }

    function testGetPrecision() external {
        uint256 Precision = dscEngine.getPrecision();

        assert(Precision == 1e18);

        // PRECISION is hardcoded 1e18 in DSCEngine.sol
    }

    ////////////////////
    // Liquidation Tests
    ////////////////////

    // Create new user; liquidator

    function testLiquidateRevertsWithOkHealthFactor() external DscMinted {
        // This test should revert for the following reasons
        // 1. LIQUIDATOR is trying to liquidate USER. Check modifier DscMinted
        // 2. LIQUIDATOR has no collateral or DSCs.
        // But first check is that the liquidated users Health factor is OK or not before liquidating
        uint256 userHealthFactor = dscEngine.getHealthFactor(USER);

        console.log(
            "User about to be liquidated has OK health factor of ",
            userHealthFactor
        );
        vm.prank(LIQUIDATOR);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        dscEngine.liquidate(weth, USER, STARTING_COLLATERAL_BALANCE);
    }

    function testLiquidateRevertsWhenLiquidatorHasBrokenHealthFactor()
        external
    {
        // vm.prank(LIQUIDATOR);
        // ERC20Mock(weth).approve(
        //     address(dscEngine),
        //     STARTING_COLLATERAL_BALANCE
        // );

        // uint256 liquidatorBalance = ERC20Mock(weth).balanceOf(LIQUIDATOR);
        // console.log("Liquidator weth balance is ", liquidatorBalance);

        // // They call depositCollateral properly
        // vm.prank(LIQUIDATOR);
        // dscEngine.depositCollateral(weth, STARTING_COLLATERAL_BALANCE);

        // vm.prank(LIQUIDATOR);
        // dscEngine.mintDsc(AMOUNT_DSC_MINTED);
        // // vm.stopPrank();

        vm.prank(USER);
        ERC20Mock(weth).approve(
            address(dscEngine),
            STARTING_COLLATERAL_BALANCE
        );

        uint256 depositedCollateral = 5 ether;
        uint256 userRemainingWethBalance = 5 ether;

        // They call depositCollateral properly
        vm.prank(USER);
        dscEngine.depositCollateral(weth, depositedCollateral);

        vm.prank(USER);
        dscEngine.mintDsc(depositedCollateral);

        vm.prank(USER);
        address to = LIQUIDATOR;
        uint256 amountDsc = dscEngine.getTotalDscMinted(USER);
        vm.prank(USER);
        IERC20(dsc).transfer(to, amountDsc);

        uint256 userHealthFactor = dscEngine.getHealthFactor(LIQUIDATOR);

        console.log(
            "Liquidator has broken health factor of ",
            userHealthFactor
        );
        vm.prank(LIQUIDATOR);
        vm.expectRevert();
        dscEngine.liquidate(weth, USER, STARTING_COLLATERAL_BALANCE);
    }

    // Need some fuzz test. Lord!
}
