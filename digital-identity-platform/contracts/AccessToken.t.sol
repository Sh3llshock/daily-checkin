// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// AI-assisted: this test file was generated with Claude Code (Claude Opus 5.5)
// on 2026-09-30 and updated for TASKS A1-A4 on 2026-10-01. Per the coursebook
// GenAI rules it must be fully reviewed by the team before submission and
// declared in the report's AI statement.

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

    // setUp already wired `token`, so the setMinter tests below use a fresh,
    // unwired token wherever they need the first call to succeed.

    function test_SetMinterEmitsEvent() public {
        AccessToken fresh = new AccessToken();
        vm.expectEmit(true, false, false, false, address(fresh));
        emit AccessToken.MinterUpdated(minter);
        fresh.setMinter(minter);
        assertEq(fresh.minter(), minter);
    }

    function test_MinterCanOnlyBeSetOnce() public {
        // Not even the owner can re-point minting, e.g. at their own wallet.
        vm.expectRevert("AccessToken: minter already set");
        token.setMinter(address(this));
        assertEq(token.minter(), minter);

        vm.prank(minter);
        token.mintReward(user, ONE);
        assertEq(token.balanceOf(user), ONE);
    }

    function test_OnlyAdminCanSetMinter() public {
        AccessToken fresh = new AccessToken();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        fresh.setMinter(stranger);
    }

    function test_RejectsZeroMinter() public {
        AccessToken fresh = new AccessToken();
        vm.expectRevert("AccessToken: zero minter");
        fresh.setMinter(address(0));
    }
}
