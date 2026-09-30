// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "./AccessToken.sol";

/// Unit tests for AccessToken (ACT).
contract AccessTokenTest is Test {
    AccessToken token;
    address minter = address(0xC0DE); // stands in for ConsentManager
    address user = address(0x1001);
    address stranger = address(0xBAD);
    uint256 constant ONE = 1e18;

    function setUp() public {
        token = new AccessToken(); // this test contract plays the admin
        token.setMinter(minter);
    }

    function test_Metadata() public view {
        assertEq(token.name(), "Access Token");
        assertEq(token.symbol(), "ACT");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), 0);
        assertEq(token.owner(), address(this));
    }

    function test_NoMinterByDefault() public {
        AccessToken fresh = new AccessToken();
        assertEq(fresh.minter(), address(0));

        vm.expectRevert("AccessToken: caller is not minter");
        fresh.mintReward(user, ONE);
    }

    function test_MinterCanMintReward() public {
        vm.prank(minter);
        token.mintReward(user, 10 * ONE);
        assertEq(token.balanceOf(user), 10 * ONE);
        assertEq(token.totalSupply(), 10 * ONE);
    }

    function test_StrangerCannotMint() public {
        vm.prank(stranger);
        vm.expectRevert("AccessToken: caller is not minter");
        token.mintReward(stranger, ONE);
    }

    function test_AdminCannotMintDirectly() public {
        vm.expectRevert("AccessToken: caller is not minter");
        token.mintReward(address(this), ONE);
    }

    function test_SetMinterEmitsEvent() public {
        address newMinter = address(0xC0DE2);
        vm.expectEmit(true, false, false, false, address(token));
        emit AccessToken.MinterUpdated(newMinter);
        token.setMinter(newMinter);
        assertEq(token.minter(), newMinter);
    }

    function test_RepointingMinterRevokesOldMinter() public {
        address newMinter = address(0xC0DE2);
        token.setMinter(newMinter);

        vm.prank(minter);
        vm.expectRevert("AccessToken: caller is not minter");
        token.mintReward(user, ONE);

        vm.prank(newMinter);
        token.mintReward(user, ONE);
        assertEq(token.balanceOf(user), ONE);
    }

    function test_OnlyAdminCanSetMinter() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        token.setMinter(stranger);
    }

    function test_RejectsZeroMinter() public {
        vm.expectRevert("AccessToken: zero minter");
        token.setMinter(address(0));
    }
}
