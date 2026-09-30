// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

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
        AccessLogger.LogEntry[] memory entries = logger.getLogs(user); // read as admin
        return entries[entries.length - 1];
    }

    function _assertDenied(address from, string memory expectedReason) internal {
        (bool granted, string memory link, bytes32 front, bytes32 back) = _request(from);
        assertFalse(granted);
        assertEq(bytes(link).length, 0);
        assertEq(front, bytes32(0));
        assertEq(back, bytes32(0));

        AccessLogger.LogEntry memory entry = _lastLog();
        assertEq(entry.requester, from);
        assertEq(uint8(entry.outcome), uint8(AccessLogger.Outcome.DENIED));
        assertEq(entry.reason, expectedReason);
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
        assertEq(entry.reason, "");
    }

    function test_GrantedAccessEmitsEvents() public {
        _grant(ConsentManager.Scope.BOTH, 30);

        vm.expectEmit(true, true, false, true, address(logger));
        emit AccessLogger.AccessLogged(user, requester, AccessLogger.Outcome.GRANTED, "", block.timestamp);
        vm.expectEmit(true, true, false, false, address(dsm));
        emit DataSharingManager.AccessGranted(user, requester);
        _request(requester);
    }

    // --- Denied path: returns false instead of reverting, and is still logged ---

    function test_NoConsentIsDeniedAndLogged() public {
        _assertDenied(requester, "NO_CONSENT");
        assertEq(logger.getLogCount(user), 1);
    }

    function test_RevokedConsentIsDenied() public {
        _grant(ConsentManager.Scope.BOTH, 30);
        vm.prank(user);
        consent.revokeConsent(requester);
        _assertDenied(requester, "REVOKED");
    }

    function test_ExpiredConsentIsDenied() public {
        _grant(ConsentManager.Scope.BOTH, 30);
        vm.warp(block.timestamp + 30 days + 1);
        _assertDenied(requester, "EXPIRED");
    }

    function test_DeniedAccessEmitsEvents() public {
        vm.expectEmit(true, true, false, true, address(logger));
        emit AccessLogger.AccessLogged(user, requester, AccessLogger.Outcome.DENIED, "NO_CONSENT", block.timestamp);
        vm.expectEmit(true, true, false, true, address(dsm));
        emit DataSharingManager.AccessDenied(user, requester, "NO_CONSENT");
        _request(requester);
    }

    function test_ConsentForOneRequesterDoesNotCoverAnother() public {
        _grant(ConsentManager.Scope.BOTH, 30);
        _assertDenied(otherRequester, "NO_CONSENT");
    }

    function test_TokenBalanceDoesNotGrantAccess() public {
        // A second user earns ACT by consenting to someone else, then tries to
        // read the first user's record without any consent from them.
        address holder = address(0x1002);
        bytes32 emailHash = keccak256("test-user-2@example.invalid");
        bytes32 front = sha256("test-user-2-front");
        bytes32 back = sha256("test-user-2-back");
        vm.prank(holder);
        registry.registerUser(emailHash, "https://storage.example.invalid/docs/test-user-2", front, back);
        vm.prank(holder);
        consent.setConsent(otherRequester, ConsentManager.Scope.BOTH, 30);
        assertGt(token.balanceOf(holder), 0);

        _assertDenied(holder, "NO_CONSENT");
    }

    function test_EveryAttemptIsLogged() public {
        _request(requester); // denied
        _grant(ConsentManager.Scope.BOTH, 30);
        _request(requester); // granted
        _request(otherRequester); // denied
        _request(stranger); // denied
        assertEq(logger.getLogCount(user), 4);
    }
}
