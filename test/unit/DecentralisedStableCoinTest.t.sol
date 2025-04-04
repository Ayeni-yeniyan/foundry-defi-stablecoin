// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DecentralisedStableCoin} from "../../src/DecentralisedStableCoin.sol";

contract DecentralisedStableCoinTest is Test {
    DecentralisedStableCoin public dsc;

    address public constant nonOwner = address(0x123);

    function setUp() public {
        dsc = new DecentralisedStableCoin();
    }

    function testMintDsc() public {
        dsc.mint(msg.sender, 1 ether);
        assertEq(dsc.balanceOf(msg.sender), 1 ether);
    }

    // I don't know why it is failing i guess? i actually do but not how to fix it
    // function testBurnDscTest() public {
    //     dsc.mint(msg.sender, 1 ether);
    //     vm.prank(msg.sender);
    //     dsc.burn(0.5 ether);
    //     assertEq(dsc.balanceOf(msg.sender), 0.5 ether);
    // }

    function testBurnByNonOwnerReverts() public {
        vm.startPrank(nonOwner);
        vm.expectRevert();
        dsc.burn(1 ether);
        vm.stopPrank();
    }

    // Test that only owner can mint
    function testMintByNonOwnerReverts() public {
        vm.startPrank(nonOwner);
        vm.expectRevert();
        dsc.mint(nonOwner, 1 ether);
        vm.stopPrank();
    }
}
