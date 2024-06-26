// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

/////////////////////
// Imports
/////////////////////

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {DecentralisedStableCoin} from "./DecentralisedStableCoin.sol";
import { OracleLib, AggregatorV3Interface} from "./libraries/OracleLib.sol";
// import {AggregatorV3Interface} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";




/////////////////////
// Types
/////////////////////

using OracleLib for AggregatorV3Interface; // Never Forget to declare types!!

/*
 * @title DSCEngine
 * @author Ikpong Joseph
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 DSC token == $1 peg at all times.
 * This is a stablecoin that is:
 * - Exogenously Collateralized
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was backed by only WETH and WBTC.
 *
 * Our DSC system should always be "overcollateralized". At no point, should the value of
 * all collateral < the $ backed value of all the DSC. Else that user gets liquidated.
 * Another user is then ooportuned to pay off the DSC token the undercollateralized user held, and in return gets users deposited collateral.
 *
 * @notice This contract is the core of the Decentralized Stablecoin system. It handles all the logic
 * for minting and redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is based on the MakerDAO DSS system
 */

contract DSCEngine is ReentrancyGuard {

    /////////////////////
    // Errors
    /////////////////////

    error DSCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch();
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenNotAllowed(address collateralToken);
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactorValue);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();
    
    ///////////////////
    // State Variables
    ///////////////////

    DecentralisedStableCoin private immutable i_dsc;

    /// @dev Mapping of collatera token address to price feed address
    mapping(address collateralToken => address priceFeed) private s_priceFeeds;
    /// @dev Amount of collateral deposited by user by mapping user address to the mapping of collarteral token addreess to amount
    mapping(address user => mapping(address collateralToken => uint256 amount))
        private s_collateralDeposited;
    /// @dev Amount of DSC minted by user
    mapping(address user => uint256 amount) private s_DSCMinted;
    /// @dev If we know exactly how many tokens we have, we could make this immutable!
    address[] private s_collateralTokens;

    uint256 private constant LIQUIDATION_THRESHOLD = 50; // This means you need to be 200% over-collateralized
    uint256 private constant LIQUIDATION_BONUS = 10; // This means you get assets at a 10% discount when liquidating
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    /// @dev PRECISION is the standard decimal count for ETHER
    uint256 private constant PRECISION = 1e18;
    /// @dev ADDITIONAL_FEED_PRECISION is the additional decimals needed to round the returned 1e8 chainlink price to conform to the ETHER standard 1e18.
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant FEED_PRECISION = 1e8;

    ///////////////////
    // Events
    ///////////////////
    event CollateralDeposited(
        address indexed user,
        address indexed token,
        uint256 indexed amount
    );
    event CollateralRedeemed(
        address indexed redeemFrom,
        address indexed redeemTo,
        address token,
        uint256 amount
    );
    // if redeemFrom != redeemedTo, then it was liquidated

    ///////////////////
    // Modifiers
    ///////////////////
    modifier moreThanZero(uint256 amount) {
        // Ensures that zero amounts are not transferred during a function call
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address collateralToken) {
        // To check that a token is an allowed collateral token
        if (s_priceFeeds[collateralToken] == address(0)) {
            revert DSCEngine__TokenNotAllowed(collateralToken);
        }
        _;
    }

    ///////////////////
    // Functions
    ///////////////////

    constructor(
        address[] memory collateralTokenAddresses,
        address[] memory priceFeedAddresses,
        address dscAddress
    ) {
        // Check to ensure each collateral token has a corresponding price feed address
        // It doesn't necessarily check that the price feed addresses are for the respective collateral token
        // Can it be done?
        if (collateralTokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch();
        }
        // These feeds will be the USD pairs
        // For example ETH / USD or MKR / USD
        for (uint256 i = 0; i < collateralTokenAddresses.length; i++) {
            s_priceFeeds[collateralTokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(collateralTokenAddresses[i]);
        }
        i_dsc = DecentralisedStableCoin(dscAddress);
    }

    ///////////////////
    // External Functions
    ///////////////////
    /*
     * @param tokenCollateralAddress: The ERC20 token address of the collateral you're depositing
     * @param amountCollateral: The amount of collateral you're depositing
     * @param amountDscToMint: The amount of DSC you want to mint
     * @notice This function will deposit your collateral and mint DSC in one transaction
     */
    function depositCollateralAndMintDsc(
        address collateralTokenAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(collateralTokenAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /*
     * @param tokenCollateralAddress: The ERC20 token address of the collateral you're depositing
     * @param amountCollateral: The amount of collateral you're depositing
     * @param amountDscToBurn: The amount of DSC you want to burn
     * @notice This function will withdraw your collateral and burn DSC in one transaction
     */
    function redeemCollateralForDsc(
        address collateralTokenAddress,
        uint256 amountCollateral,
        uint256 amountDscToBurn
    )
        external
        moreThanZero(amountCollateral)
        isAllowedToken(collateralTokenAddress)
    {
        _burnDsc(amountDscToBurn, msg.sender, msg.sender);
        _redeemCollateral(
            collateralTokenAddress,
            amountCollateral,
            msg.sender,
            msg.sender
        );
        revertIfHealthFactorIsBroken(msg.sender);
    }

    /*
     * @param collateralTokenAddress: The ERC20 token address of the collateral you're redeeming
     * @param amountCollateral: The amount of collateral you're redeeming
     * @notice This function will redeem your collateral.
     * @notice If you have DSC minted, you will not be able to redeem until you burn your DSC
     */
    function redeemCollateral(
        address collateralTokenAddress,
        uint256 amountCollateral
    )
        external
        moreThanZero(amountCollateral)
        nonReentrant
        isAllowedToken(collateralTokenAddress)
    {
        _redeemCollateral(
            collateralTokenAddress,
            amountCollateral,
            msg.sender,
            msg.sender
        );
        revertIfHealthFactorIsBroken(msg.sender);
    }

    /*
     * @notice careful! You'll burn your DSC here! Make sure you want to do this...
     * @dev you might want to use this if you're nervous you might get liquidated and want to just burn
     * you DSC but keep your collateral in.
     */
    function burnDsc(uint256 amount) external moreThanZero(amount /**Tested */) {
        _burnDsc(amount, msg.sender, msg.sender);
        revertIfHealthFactorIsBroken(msg.sender); // I don't think this would ever hit...
    }

    /*
     * @param collateral: The ERC20 token address of the collateral you're using to make the protocol solvent again.
     * This is collateral that you're going to take from the user who is insolvent.
     * In return, you have to burn your DSC to pay off their debt, but you don't pay off your own.
     * @param user: The user who is insolvent. They have to have a _healthFactor below MIN_HEALTH_FACTOR
     * @param debtToCover: The amount of DSC you want to burn to cover the user's debt.
     *
     * @notice: You can partially liquidate a user.
     * @notice: You will get a 10% LIQUIDATION_BONUS for taking the users funds.
    * @notice: This function working assumes that the protocol will be roughly 150% overcollateralized in order for this
    to work.
    * @notice: A known bug would be if the protocol was only 100% collateralized, we wouldn't be able to liquidate
    anyone.
     * For example, if the price of the collateral plummeted before anyone could be liquidated.
     */
    function liquidate(
        address collateral,
        address user,
        uint256 debtToCover
    ) external moreThanZero(debtToCover) nonReentrant {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }
        // If covering 100 DSC, we need to $100 of collateral
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(
            collateral,
            debtToCover
        );
        // And give them a 10% bonus
        // So we are giving the liquidator $110 of WETH for 100 DSC
        // We should implement a feature to liquidate in the event the protocol is insolvent
        // And sweep extra amounts into a treasury
        uint256 bonusCollateral = (tokenAmountFromDebtCovered *
            LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        // Burn DSC equal to debtToCover
        // Figure out how much collateral to recover based on how much burnt
        // _redeemCollateral(
        // address collateralTokenAddress,
        // uint256 amountCollateral,
        // address from, i.e liquidated user
        // address to i.e liquidator
        _redeemCollateral(
            collateral,
            tokenAmountFromDebtCovered + bonusCollateral,
            user,
            msg.sender
        );
        _burnDsc(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        // This conditional should never hit, but just in case
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        revertIfHealthFactorIsBroken(msg.sender);
    }

    ///////////////////
    // Public Functions
    ///////////////////
    /*
     * @param amountDscToMint: The amount of DSC you want to mint
     * You can only mint DSC if you have enough collateral
     */
    function mintDsc(
        uint256 amountDscToMint
    ) public moreThanZero(amountDscToMint /**Tested */) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        revertIfHealthFactorIsBroken(msg.sender); // Tested
        bool minted = i_dsc.mint(msg.sender, amountDscToMint); // Mints DSC from DecentralisedtableCoin.sol

        if (minted != true) {
            revert DSCEngine__MintFailed();
        } // Tested
    }

    /*
     * @param tokenCollateralAddress: The ERC20 token address of the collateral you're depositing
     * @param amountCollateral: The amount of collateral you're depositing
     */
    function depositCollateral(
        address collateralTokenAddress,
        uint256 amountCollateral
    )
        public
        moreThanZero(amountCollateral)
        nonReentrant
        isAllowedToken(collateralTokenAddress)
    {
        s_collateralDeposited[msg.sender][
            collateralTokenAddress
        ] += amountCollateral;
        emit CollateralDeposited(
            msg.sender,
            collateralTokenAddress,
            amountCollateral
        );
        bool success = IERC20(collateralTokenAddress).transferFrom(
            msg.sender,
            address(this),
            amountCollateral
        );
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    ///////////////////
    // Private Functions
    ///////////////////
    // Transfers collateral from liquidated user to liquidator
    function _redeemCollateral(
        address collateralTokenAddress,
        uint256 amountCollateral,
        address from,
        address to
    ) private {
        s_collateralDeposited[from][collateralTokenAddress] -= amountCollateral;
        emit CollateralRedeemed(
            from,
            to,
            collateralTokenAddress,
            amountCollateral
        );
        bool success = IERC20(collateralTokenAddress).transfer(
            to,
            amountCollateral
        );
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _burnDsc(
        uint256 amountDscToBurn,
        address onBehalfOf,
        address dscFrom
    ) private {
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;

        bool success = i_dsc.transferFrom(
            dscFrom,
            address(this),
            amountDscToBurn
        );
        // This conditional is hypothetically unreachable
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn); // Calls burn from DecentralisedStableCoin.sol
    }

    //////////////////////////////
    // Private & Internal View & Pure Functions
    //////////////////////////////

    function _getAccountInformation(
        address user
    )
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    function _healthFactor(address user) private view returns (uint256) {
        (
            uint256 totalDscMinted,
            uint256 collateralValueInUsd
        ) = _getAccountInformation(user);
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    function _getUsdValue(
        address token,
        uint256 amount
    ) private view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.staleCheckLatestRoundData();
        // This returns the USD value for a specific amount of any supported token.
        // How much in USD does this amount of token worth?
        // 1 ETH = 1000 USD
        // The returned value from Chainlink will be 1000 * 1e8
        // Most USD pairs have 8 decimals, so we will just pretend they all do
        // We want to have everything in terms of WEI, i.e *1e18, so we add 10 zeros at the end
        // The multiplication of powers = the addition of it. 10e8 * 10e10 = 10e(8+10) == 10e18. Just so we can uniformly make calculations
        // price is wrapped as a uint256 because Chainlink returns price as an int256, and we need it conform with thhhhhe rest of values we'd be calculating with.
        // Therefore, USD value will be USD1e18.
        // USD value = Token price in USD * token amount
        return
            ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function _calculateHealthFactor(
        uint256 totalDscMinted,
        uint256 collateralValueInUsd
    ) internal pure returns (uint256) {
        if (totalDscMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd *
            LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    /**
    * This calculates users health factor
    * Checks _healthFactor(user)
    * Houses mandatory check and error if users health is less than MIN_HEALTH_FACTOR
    */

    function revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    ////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////
    // External & Public View & Pure Functions
    ////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////
    
    function calculateHealthFactor(
        uint256 totalDscMinted,
        uint256 collateralValueInUsd
    ) external pure returns (uint256) {
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    function getAccountInformation(
        address user
    )
        external
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        return _getAccountInformation(user);
    }

    function getUsdValue(
        address token,
        uint256 amount // in WEI
    ) external view returns (uint256) {
        return _getUsdValue(token, amount);
    }

    function getCollateralBalanceOfUser(
        address user,
        address token
    ) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getAccountCollateralValue(
        address user
    ) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 index = 0; index < s_collateralTokens.length; index++) {
            address token = s_collateralTokens[index];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += _getUsdValue(token, amount);
            // totalCollateralValueInUsd is added to _getUsdValue for user per loop in the case that a user deposited multiple collateral tokens.
        }
        return totalCollateralValueInUsd;
    }

    function getTotalDscMinted(address user) public view returns (uint256) {
        return s_DSCMinted[user];
    }

    function getTokenAmountFromUsd(
        address collateralToken,
        uint256 usdAmountInWei /* USDe18 */
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[collateralToken]
        );
        (, int256 price, , , ) = priceFeed.staleCheckLatestRoundData();
        // How much of a certain token can I get if I have a certan amount of USD? Reverse of _getUsdValue()
        // USD amount / Token price
        // $100e18 USD Debt
        // 1 ETH = 2000 USD
        // The returned value from Chainlink will be 2000 * 1e8
        // Most USD pairs have 8 decimals, so we will just pretend they all do
        // Token amount from USD will be to e18.
        
        return ((usdAmountInWei * PRECISION) /
            (uint256(price) * ADDITIONAL_FEED_PRECISION));
        // (e18 * e18)/(e8 * e10) 
        // (e18+18)/(e8+10)
        // (e36-18) = (e18)
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getDsc() external view returns (address) {
        return address(i_dsc);
    }

    function getCollateralTokenPriceFeed(
        address collateralToken
    ) external view returns (address) {
        return s_priceFeeds[collateralToken];
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }
}
