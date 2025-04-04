// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DecentralisedStableCoin} from "../../src/DecentralisedStableCoin.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "@chainlink/src/v0.8/tests/MockV3Aggregator.sol";

contract DSCEngineTest is Test {
    DecentralisedStableCoin public dsc;
    DeployDSC public deployDSC;
    DSCEngine public dSCEngine;
    HelperConfig public helperConfig;
    address public weth;
    address public ethUsdPriceFeed;
    address public wbtc;
    address public btcUsdPriceFeed;
    address USER = makeAddr("USER");
    address LIQUIDATOR = makeAddr("LIQUIDATOR");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 public constant DSC_MINT_AMOUNT = 5000 ether; // $5000 worth of DSC
    // Events
    event CollateralDeposited(
        address indexed user,
        address indexed token,
        uint256 indexed amount
    );

    function setUp() public {
        deployDSC = new DeployDSC();
        (dsc, dSCEngine, helperConfig) = deployDSC.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc, ) = helperConfig
            .activeNetworkConfig();
        vm.startPrank(address(deployDSC));
        ERC20Mock(weth).transfer(USER, STARTING_ERC20_BALANCE);
        ERC20Mock(weth).transfer(LIQUIDATOR, STARTING_ERC20_BALANCE);
        vm.stopPrank();
    }

    ////////////////////////
    // Contructor Tests ////
    ////////////////////////
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testIfTokenLengthDoesntMatchPriceFeeds() public {
        // Arrange
        tokenAddresses.push(weth);
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        // Act  // Assert
        vm.expectRevert(
            DSCEngine
                .DSCEngine__TokenAddressesAndPricefeedAddressesNotEqual
                .selector
        );
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    function testRevertsIfDscAddressIsZero() public {
        tokenAddresses.push(weth);
        tokenAddresses.push(wbtc);

        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(
            DSCEngine.DSCEngine__DscAddressCannotBeZeroAddress.selector
        );
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(0));
    }

    ///////////////////
    // Price Tests ////
    ///////////////////
    function testGetUsdValue() public view {
        // Act
        uint256 ethAmount = 15e18;
        // 15e18 * 2000/ETH=30,000e18
        uint256 expectedUsd = 30000e18;
        // Arrange
        uint256 calculatedUsd = dSCEngine.getUsdValue(weth, ethAmount);
        // Assert
        assertEq(expectedUsd, calculatedUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        // Act
        uint256 usdAmount = 100 ether;
        // 15e18 * 2000/ETH=30,000e18
        uint256 expectedWeth = 0.05 ether;
        // Arrange
        uint256 calculatedWeth = dSCEngine.getTokenAmountFromUsd(
            weth,
            usdAmount
        );
        // Assert
        assertEq(expectedWeth, calculatedWeth);
    }

    //////////////////////////
    // Deposit collateral ////
    //////////////////////////
    function testRevertIfCollateralZero() public {
        // Arrange
        vm.prank(USER);
        ERC20Mock(weth).approve(address(dSCEngine), AMOUNT_COLLATERAL);
        // Act  // Assert
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dSCEngine.depositCollateral(weth, 0);
    }

    function testRevertIfCollateralUnapproved() public {
        // Arrange
        ERC20Mock unApprovedErc20 = new ERC20Mock();
        vm.startPrank(USER);
        // Act  // Assert
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressNotAllowed.selector);
        dSCEngine.depositCollateral(
            address(unApprovedErc20),
            AMOUNT_COLLATERAL
        );

        vm.stopPrank();
    }

    function testCollateralDepositedWhenAboveZeroAndEmitEvent() public {
        // Arrange
        uint256 collateralAmount = AMOUNT_COLLATERAL;
        // Act  // Assert

        vm.prank(USER);
        ERC20Mock(weth).approve(address(dSCEngine), AMOUNT_COLLATERAL);

        vm.expectEmit(true, true, true, false, address(dSCEngine));
        emit CollateralDeposited(USER, weth, collateralAmount);

        vm.prank(USER);
        dSCEngine.depositCollateral(weth, collateralAmount);
    }

    function testCanDepositCollateralAndGetccountInfo()
        public
        depositedCollateral
    {
        // Arrange
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dSCEngine
            .getAccountInformation(USER);
        uint256 expectedTotalMinted = 0;
        uint256 expectedDepositedCollateral = dSCEngine.getTokenAmountFromUsd(
            weth,
            collateralValueInUsd
        );
        uint256 expectedCollateralValueInUsd = dSCEngine.getUsdValue(
            weth,
            10 ether
        );
        // Act
        // Assert
        // assert the total minted dsc is 0
        assertEq(expectedTotalMinted, totalDscMinted);
        // assert the collateral value deposited is equal to the amount of collateral
        assertEq(AMOUNT_COLLATERAL, expectedDepositedCollateral);
        // assert the collateral value in usd is equal to the amount of collateral
        assertEq(collateralValueInUsd, expectedCollateralValueInUsd);
    }

    /////////////////////
    // Mint DSC Tests  //
    /////////////////////

    function testMintDsc() public depositedCollateral {
        // Arrange
        vm.startPrank(USER);
        uint256 amountToMint = 100 ether; // $100 worth of DSC
        dSCEngine.mintDsc(amountToMint);
        vm.stopPrank();

        (uint256 totalDscMinted, ) = dSCEngine.getAccountInformation(USER);
        assertEq(totalDscMinted, amountToMint);
        assertEq(dsc.balanceOf(USER), amountToMint);
    }

    function testRevertsIfMintAmountBreaksHealthFactor()
        public
        depositedCollateral
    {
        uint256 amountToMint = 10001 ether; // Try to mint $10,001 DSC
        // ETH Price: $2000, Deposited: 10 ETH = $20,000
        // With 50% liquidation threshold, can mint maximum $10,000 DSC

        uint256 expectedHealthFactor = ((((20000 ether * 5) / 10) * 1e18) /
            amountToMint);
        vm.startPrank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__BreaksHealthFactor.selector,
                expectedHealthFactor
            )
        );
        dSCEngine.mintDsc(amountToMint);
        vm.stopPrank();
    }

    //////////////////////////////
    // Deposit and Mint Tests   //
    //////////////////////////////
    function testDepositCollateralAndMintDsc() public {
        vm.startPrank(USER);
        uint256 amountToMint = 5000 ether; // $5000 worth of DSC
        ERC20Mock(weth).approve(address(dSCEngine), AMOUNT_COLLATERAL);
        dSCEngine.depositCollateralAndMintDsc(
            address(weth),
            AMOUNT_COLLATERAL,
            amountToMint
        );
        vm.stopPrank();

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dSCEngine
            .getAccountInformation(USER);
        uint256 expectedCollateralValue = dSCEngine.getUsdValue(
            address(weth),
            AMOUNT_COLLATERAL
        );

        assertEq(totalDscMinted, amountToMint);
        assertEq(collateralValueInUsd, expectedCollateralValue);
        assertEq(dsc.balanceOf(USER), amountToMint);
    }

    //////////////////////////
    // Redeem Collateral Tests //
    //////////////////////////
    function testRedeemCollateral() public depositedCollateralAndMintedDsc {
        uint256 redeemedAmount = 5 ether;
        vm.startPrank(USER);
        dSCEngine.redeemCollateral(address(weth), redeemedAmount);
        vm.stopPrank();

        uint256 userBalance = ERC20Mock(weth).balanceOf(USER);
        assertEq(
            userBalance,
            STARTING_ERC20_BALANCE - AMOUNT_COLLATERAL + redeemedAmount
        );
    }

    function testRevertsIfRedeemCollateralBreaksHealthFactor()
        public
        depositedCollateralAndMintedDsc
    {
        vm.startPrank(USER);
        uint256 amountToRedem = 10 ether;
        // Try to redeem more than allowed
        vm.expectRevert();
        dSCEngine.redeemCollateral(address(weth), amountToRedem);
        vm.stopPrank();
    }

    /////////////////////
    // Burn DSC Tests  //
    /////////////////////
    function testBurnDsc() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        dsc.approve(address(dSCEngine), DSC_MINT_AMOUNT);
        dSCEngine.burnDsc(DSC_MINT_AMOUNT);
        vm.stopPrank();

        assertEq(dsc.balanceOf(USER), 0);
        (uint256 totalDscMinted, ) = dSCEngine.getAccountInformation(USER);
        assertEq(totalDscMinted, 0);
    }

    /////////////////////////////
    // Redeem and Burn Tests   //
    /////////////////////////////
    function testRedeemCollateralAndBurnDsc()
        public
        depositedCollateralAndMintedDsc
    {
        vm.startPrank(USER);
        dsc.approve(address(dSCEngine), 50 ether);
        dSCEngine.redeemCollateralAndBurnDsc(address(weth), 5 ether, 50 ether);
        vm.stopPrank();

        (uint256 totalDscMinted, ) = dSCEngine.getAccountInformation(USER);
        assertEq(totalDscMinted, DSC_MINT_AMOUNT - 50 ether);
        assertEq(
            ERC20Mock(weth).balanceOf(USER),
            STARTING_ERC20_BALANCE - AMOUNT_COLLATERAL + 5 ether
        );
    }

    function testRevertsIfRedeemAndBurnBreaksHealthFactor()
        public
        depositedCollateralAndMintedDsc
    {
        vm.startPrank(USER);
        uint256 amountToRedem = 10 ether;
        // Try to redeem more than allowed
        vm.expectRevert();
        dSCEngine.redeemCollateralAndBurnDsc(
            address(weth),
            amountToRedem,
            DSC_MINT_AMOUNT
        );
        vm.stopPrank();
    }

    ////////////////////
    // Liquidation Tests //
    ////////////////////
    function testLiquidation() public depositedCollateralAndMintedDsc {
        // Drop ETH price to put USER below health factor
        int256 newEthPrice = 900e8; // $1000 per ETH
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(newEthPrice);
        uint256 amountDscToMint = 100 ether;
        uint256 newCollateralValue = dSCEngine.getUsdValue(
            address(weth),
            AMOUNT_COLLATERAL
        );
        uint256 newHealthFactor = dSCEngine.getHealthFactor(USER);
        console.log(
            "New newCollateralValue after price drop: ",
            newCollateralValue
        );
        console.log("New Health Factor after price drop: ", newHealthFactor);

        // Liquidator setup
        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(dSCEngine), AMOUNT_COLLATERAL);
        dSCEngine.depositCollateralAndMintDsc(
            address(weth),
            AMOUNT_COLLATERAL,
            amountDscToMint
        );
        dsc.approve(address(dSCEngine), amountDscToMint);

        // Liquidate half of USER's debt
        uint256 debtToCover = 45 ether;
        dSCEngine.liquidate(USER, address(weth), debtToCover);
        vm.stopPrank();

        // Check results - liquidator should have received collateral with bonus
        uint256 tokenAmountFromDebtCovered = 0.05 ether; // 50 / 1000 = 0.05 ETH
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * 10) / 100; // 10% bonus
        uint256 totalCollateralLiquidated = tokenAmountFromDebtCovered +
            bonusCollateral;

        (uint256 userDscMinted, ) = dSCEngine.getAccountInformation(USER);
        assertEq(userDscMinted, DSC_MINT_AMOUNT - debtToCover);
        assertEq(
            ERC20Mock(weth).balanceOf(LIQUIDATOR),
            STARTING_ERC20_BALANCE -
                AMOUNT_COLLATERAL +
                totalCollateralLiquidated
        );
    }

    function testRevertsIfHealthFactorOk()
        public
        depositedCollateralAndMintedDsc
    {
        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(dSCEngine), AMOUNT_COLLATERAL);
        dSCEngine.depositCollateralAndMintDsc(
            address(weth),
            AMOUNT_COLLATERAL,
            5000 ether
        );
        dsc.approve(address(dSCEngine), 5000 ether);

        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOkay.selector);
        dSCEngine.liquidate(USER, address(weth), 50 ether);
        vm.stopPrank();
    }

    ///////////////////
    // Test Modifiers //
    ///////////////////
    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dSCEngine), AMOUNT_COLLATERAL);
        dSCEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }
    modifier depositedCollateralAndMintedDsc() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dSCEngine), AMOUNT_COLLATERAL);
        dSCEngine.depositCollateralAndMintDsc(
            address(weth),
            AMOUNT_COLLATERAL,
            DSC_MINT_AMOUNT
        );
        vm.stopPrank();
        _;
    }
}

// //////// Starter test function
//   function test() public {
//         // Arrange

//         // Act

//         // Assert
//     }
//
