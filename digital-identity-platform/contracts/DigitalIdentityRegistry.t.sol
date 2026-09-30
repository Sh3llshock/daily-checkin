// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// AI-assisted: this test file was generated with Claude Code (Claude Opus 5.5)
// on 2026-09-30. Per the coursebook GenAI rules it must be fully reviewed by
// the team before submission and declared in the report's AI statement.

import "forge-std/Test.sol";
import "./DigitalIdentityRegistry.sol";

/// Unit tests for DigitalIdentityRegistry.
/// All identity values are synthetic placeholders -- no personal data.
contract DigitalIdentityRegistryTest is Test {
    DigitalIdentityRegistry registry;
    address user = address(0x1001);
    address otherUser = address(0x1002);
    address requester = address(0x2001);
    address stranger = address(0xBAD);

    bytes32 constant EMAIL_HASH = keccak256("test-user-1@example.invalid");
    string constant LINK = "https://storage.example.invalid/docs/test-user-1";
    bytes32 FRONT = sha256("test-user-1-front");
    bytes32 BACK = sha256("test-user-1-back");

    function setUp() public {
        registry = new DigitalIdentityRegistry(); // this test contract plays the admin
    }

    function _register() internal {
        vm.prank(user);
        registry.registerUser(EMAIL_HASH, LINK, FRONT, BACK);
    }

    function test_DeployerIsAdmin() public view {
        assertEq(registry.owner(), address(this));
    }

    function test_RegisterStoresReferenceData() public {
        _register();

        assertTrue(registry.isRegistered(user));
        (bytes32 emailHash, string memory link, bytes32 front, bytes32 back, bool registered) =
            registry.getUserRecord(user);
        assertEq(emailHash, EMAIL_HASH);
        assertEq(link, LINK);
        assertEq(front, FRONT);
        assertEq(back, BACK);
        assertTrue(registered);
    }

    function test_RegisterEmitsEvent() public {
        vm.expectEmit(true, false, false, true, address(registry));
        emit DigitalIdentityRegistry.UserRegistered(user, EMAIL_HASH, LINK);
        _register();
    }

    function test_UnregisteredUserHasEmptyRecord() public view {
        assertFalse(registry.isRegistered(stranger));
        (bytes32 emailHash, string memory link, bytes32 front, bytes32 back, bool registered) =
            registry.getUserRecord(stranger);
        assertEq(emailHash, bytes32(0));
        assertEq(bytes(link).length, 0);
        assertEq(front, bytes32(0));
        assertEq(back, bytes32(0));
        assertFalse(registered);
    }

    function test_CannotRegisterTwice() public {
        _register();
        vm.prank(user);
        vm.expectRevert("DigitalIdentityRegistry: already registered");
        registry.registerUser(keccak256("test-user-1-alt@example.invalid"), LINK, FRONT, BACK);
    }

    function test_EmailHashCanOnlyBeUsedOnce() public {
        _register();
        vm.prank(otherUser);
        vm.expectRevert("DigitalIdentityRegistry: email already used");
        registry.registerUser(EMAIL_HASH, "https://storage.example.invalid/docs/test-user-2", FRONT, BACK);
    }

    function test_RejectsEmptyEmailHash() public {
        vm.prank(user);
        vm.expectRevert("DigitalIdentityRegistry: empty email hash");
        registry.registerUser(bytes32(0), LINK, FRONT, BACK);
    }

    function test_RejectsEmptyLink() public {
        vm.prank(user);
        vm.expectRevert("DigitalIdentityRegistry: empty link");
        registry.registerUser(EMAIL_HASH, "", FRONT, BACK);
    }

    function test_RejectsEmptyImageHashes() public {
        vm.prank(user);
        vm.expectRevert("DigitalIdentityRegistry: empty image hash");
        registry.registerUser(EMAIL_HASH, LINK, bytes32(0), BACK);

        vm.prank(user);
        vm.expectRevert("DigitalIdentityRegistry: empty image hash");
        registry.registerUser(EMAIL_HASH, LINK, FRONT, bytes32(0));
    }

    function test_UpdateDocumentReplacesLinkAndHashes() public {
        _register();
        string memory newLink = "https://storage.example.invalid/docs/test-user-1-v2";
        bytes32 newFront = sha256("test-user-1-front-renewed");
        bytes32 newBack = sha256("test-user-1-back-renewed");

        vm.prank(user);
        registry.updateDocument(newLink, newFront, newBack);

        (bytes32 emailHash, string memory link, bytes32 front, bytes32 back, bool registered) =
            registry.getUserRecord(user);
        assertEq(emailHash, EMAIL_HASH); // identity key is unchanged
        assertEq(link, newLink);
        assertEq(front, newFront);
        assertEq(back, newBack);
        assertTrue(registered);
    }

    function test_UpdateDocumentEmitsEvent() public {
        _register();
        string memory newLink = "https://storage.example.invalid/docs/test-user-1-v2";
        bytes32 newFront = sha256("test-user-1-front-renewed");
        bytes32 newBack = sha256("test-user-1-back-renewed");

        vm.expectEmit(true, false, false, true, address(registry));
        emit DigitalIdentityRegistry.DocumentUpdated(user, newLink);
        vm.prank(user);
        registry.updateDocument(newLink, newFront, newBack);
    }

    function test_UpdateDocumentRequiresRegistration() public {
        vm.prank(stranger);
        vm.expectRevert("DigitalIdentityRegistry: not registered");
        registry.updateDocument(LINK, FRONT, BACK);
    }

    function test_UpdateDocumentRejectsEmptyValues() public {
        _register();

        vm.prank(user);
        vm.expectRevert("DigitalIdentityRegistry: empty link");
        registry.updateDocument("", FRONT, BACK);

        vm.prank(user);
        vm.expectRevert("DigitalIdentityRegistry: empty image hash");
        registry.updateDocument(LINK, bytes32(0), BACK);
    }

    function test_AdminWhitelistsAndRemovesRequester() public {
        assertFalse(registry.isApprovedRequester(requester));

        vm.expectEmit(true, false, false, true, address(registry));
        emit DigitalIdentityRegistry.RequesterStatusChanged(requester, true);
        registry.setRequesterStatus(requester, true);
        assertTrue(registry.isApprovedRequester(requester));

        registry.setRequesterStatus(requester, false);
        assertFalse(registry.isApprovedRequester(requester));
    }

    function test_OnlyAdminCanWhitelist() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        registry.setRequesterStatus(stranger, true);
    }
}
