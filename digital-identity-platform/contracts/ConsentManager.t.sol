// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "./ConsentManager.sol";

/// Unit tests for ConsentManager, wired to a real registry and token.
/// All identity values are synthetic placeholders -- no personal data.
contract ConsentManagerTest is Test {
    DigitalIdentityRegistry registry;
    AccessToken token;
    ConsentManager consent;

    address user = address(0x1001);
    address requester = address(0x2001);
    address otherRequester = address(0x2002);
    address stranger = address(0xBAD);
    uint256 constant REWARD = 10 * 1e18;

    function setUp() public {
        // this test contract plays the admin
        registry = new DigitalIdentityRegistry();
        token = new AccessToken();
        consent = new ConsentManager(registry, token);
        token.setMinter(address(consent));

        registry.setRequesterStatus(requester, true);
        registry.setRequesterStatus(otherRequester, true);

        bytes32 emailHash = keccak256("test-user-1@example.invalid");
        bytes32 front = sha256("test-user-1-front");
        bytes32 back = sha256("test-user-1-back");
        vm.prank(user);
        registry.registerUser(emailHash, "https://storage.example.invalid/docs/test-user-1", front, back);
    }

    function _grant(address to, ConsentManager.Scope scope, uint256 durationDays) internal {
        vm.prank(user);
        consent.setConsent(to, scope, durationDays);
    }

    function _revoke(address from) internal {
        vm.prank(user);
        consent.revokeConsent(from);
    }

    // --- Granting ---

    function test_SetConsentStoresScopedTimeLimitedRecord() public {
        _grant(requester, ConsentManager.Scope.BOTH, 30);

        (ConsentManager.Scope scope, uint256 grantedAt, uint256 expiresAt, bool revoked, bool exists) =
            consent.getConsent(user, requester);
        assertEq(uint8(scope), uint8(ConsentManager.Scope.BOTH));
        assertEq(grantedAt, block.timestamp);
        assertEq(expiresAt, block.timestamp + 30 days);
        assertFalse(revoked);
        assertTrue(exists);
        assertTrue(consent.isConsentValid(user, requester));
    }

    function test_SetConsentEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(consent));
        emit ConsentManager.ConsentGranted(user, requester, ConsentManager.Scope.FRONT_ONLY, block.timestamp + 7 days);
        _grant(requester, ConsentManager.Scope.FRONT_ONLY, 7);
    }

    function test_ConsentIsPerRequester() public {
        _grant(requester, ConsentManager.Scope.BOTH, 30);
        assertTrue(consent.isConsentValid(user, requester));
        assertFalse(consent.isConsentValid(user, otherRequester));
    }

    function test_RegrantUpdatesScopeAndExpiry() public {
        _grant(requester, ConsentManager.Scope.BOTH, 30);
        _grant(requester, ConsentManager.Scope.BACK_ONLY, 90);

        (ConsentManager.Scope scope, , uint256 expiresAt, , ) = consent.getConsent(user, requester);
        assertEq(uint8(scope), uint8(ConsentManager.Scope.BACK_ONLY));
        assertEq(expiresAt, block.timestamp + 90 days);
    }

    function test_RejectsUnregisteredUser() public {
        vm.prank(stranger);
        vm.expectRevert("ConsentManager: user not registered");
        consent.setConsent(requester, ConsentManager.Scope.BOTH, 30);
    }

    function test_RejectsNonWhitelistedRequester() public {
        vm.prank(user);
        vm.expectRevert("ConsentManager: requester not whitelisted");
        consent.setConsent(stranger, ConsentManager.Scope.BOTH, 30);
    }

    function test_RejectsRequesterRemovedFromWhitelist() public {
        registry.setRequesterStatus(requester, false);
        vm.prank(user);
        vm.expectRevert("ConsentManager: requester not whitelisted");
        consent.setConsent(requester, ConsentManager.Scope.BOTH, 30);
    }

    function test_AcceptsDurationBounds() public {
        _grant(requester, ConsentManager.Scope.BOTH, consent.MIN_DURATION_DAYS());
        _grant(otherRequester, ConsentManager.Scope.BOTH, consent.MAX_DURATION_DAYS());
        assertTrue(consent.isConsentValid(user, requester));
        assertTrue(consent.isConsentValid(user, otherRequester));
    }

    function test_RejectsDurationOutOfRange() public {
        vm.prank(user);
        vm.expectRevert("ConsentManager: duration out of range");
        consent.setConsent(requester, ConsentManager.Scope.BOTH, 0);

        vm.prank(user);
        vm.expectRevert("ConsentManager: duration out of range");
        consent.setConsent(requester, ConsentManager.Scope.BOTH, 366);
    }

    // --- Expiry ---

    function test_ConsentValidUntilExpiryInclusive() public {
        _grant(requester, ConsentManager.Scope.BOTH, 30);
        uint256 expiresAt = block.timestamp + 30 days;

        vm.warp(expiresAt);
        assertTrue(consent.isConsentValid(user, requester));

        vm.warp(expiresAt + 1);
        assertFalse(consent.isConsentValid(user, requester));
    }

    function testFuzz_ExpiryMatchesDuration(uint256 durationDays) public {
        durationDays = bound(durationDays, 1, 365);
        _grant(requester, ConsentManager.Scope.BOTH, durationDays);
        uint256 expiresAt = block.timestamp + durationDays * 1 days;

        (, , uint256 storedExpiry, , ) = consent.getConsent(user, requester);
        assertEq(storedExpiry, expiresAt);

        vm.warp(expiresAt + 1);
        assertFalse(consent.isConsentValid(user, requester));
    }

    function test_ExpiredConsentCanBeRenewed() public {
        _grant(requester, ConsentManager.Scope.BOTH, 1);
        vm.warp(block.timestamp + 2 days);
        assertFalse(consent.isConsentValid(user, requester));

        _grant(requester, ConsentManager.Scope.BOTH, 30);
        assertTrue(consent.isConsentValid(user, requester));
    }

    // --- Revoking ---

    function test_UserCanRevoke() public {
        _grant(requester, ConsentManager.Scope.BOTH, 30);
        _revoke(requester);

        (, , , bool revoked, bool exists) = consent.getConsent(user, requester);
        assertTrue(revoked);
        assertTrue(exists);
        assertFalse(consent.isConsentValid(user, requester));
    }

    function test_RevokeEmitsEvent() public {
        _grant(requester, ConsentManager.Scope.BOTH, 30);
        vm.expectEmit(true, true, false, false, address(consent));
        emit ConsentManager.ConsentRevoked(user, requester);
        _revoke(requester);
    }

    function test_CannotRevokeMissingConsent() public {
        vm.prank(user);
        vm.expectRevert("ConsentManager: no such consent");
        consent.revokeConsent(requester);
    }

    function test_CannotRevokeTwice() public {
        _grant(requester, ConsentManager.Scope.BOTH, 30);
        _revoke(requester);
        vm.prank(user);
        vm.expectRevert("ConsentManager: already revoked");
        consent.revokeConsent(requester);
    }

    function test_NobodyElseCanRevokeUsersConsent() public {
        _grant(requester, ConsentManager.Scope.BOTH, 30);

        // revokeConsent only ever touches the caller's own record, so neither
        // the requester nor the admin can revoke on the user's behalf.
        vm.prank(requester);
        vm.expectRevert("ConsentManager: no such consent");
        consent.revokeConsent(requester);

        vm.expectRevert("ConsentManager: no such consent");
        consent.revokeConsent(requester);

        assertTrue(consent.isConsentValid(user, requester));
    }

    function test_RegrantAfterRevokeRestoresConsent() public {
        _grant(requester, ConsentManager.Scope.BOTH, 30);
        _revoke(requester);
        _grant(requester, ConsentManager.Scope.BOTH, 30);

        (, , , bool revoked, ) = consent.getConsent(user, requester);
        assertFalse(revoked);
        assertTrue(consent.isConsentValid(user, requester));
    }

    // --- ACT rewards ---

    function test_FirstGrantMintsReward() public {
        _grant(requester, ConsentManager.Scope.BOTH, 30);
        assertEq(token.balanceOf(user), REWARD);
    }

    function test_RegrantDoesNotMintAgain() public {
        _grant(requester, ConsentManager.Scope.BOTH, 30);
        _grant(requester, ConsentManager.Scope.BOTH, 60);
        assertEq(token.balanceOf(user), REWARD);
    }

    function test_RevokeThenRegrantDoesNotMintAgain() public {
        for (uint256 i = 0; i < 5; i++) {
            _grant(requester, ConsentManager.Scope.BOTH, 30);
            _revoke(requester);
        }
        assertEq(token.balanceOf(user), REWARD);
    }

    function test_EachNewRequesterIsRewardedOnce() public {
        _grant(requester, ConsentManager.Scope.BOTH, 30);
        _grant(otherRequester, ConsentManager.Scope.BOTH, 30);
        assertEq(token.balanceOf(user), 2 * REWARD);
    }

    function test_RewardAmountChangeAppliesToLaterGrants() public {
        vm.expectEmit(false, false, false, true, address(consent));
        emit ConsentManager.RewardAmountUpdated(5 * 1e18);
        consent.setRewardAmount(5 * 1e18);

        _grant(requester, ConsentManager.Scope.BOTH, 30);
        assertEq(token.balanceOf(user), 5 * 1e18);
    }

    function test_OnlyAdminCanSetRewardAmount() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        consent.setRewardAmount(1000 * 1e18);
    }
}
