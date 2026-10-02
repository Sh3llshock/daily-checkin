// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../contracts/AccessToken.sol";

contract AccessTokenTest is Test {
    AccessToken token;
    address admin;
    address minter;
    address alice;
    address bob;

    function setUp() public {
        admin = address(this);
        minter = makeAddr("minter");
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        token = new AccessToken();
        token.setMinter(minter);
    }

    // --- Deployment ---------------------------------------------------

    function test_Metadata() public view {
        assertEq(token.name(), "Access Token");
        assertEq(token.symbol(), "ACT");
        assertEq(token.decimals(), 18);
        assertEq(token.owner(), admin);
        assertEq(token.totalSupply(), 0);
    }

    // --- Minter -------------------------------------------------------

    function test_OwnerSetsMinter() public {
        AccessToken fresh = new AccessToken();
        fresh.setMinter(minter);
        assertEq(fresh.minter(), minter);
    }

    function test_RevertsWhenMinterSetTwice() public {
        // otherwise the owner could make their own wallet the minter
        vm.expectRevert("Minter already set");
        token.setMinter(admin);
        assertEq(token.minter(), minter);
    }

    function test_RevertsWhenNonOwnerSetsMinter() public {
        vm.prank(alice);
        vm.expectRevert("Not the owner");
        token.setMinter(alice);
    }

    function test_RevertsOnZeroMinter() public {
        AccessToken fresh = new AccessToken();
        vm.expectRevert("Invalid minter");
        fresh.setMinter(address(0));
    }

    function test_MinterCanMint() public {
        vm.expectEmit(true, true, true, true, address(token));
        emit AccessToken.Transfer(address(0), alice, 10 ether);

        vm.prank(minter);
        token.mint(alice, 10 ether);

        assertEq(token.balanceOf(alice), 10 ether);
        assertEq(token.totalSupply(), 10 ether);
    }

    function test_RevertsWhenNonMinterMints() public {
        vm.prank(alice);
        vm.expectRevert("Not the minter");
        token.mint(alice, 1 ether);

        // not even the owner can mint directly
        vm.expectRevert("Not the minter");
        token.mint(admin, 1 ether);
    }

    // --- ERC-20 -------------------------------------------------------

    function test_Transfer() public {
        vm.prank(minter);
        token.mint(alice, 10 ether);

        vm.prank(alice);
        token.transfer(bob, 4 ether);

        assertEq(token.balanceOf(alice), 6 ether);
        assertEq(token.balanceOf(bob), 4 ether);
    }

    function test_RevertsTransferWithoutBalance() public {
        vm.prank(alice);
        vm.expectRevert("Insufficient balance");
        token.transfer(bob, 1 ether);
    }

    function test_ApproveAndTransferFrom() public {
        vm.prank(minter);
        token.mint(alice, 10 ether);

        vm.prank(alice);
        token.approve(bob, 5 ether);
        assertEq(token.allowance(alice, bob), 5 ether);

        vm.prank(bob);
        token.transferFrom(alice, bob, 3 ether);

        assertEq(token.balanceOf(bob), 3 ether);
        assertEq(token.allowance(alice, bob), 2 ether);
    }

    function test_RevertsTransferFromOverAllowance() public {
        vm.prank(minter);
        token.mint(alice, 10 ether);

        vm.prank(alice);
        token.approve(bob, 1 ether);

        vm.prank(bob);
        vm.expectRevert("Insufficient allowance");
        token.transferFrom(alice, bob, 2 ether);
    }
}
