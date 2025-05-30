// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DecentralisedStableCoin} from "../../src/DecentralisedStableCoin.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";

contract InvariantsTest is StdInvariant, Test {
    DecentralisedStableCoin public dsc;
    DeployDSC public deployDSC;
    DSCEngine public dSCEngine;
    address public weth;
    address public wbtc;
    HelperConfig public helperConfig;
    Handler public handler;

    function setUp() external {
        deployDSC = new DeployDSC();
        (dsc, dSCEngine, helperConfig) = deployDSC.run();
        (, , weth, wbtc, ) = helperConfig.activeNetworkConfig();
        handler = new Handler(dsc, dSCEngine);
        targetContract(address(handler));
        // targetContract(address(dSCEngine));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dSCEngine));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dSCEngine));
        uint256 totalValueInUSD = dSCEngine.getUsdValue(
            weth,
            totalWethDeposited
        ) + dSCEngine.getUsdValue(wbtc, totalWbtcDeposited);
        console.log(
            "Total Supply: %s, Total Value in USD: %s",
            totalSupply,
            totalValueInUSD
        );
        console.log("totalMintCalled by handler", handler.totalMintCalled());
        assert(totalValueInUSD >= totalSupply);
    }

    function invariant_gettersSHouldNeverRevert() public view {
        // Getters should never revert
        dSCEngine.getAccountInformation(msg.sender);
        dSCEngine.getUserCollateralForToken(msg.sender, weth);
        dSCEngine.getCollateralTokens();
        dSCEngine.getHealthFactor(msg.sender);
        dSCEngine.getCollateralTokens();
    }
}
