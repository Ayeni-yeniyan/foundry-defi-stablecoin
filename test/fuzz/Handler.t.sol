// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DecentralisedStableCoin} from "../../src/DecentralisedStableCoin.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract Handler is StdInvariant, Test {
    DecentralisedStableCoin public dsc;
    DSCEngine public dSCEngine;
    uint256 public constant MAX_AMOUNT_COLLATERAL = type(uint96).max;
    ERC20Mock public wethMock;
    ERC20Mock public wbtcMock;
    uint256 public totalMintCalled;

    constructor(DecentralisedStableCoin _dsc, DSCEngine _dSCEngine) {
        dsc = _dsc;
        dSCEngine = _dSCEngine;
        address[] memory collateralTokens = dSCEngine.getCollateralTokens();
        wethMock = ERC20Mock(collateralTokens[0]);
        wbtcMock = ERC20Mock(collateralTokens[1]);
    }

    // redeem collateral
    function depositCollateral(
        uint256 collateralSeed,
        uint256 amountCollateral
    ) public {
        uint256 amount = bound(amountCollateral, 1, MAX_AMOUNT_COLLATERAL);
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        vm.startPrank(msg.sender);

        // mint to msg.sender
        collateral.mint(msg.sender, amount);
        // approve dSCEngine to spend
        collateral.approve(address(dSCEngine), amount);
        dSCEngine.depositCollateral(address(collateral), amount);
        vm.stopPrank();
    }

    function redeemCollateral(
        uint256 collateralSeed,
        uint256 amountCollateral
    ) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        // Get user collateral for token
        uint256 maxRedeemableCollateral = dSCEngine.getUserCollateralForToken(
            msg.sender,
            address(collateral)
        );
        uint256 amountToRedeem = bound(
            amountCollateral,
            0,
            maxRedeemableCollateral
        );
        // Calculate health factor
        // uint256 userCollateralForToken = dSCEngine.calculateHealthFactor(
        //     msg.sender,
        //     address(collateral)
        // );
        // (uint256 totalDscMinted, uint256 collateralValueInUsd) = dSCEngine
        //     .getAccountInformation(msg.sender);
        // int256 maxUsdAmountRedeemable = (int256(collateralValueInUsd) / 2) -
        //     int256(totalDscMinted);
        // if (maxUsdAmountRedeemable < 1) {
        //     return;
        // }
        // console.log("userCollateralForToken", userCollateralForToken);
        // amountCollateral = bound(amountCollateral, 0, userCollateralForToken);
        if (amountToRedeem == 0) {
            return;
        }
        vm.startPrank(msg.sender);
        dSCEngine.redeemCollateral(address(collateral), amountToRedeem);
        vm.stopPrank();
    }

    function mintDsc(uint256 amountSeed) public {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dSCEngine
            .getAccountInformation(msg.sender);
        int256 maxDscToMint = (int256(collateralValueInUsd) / 2) -
            int256(totalDscMinted);
        if (maxDscToMint < 1) {
            return;
        }
        uint256 amountToMint = bound(amountSeed, 1, uint256(maxDscToMint));
        vm.startPrank(msg.sender);
        dSCEngine.mintDsc(amountToMint);
        vm.stopPrank();
        totalMintCalled++;
    }

    function _getCollateralFromSeed(
        uint256 collateralSeed
    ) private view returns (ERC20Mock) {
        uint256 seed = collateralSeed % 2;
        if (seed == 0) {
            return wethMock;
        } else {
            return wbtcMock;
        }
    }
}
