// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "./DataSharingManager.sol";

/// Integration tests: end-to-end user workflows across all five contracts,
/// deployed and wired the same way as ignition/modules/DigitalIdentityPlatform.ts.
/// All identity values are synthetic placeholders -- no personal data.
contract DigitalIdentityPlatformTest is Test {
    DigitalIdentityRegistry registry;
    AccessToken token;
    ConsentManager consent;
    AccessLogger logger;
    DataSharingManager dsm;

    // this test contract plays the admin
    address user1 = address(0x1001);
    address user2 = address(0x1002);
    address hospital = address(0x2001);
    address lab = address(0x2002);
    address unapproved = address(0xBAD);
    uint256 constant REWARD = 10 * 1e18;

    function setUp() public {
        token = new AccessToken();
        registry = new DigitalIdentityRegistry();
        consent = new ConsentManager(registry, token);
        logger = new AccessLogger();
        dsm = new DataSharingManager(registry, consent, logger);
        token.setMinter(address(consent));
        logger.setDataSharingManager(address(dsm));
    }

    function _link(string memory label) internal pure returns (string memory) {
        return string.concat("https://storage.example.invalid/docs/", label);
    }

    function _register(address who, string memory label) internal {
        bytes32 emailHash = keccak256(abi.encodePacked(label, "@example.invalid"));
        bytes32 front = sha256(abi.encodePacked(label, "-front"));
        bytes32 back = sha256(abi.encodePacked(label, "-back"));
        string memory link = _link(label);
        vm.prank(who);
        registry.registerUser(emailHash, link, front, back);
    }

    function _grant(address who, address to, ConsentManager.Scope scope, uint256 durationDays) internal {
        vm.prank(who);
        consent.setConsent(to, scope, durationDays);
    }

    function _request(address from, address user)
        internal
        returns (bool granted, string memory link, bytes32 front, bytes32 back)
    {
        vm.prank(from);
        return dsm.requestAccess(user);
    }

    function _logsOf(address user) internal returns (AccessLogger.LogEntry[] memory) {
        vm.prank(user);
        return logger.getLogs(user);
    }

    /// registration -> whitelist -> grant consent -> data access -> revoke -> denied
    function test_FullLifecycle() public {
        _register(user1, "test-user-1");
        assertTrue(registry.isRegistered(user1));

        registry.setRequesterStatus(hospital, true);

        _grant(user1, hospital, ConsentManager.Scope.BOTH, 30);
        assertTrue(consent.isConsentValid(user1, hospital));
        assertEq(token.balanceOf(user1), REWARD);

        (bool granted, string memory link, bytes32 front, bytes32 back) = _request(hospital, user1);
        assertTrue(granted);
        assertEq(link, _link("test-user-1"));
        assertEq(front, sha256(abi.encodePacked("test-user-1", "-front")));
        assertEq(back, sha256(abi.encodePacked("test-user-1", "-back")));

        vm.prank(user1);
        consent.revokeConsent(hospital);

        (granted, link, front, back) = _request(hospital, user1);
        assertFalse(granted);
        assertEq(bytes(link).length, 0);

        AccessLogger.LogEntry[] memory entries = _logsOf(user1);
        assertEq(entries.length, 2);
        assertEq(uint8(entries[0].outcome), uint8(AccessLogger.Outcome.GRANTED));
        assertEq(uint8(entries[1].outcome), uint8(AccessLogger.Outcome.DENIED));
        assertEq(entries[1].reason, "REVOKED");

        assertEq(token.balanceOf(user1), REWARD); // reward kept, nothing extra minted
    }

    /// Consent lapses on its own; renewing it restores access without a new reward.
    function test_ConsentExpiresAndCanBeRenewed() public {
        _register(user1, "test-user-1");
        registry.setRequesterStatus(hospital, true);
        _grant(user1, hospital, ConsentManager.Scope.BOTH, 7);

        (bool granted, , , ) = _request(hospital, user1);
        assertTrue(granted);

        vm.warp(block.timestamp + 7 days + 1);
        (granted, , , ) = _request(hospital, user1);
        assertFalse(granted);

        _grant(user1, hospital, ConsentManager.Scope.BOTH, 30);
        (granted, , , ) = _request(hospital, user1);
        assertTrue(granted);

        AccessLogger.LogEntry[] memory entries = _logsOf(user1);
        assertEq(entries.length, 3);
        assertEq(entries[1].reason, "EXPIRED");
        assertEq(token.balanceOf(user1), REWARD);
    }

    /// A re-uploaded ID is served to requesters that already hold consent.
    function test_DocumentUpdateReachesConsentedRequester() public {
        _register(user1, "test-user-1");
        registry.setRequesterStatus(hospital, true);
        _grant(user1, hospital, ConsentManager.Scope.BOTH, 30);

        string memory newLink = _link("test-user-1-v2");
        bytes32 newFront = sha256("test-user-1-front-renewed");
        bytes32 newBack = sha256("test-user-1-back-renewed");
        vm.prank(user1);
        registry.updateDocument(newLink, newFront, newBack);

        (bool granted, string memory link, bytes32 front, bytes32 back) = _request(hospital, user1);
        assertTrue(granted);
        assertEq(link, newLink);
        assertEq(front, newFront);
        assertEq(back, newBack);
    }

    /// Two users, two requesters: consents, scopes, logs and rewards stay separate.
    function test_MultipleUsersAndRequestersAreIsolated() public {
        _register(user1, "test-user-1");
        _register(user2, "test-user-2");
        registry.setRequesterStatus(hospital, true);
        registry.setRequesterStatus(lab, true);

        _grant(user1, hospital, ConsentManager.Scope.FRONT_ONLY, 30);
        _grant(user2, lab, ConsentManager.Scope.BOTH, 30);

        (bool granted, , bytes32 front, bytes32 back) = _request(hospital, user1);
        assertTrue(granted);
        assertTrue(front != bytes32(0));
        assertEq(back, bytes32(0)); // FRONT_ONLY

        (granted, , , ) = _request(hospital, user2);
        assertFalse(granted);

        (granted, , front, back) = _request(lab, user2);
        assertTrue(granted);
        assertTrue(front != bytes32(0) && back != bytes32(0));

        (granted, , , ) = _request(lab, user1);
        assertFalse(granted);

        assertEq(_logsOf(user1).length, 2);
        assertEq(_logsOf(user2).length, 2);

        vm.prank(user1);
        vm.expectRevert("AccessLogger: not authorized");
        logger.getLogs(user2);

        assertEq(token.balanceOf(user1), REWARD);
        assertEq(token.balanceOf(user2), REWARD);
    }

    /// A requester the admin never approved can neither receive consent nor data.
    function test_UnapprovedRequesterIsBlocked() public {
        _register(user1, "test-user-1");

        vm.prank(user1);
        vm.expectRevert("ConsentManager: requester not whitelisted");
        consent.setConsent(unapproved, ConsentManager.Scope.BOTH, 30);

        (bool granted, , , ) = _request(unapproved, user1);
        assertFalse(granted);

        AccessLogger.LogEntry[] memory entries = _logsOf(user1);
        assertEq(entries.length, 1);
        assertEq(entries[0].requester, unapproved);
        assertEq(entries[0].reason, "NO_CONSENT");
    }

    /// The admin manages the whitelist but cannot read data, revoke consent or write logs.
    function test_AdminCannotBypassUserControl() public {
        _register(user1, "test-user-1");
        registry.setRequesterStatus(hospital, true);
        _grant(user1, hospital, ConsentManager.Scope.BOTH, 30);

        (bool granted, , , ) = dsm.requestAccess(user1);
        assertFalse(granted);

        vm.expectRevert("ConsentManager: no such consent");
        consent.revokeConsent(hospital);
        assertTrue(consent.isConsentValid(user1, hospital));

        vm.expectRevert("AccessLogger: caller is not DataSharingManager");
        logger.logAccess(user1, hospital, AccessLogger.Outcome.GRANTED, "");

        vm.expectRevert("AccessToken: caller is not minter");
        token.mintReward(address(this), REWARD);
    }
}
