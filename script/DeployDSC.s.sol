// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {DecentralisedStableCoin} from "../src/DecentralisedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";

contract DeployDSC is Script {
    DecentralisedStableCoin public counter;
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function setUp() public {}

    function run()
        external
        returns (
            DecentralisedStableCoin decentralisedStableCoin,
            DSCEngine dSCEngine,
            HelperConfig helperConfig
        )
    {
        helperConfig = new HelperConfig();
        (
            address wethUsdPriceFeed,
            address wbtcUsdPriceFeed,
            address weth,
            address wbtc, // uint256 deployerKey

        ) = helperConfig.activeNetworkConfig();
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];
        tokenAddresses = [weth, wbtc];

        console.logAddress(weth);
        vm.startBroadcast();
        decentralisedStableCoin = new DecentralisedStableCoin();
        dSCEngine = new DSCEngine(
            tokenAddresses,
            priceFeedAddresses,
            address(decentralisedStableCoin)
        );
        // Transfer ownership to the engine
        decentralisedStableCoin.transferOwnership(address(dSCEngine));
        vm.stopBroadcast();
    }
}
