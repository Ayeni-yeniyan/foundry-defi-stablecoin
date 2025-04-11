// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DecentralisedStableCoin} from "../../src/DecentralisedStableCoin.sol";

contract DecentralisedStableCoinTest is Test {
    DecentralisedStableCoin public dsc;

    address public constant nonOwner = address(0x123);
    address public user = address(0x456);
    uint256 public constant AMOUNT = 1 ether;

    function setUp() public {
        dsc = new DecentralisedStableCoin();
    }

    // MINT TESTS
    function testMintDsc() public {
        dsc.mint(msg.sender, AMOUNT);
        assertEq(dsc.balanceOf(msg.sender), AMOUNT);
    }

    function testMintByNonOwnerReverts() public {
        vm.startPrank(nonOwner);
        vm.expectRevert();
        dsc.mint(nonOwner, AMOUNT);
        vm.stopPrank();
    }

    function testMintToZeroAddressReverts() public {
        vm.expectRevert(
            DecentralisedStableCoin
                .DecentralisedStableCoin__MustNotBeZeroAddress
                .selector
        );
        dsc.mint(address(0), AMOUNT);
    }

    function testMintZeroAmountReverts() public {
        vm.expectRevert(
            DecentralisedStableCoin
                .DecentralisedStableCoin__MustBeMoreThanZero
                .selector
        );
        dsc.mint(user, 0);
    }

    // BURN TESTS
    function testBurnDsc() public {
        dsc.mint(address(this), AMOUNT);
        dsc.burn(AMOUNT / 2);
        assertEq(dsc.balanceOf(address(this)), AMOUNT / 2);
    }

    function testBurnMoreThanBalanceReverts() public {
        dsc.mint(address(this), AMOUNT);
        vm.expectRevert(
            DecentralisedStableCoin
                .DecentralisedStableCoin__BurnAmountExceedsBalance
                .selector
        );
        dsc.burn(AMOUNT * 2);
    }

    function testBurnZeroAmountReverts() public {
        vm.expectRevert(
            DecentralisedStableCoin
                .DecentralisedStableCoin__MustBeMoreThanZero
                .selector
        );
        dsc.burn(0);
    }

    function testBurnByNonOwnerReverts() public {
        vm.startPrank(nonOwner);
        vm.expectRevert();
        dsc.burn(AMOUNT);
        vm.stopPrank();
    }

    // ERC20 FUNCTIONALITY TESTS
    function testTransfer() public {
        dsc.mint(address(this), AMOUNT);
        bool success = dsc.transfer(user, AMOUNT / 2);
        assertTrue(success);
        assertEq(dsc.balanceOf(user), AMOUNT / 2);
        assertEq(dsc.balanceOf(address(this)), AMOUNT / 2);
    }

    function testApproveAndTransferFrom() public {
        dsc.mint(address(this), AMOUNT);
        dsc.approve(user, AMOUNT / 2);

        vm.prank(user);
        bool success = dsc.transferFrom(address(this), user, AMOUNT / 2);

        assertTrue(success);
        assertEq(dsc.balanceOf(user), AMOUNT / 2);
        assertEq(dsc.balanceOf(address(this)), AMOUNT / 2);
    }

    // TOTAL SUPPLY TESTS
    function testTotalSupplyAfterMintAndBurn() public {
        uint256 initialSupply = dsc.totalSupply();
        dsc.mint(address(this), AMOUNT);
        assertEq(dsc.totalSupply(), initialSupply + AMOUNT);

        dsc.burn(AMOUNT / 2);
        assertEq(dsc.totalSupply(), initialSupply + AMOUNT / 2);
    }
}
