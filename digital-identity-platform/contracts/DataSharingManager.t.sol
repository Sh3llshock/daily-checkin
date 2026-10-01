// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// AI-assisted: this test file was generated with Claude Code (Claude Opus 5.5)
// on 2026-09-30 and updated for TASKS A1-A4 on 2026-10-01. Per the coursebook
// GenAI rules it must be fully reviewed by the team before submission and
// declared in the report's AI statement.

import "forge-std/Test.sol";
import "./DataSharingManager.sol";

/// Unit tests for DataSharingManager.requestAccess, with all five contracts
/// deployed and wired the same way as ignition/modules/DigitalIdentityPlatform.ts.
/// All identity values are synthetic placeholders -- no personal data.
contract DataSharingManagerTest is Test {
    DigitalIdentityRegistry registry;
    AccessToken token;
    ConsentManager consent;
    AccessLogger logger;
    DataSharingManager dsm;

    address user = address(0x1001);
    address requester = address(0x2001);
    address otherRequester = address(0x2002);
    address stranger = address(0xBAD);

    string constant LINK = "https://storage.example.invalid/docs/test-user-1";
    bytes32 FRONT = sha256("test-user-1-front");
    bytes32 BACK = sha256("test-user-1-back");

    function setUp() public {
        // this test contract plays the admin
        token = new AccessToken();
        registry = new DigitalIdentityRegistry();
        consent = new ConsentManager(registry, token);
        logger = new AccessLogger();
        dsm = new DataSharingManager(registry, consent, logger);
        token.setMinter(address(consent));
        logger.setDataSharingManager(address(dsm));

        registry.setRequesterStatus(requester, true);
        registry.setRequesterStatus(otherRequester, true);

        bytes32 emailHash = keccak256("test-user-1@example.invalid");
        vm.prank(user);
        registry.registerUser(emailHash, LINK, FRONT, BACK);
    }

    function _grant(ConsentManager.Scope scope, uint256 durationDays) internal {
        vm.prank(user);
        consent.setConsent(requester, scope, durationDays);
    }

    function _request(address from)
        internal
        returns (bool granted, string memory link, bytes32 front, bytes32 back)
    {
        vm.prank(from);
        return dsm.requestAccess(user);
    }

    function _lastLog() internal view returns (AccessLogger.LogEntry memory) {
        AccessLogger.LogEntry[] memory entries = logger.getLogs(user);
        return entries[entries.length - 1];
    }

    function _assertDenied(address from, AccessLogger.Reason expectedReason) internal {
        (bool granted, string memory link, bytes32 front, bytes32 back) = _request(from);
        assertFalse(granted);
        assertEq(bytes(link).length, 0);
        assertEq(front, bytes32(0));
        assertEq(back, bytes32(0));

        AccessLogger.LogEntry memory entry = _lastLog();
        assertEq(entry.requester, from);
        assertEq(uint8(entry.outcome), uint8(AccessLogger.Outcome.DENIED));
        assertEq(uint8(entry.reason), uint8(expectedReason));
    }

    // --- Granted path ---

    function test_BothScopeReleasesLinkAndBothHashes() public {
        _grant(ConsentManager.Scope.BOTH, 30);
        (bool granted, string memory link, bytes32 front, bytes32 back) = _request(requester);
        assertTrue(granted);
        assertEq(link, LINK);
        assertEq(front, FRONT);
        assertEq(back, BACK);
    }

    function test_FrontOnlyScopeWithholdsBackHash() public {
        _grant(ConsentManager.Scope.FRONT_ONLY, 30);
        (bool granted, string memory link, bytes32 front, bytes32 back) = _request(requester);
        assertTrue(granted);
        assertEq(link, LINK);
        assertEq(front, FRONT);
        assertEq(back, bytes32(0));
    }

    function test_BackOnlyScopeWithholdsFrontHash() public {
        _grant(ConsentManager.Scope.BACK_ONLY, 30);
        (bool granted, string memory link, bytes32 front, bytes32 back) = _request(requester);
        assertTrue(granted);
        assertEq(link, LINK);
        assertEq(front, bytes32(0));
        assertEq(back, BACK);
    }

    function test_GrantedAccessIsLogged() public {
        _grant(ConsentManager.Scope.BOTH, 30);
        _request(requester);

        assertEq(logger.getLogCount(user), 1);
        AccessLogger.LogEntry memory entry = _lastLog();
        assertEq(entry.requester, requester);
        assertEq(entry.timestamp, block.timestamp);
        assertEq(uint8(entry.outcome), uint8(AccessLogger.Outcome.GRANTED));
        assertEq(uint8(entry.reason), uint8(AccessLogger.Reason.NONE));
    }

    function test_GrantedAccessEmitsEvents() public {
        _grant(ConsentManager.Scope.BOTH, 30);

        vm.expectEmit(true, true, false, true, address(logger));
        emit AccessLogger.AccessLogged(user, requester, AccessLogger.Outcome.GRANTED, AccessLogger.Reason.NONE, block.timestamp);
        vm.expectEmit(true, true, false, false, address(dsm));
        emit DataSharingManager.AccessGranted(user, requester);
        _request(requester);
    }

    // --- Denied path: returns false instead of reverting, and is still logged ---

    function test_NoConsentIsDeniedAndLogged() public {
        _assertDenied(requester, AccessLogger.Reason.NO_CONSENT);
        assertEq(logger.getLogCount(user), 1);
    }

    function test_RevokedConsentIsDenied() public {
        _grant(ConsentManager.Scope.BOTH, 30);
        vm.prank(user);
        consent.revokeConsent(requester);
        _assertDenied(requester, AccessLogger.Reason.REVOKED);
    }

    function test_ExpiredConsentIsDenied() public {
        _grant(ConsentManager.Scope.BOTH, 30);
        vm.warp(block.timestamp + 30 days + 1);
        _assertDenied(requester, AccessLogger.Reason.EXPIRED);
    }

    function test_DeniedAccessEmitsEvents() public {
        vm.expectEmit(true, true, false, true, address(logger));
        emit AccessLogger.AccessLogged(user, requester, AccessLogger.Outcome.DENIED, AccessLogger.Reason.NO_CONSENT, block.timestamp);
        vm.expectEmit(true, true, false, true, address(dsm));
        emit DataSharingManager.AccessDenied(user, requester, AccessLogger.Reason.NO_CONSENT);
        _request(requester);
    }

    function test_ConsentForOneRequesterDoesNotCoverAnother() public {
        _grant(ConsentManager.Scope.BOTH, 30);
        _assertDenied(otherRequester, AccessLogger.Reason.NO_CONSENT);
    }

    function test_TokenBalanceDoesNotGrantAccess() public {
        // A second user earns ACT by consenting to otherRequester and hands it
        // to `requester`, which now holds ACT but still has no consent from `user`.
        address holder = address(0x1002);
        bytes32 emailHash = keccak256("test-user-2@example.invalid");
        bytes32 front = sha256("test-user-2-front");
        bytes32 back = sha256("test-user-2-back");
        vm.prank(holder);
        registry.registerUser(emailHash, "https://storage.example.invalid/docs/test-user-2", front, back);
        vm.prank(holder);
        consent.setConsent(otherRequester, ConsentManager.Scope.BOTH, 30);
        uint256 reward = token.balanceOf(holder);
        vm.prank(holder);
        token.transfer(requester, reward);
        assertEq(token.balanceOf(requester), reward);

        _assertDenied(requester, AccessLogger.Reason.NO_CONSENT);
    }

    function test_EveryAttemptIsLogged() public {
        _request(requester); // denied
        _grant(ConsentManager.Scope.BOTH, 30);
        _request(requester); // granted
        _request(otherRequester); // denied
        assertEq(logger.getLogCount(user), 3);
    }

    // --- Whitelist (TASKS A2): callers that aren't requesters revert ---

    function test_NonWhitelistedCallerReverts() public {
        vm.prank(stranger);
        vm.expectRevert("DataSharingManager: requester not whitelisted");
        dsm.requestAccess(user);

        // a reverted call leaves nothing in the user's log, so strangers can't spam it
        assertEq(logger.getLogCount(user), 0);
    }

    function test_DewhitelistedRequesterLosesAccess() public {
        _grant(ConsentManager.Scope.BOTH, 30);
        (bool granted, , , ) = _request(requester);
        assertTrue(granted);

        registry.setRequesterStatus(requester, false);

        // the user's consent is still valid, but the requester no longer is
        assertTrue(consent.isConsentValid(user, requester));
        vm.prank(requester);
        vm.expectRevert("DataSharingManager: requester not whitelisted");
        dsm.requestAccess(user);
        assertEq(logger.getLogCount(user), 1); // only the earlier GRANTED entry

        // re-approving the requester restores access under the same consent
        registry.setRequesterStatus(requester, true);
        (granted, , , ) = _request(requester);
        assertTrue(granted);
    }
}
