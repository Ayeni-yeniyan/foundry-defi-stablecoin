// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
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
// view & pure functions

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;
import {DecentralisedStableCoin} from "src/DecentralisedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**`
 * title: DSCEngine
 * author: Ayeni Samuel
 *
 * The system is designed to be as minimal as possible, and have the token maintain a 1 to 1 ration to USD
 * Coin Properties
 * Exogenous Collateral
 * Dollar Pegged
 * Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees and was only backed by wETH and wBTC
 *
 * @notice This contract is the core of the DSC system. It handles all the logic for mining and redeeming
 * as well as depositing & withdrawing collateral
 * @notice This contract is very loosely based on he MakerDAO DSS (DAI) system
 */

contract DSCEngine is ReentrancyGuard {
    // Errors
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressesAndPricefeedAddressesNotEqual();
    error DSCEngine__DscAddressCannotBeZeroAddress();
    error DSCEngine__TokenAddressNotAllowed();
    error DSCEngine__TransferFailed();
    error DSCEngine__MintFailed();
    error DSCEngine__BreaksHealthFactor(uint256 userHealthFactor);
    error DSCEngine__HealthFactorOkay();
    error DSCEngine__HealthFactorNotImproved();
    error DSCEngine__ZeroCollateral();

    // State Variables
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATION_BONUS = 10;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    mapping(address token => address priceFeed) s_priceFeeds;
    mapping(address user => mapping(address token => uint256)) s_collateralsDeposited;
    mapping(address user => uint256 amountDscMinted) s_DSCMinted;
    address[] private s_collateralTokens;
    DecentralisedStableCoin private i_dsc;

    // Events
    event CollateralDeposited(
        address indexed user,
        address indexed token,
        uint256 indexed amount
    );
    event CollateralRedeemed(
        address indexed from,
        address indexed to,
        uint256 indexed amount,
        address token
    );
    // Modifier
    modifier moreThanZero(uint256 _amount) {
        if (_amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address _tokenAddress) {
        address tokenAddress = s_priceFeeds[_tokenAddress];
        if (tokenAddress == address(0)) {
            revert DSCEngine__TokenAddressNotAllowed();
        }
        _;
    }

    // Functions
    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses,
        address dscAddress
    ) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPricefeedAddressesNotEqual();
        }
        if (address(0) == dscAddress) {
            revert DSCEngine__DscAddressCannotBeZeroAddress();
        }
        for (uint i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralisedStableCoin(dscAddress);
    }

    // External functions

    /**
     * @notice Follows CEI
     * @param tokenCollateral The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     */
    function depositCollateral(
        address tokenCollateral,
        uint256 amountCollateral
    )
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateral)
        nonReentrant
    {
        s_collateralsDeposited[msg.sender][tokenCollateral] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateral, amountCollateral);
        bool success = IERC20(tokenCollateral).transferFrom(
            msg.sender,
            address(this),
            amountCollateral
        );
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     * @notice This token calls depositCollateral and mintDsc
     * @param tokenCollateral This id the address of the token to depostice sollateral
     * @param amountCollateral This is the amount to be deposited
     * @param amountDscToMint This is the amount to be minted
     */
    function depositCollateralAndMintDsc(
        address tokenCollateral,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateral, amountCollateral);
        mintDsc(amountDscToMint);
    }

    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) public moreThanZero(amountCollateral) nonReentrant {
        _redeemCollateral(
            tokenCollateralAddress,
            amountCollateral,
            msg.sender,
            msg.sender
        );
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice This token calls burnDsc and redeemCollateral
     * @param tokenCollateralAddress This id the address of the token to depostice sollateral
     * @param amountCollateral This is the amount to be deposited
     * @param amountDscToBurn This is the amount to be burned
     */
    function redeemCollateralAndBurnDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToBurn
    ) external {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
        // Health fact is checked in redeemCollateral
    }

    /**
     *
     * @param amountDscToMint Amount of stable coin to mint
     * @notice They must have more than minimum threshold and more collateral
     */
    function mintDsc(
        uint256 amountDscToMint
    ) public moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDsc(
        uint256 amountDscToBurn
    ) public moreThanZero(amountDscToBurn) nonReentrant {
        _burnDsc(msg.sender, msg.sender, amountDscToBurn);
        _revertIfHealthFactorIsBroken(msg.sender); //This should never be needed actually
    }

    function liquidate(
        address user,
        address collateral,
        uint256 debtToCover
    ) external moreThanZero(debtToCover) nonReentrant {
        // Check user health factor
        uint256 userStartingHealthFactor = _healthFactor(user);
        if (userStartingHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOkay();
        }
        // We want to burn their DSC "debt"
        // And take their collateral
        // Bad user: $140 collateral and $100 DSC
        // Debt to cover=$100
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(
            collateral,
            debtToCover
        );
        // give bonus 10% to them
        uint256 bonuCollateral = (tokenAmountFromDebtCovered *
            LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;

        uint256 totalCollateral = tokenAmountFromDebtCovered + bonuCollateral;
        _redeemCollateral(collateral, totalCollateral, user, msg.sender);
        _burnDsc(user, msg.sender, debtToCover);

        uint256 userEndingHealthFactor = _healthFactor(user);
        if (userEndingHealthFactor <= userStartingHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    // Private and Internal functions

    function _getAccountInformation(
        address user
    )
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = _getAccountCollateralValue(user);
    }

    /**
     * Returns How close to liquidation a user is
     */
    function _healthFactor(address user) private view returns (uint256) {
        (
            uint256 totalDscMinted,
            uint256 collateralValueInUsd
        ) = _getAccountInformation(user);
        // If totalDsxMinted is zero, then the healthfactor is good!
        if (totalDscMinted == 0) {
            return type(uint256).max;
        }
        // if collateralValueInUsd is zero, then the healthfactor is bad
        if (collateralValueInUsd == 0) {
            revert DSCEngine__ZeroCollateral();
        }
        // We only wnat to take into account 50% of the users collateral
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd *
            LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        /// This [PRECISION] multiplier is to avoid floating numbers i.e 50/51 *10000
        //  if 50/51 < 10000 then the health factor is less than one. You dig?
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    function _redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        address from,
        address to
    ) private moreThanZero(amountCollateral) {
        s_collateralsDeposited[from][
            tokenCollateralAddress
        ] -= amountCollateral;
        emit CollateralRedeemed(
            from,
            to,
            amountCollateral,
            tokenCollateralAddress
        );
        bool success = IERC20(tokenCollateralAddress).transfer(
            to,
            amountCollateral
        );
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     * @notice Low level function. Check health factor when you use it
     * @param onBehalfOf address to burn on behalf of
     * @param from address to burn from
     * @param amountDscToBurn amount to be burned
     */
    function _burnDsc(
        address onBehalfOf,
        address from,
        uint256 amountDscToBurn
    ) private moreThanZero(amountDscToBurn) {
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(from, address(this), amountDscToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    // Public and external

    function getTokenAmountFromUsd(
        address token,
        uint256 usdAmountInWei
    ) public view returns (uint256) {
        // Price of token
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();
        return
            (usdAmountInWei * PRECISION) /
            (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function _getAccountCollateralValue(
        address user
    ) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralsDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
    }

    /**
     * @notice Get the Usd value of the @param amount for @param token
     */
    function getUsdValue(
        address token,
        uint256 amount
    ) public view isAllowedToken(token) returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();
        return
            (uint256(price) * ADDITIONAL_FEED_PRECISION * amount) / PRECISION;
    }

    // Visible for testing only

    function getAccountInformation(
        address user
    )
        external
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        (totalDscMinted, collateralValueInUsd) = _getAccountInformation(user);
    }

    function getHealthFactor(
        address user
    ) external view returns (uint256 userHealthFactor) {
        userHealthFactor = _healthFactor(user);
    }
}
