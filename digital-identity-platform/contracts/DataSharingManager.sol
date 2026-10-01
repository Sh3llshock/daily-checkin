// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./DigitalIdentityRegistry.sol";
import "./ConsentManager.sol";
import "./AccessLogger.sol";

/// @title DataSharingManager
/// @notice The only entry point requesters use to access a user's document
/// reference. It never transfers or stores the underlying ID images -- it
/// only ever checks consent, releases the link + hashes, and logs the
/// attempt (granted or denied). Data ownership never moves.
contract DataSharingManager {
    DigitalIdentityRegistry public immutable registry;
    ConsentManager public immutable consentManager;
    AccessLogger public immutable accessLogger;

    event AccessGranted(address indexed user, address indexed requester);
    event AccessDenied(address indexed user, address indexed requester, AccessLogger.Reason reason);

    constructor(DigitalIdentityRegistry _registry, ConsentManager _consentManager, AccessLogger _accessLogger) {
        registry = _registry;
        consentManager = _consentManager;
        accessLogger = _accessLogger;
    }

    /// @notice Request access to a user's document reference. Only requesters
    /// the admin currently whitelists may call this. If consent is missing,
    /// revoked, or expired, no data is released and `granted` is false; the
    /// attempt is logged either way.
    /// @dev A caller that is not whitelisted (a stranger, or a requester the
    /// admin has removed) reverts: it isn't a requester at all, and logging its
    /// calls would let anyone fill a user's log with spam. A whitelisted
    /// requester's denied attempt deliberately does NOT revert: a revert would
    /// also roll back the DENIED log entry and event, leaving no audit trail.
    function requestAccess(address user)
        external
        returns (bool granted, string memory documentLink, bytes32 frontHash, bytes32 backHash)
    {
        require(registry.isApprovedRequester(msg.sender), "DataSharingManager: requester not whitelisted");

        // One external read gives everything the decision needs (TASKS A4),
        // instead of isConsentValid() followed by getConsent().
        (ConsentManager.Scope scope, , uint256 expiresAt, bool revoked, bool exists) =
            consentManager.getConsent(user, msg.sender);
        AccessLogger.Reason reason = _denialReason(expiresAt, revoked, exists);

        if (reason == AccessLogger.Reason.NONE) {
            (, string memory link, bytes32 front, bytes32 back, ) = registry.getUserRecord(user);
            if (scope == ConsentManager.Scope.FRONT_ONLY) {
                back = bytes32(0);
            } else if (scope == ConsentManager.Scope.BACK_ONLY) {
                front = bytes32(0);
            }

            accessLogger.logAccess(user, msg.sender, AccessLogger.Outcome.GRANTED, AccessLogger.Reason.NONE);
            emit AccessGranted(user, msg.sender);
            return (true, link, front, back);
        }

        accessLogger.logAccess(user, msg.sender, AccessLogger.Outcome.DENIED, reason);
        emit AccessDenied(user, msg.sender, reason);
        return (false, "", bytes32(0), bytes32(0));
    }

    /// @dev The same rule as ConsentManager.isConsentValid, but also says *why*
    /// consent is invalid. Returns NONE when consent is valid. The fuzz test in
    /// DigitalIdentityPlatform.t.sol checks that the two never disagree.
    function _denialReason(uint256 expiresAt, bool revoked, bool exists)
        internal
        view
        returns (AccessLogger.Reason)
    {
        if (!exists) return AccessLogger.Reason.NO_CONSENT;
        if (revoked) return AccessLogger.Reason.REVOKED;
        if (block.timestamp > expiresAt) return AccessLogger.Reason.EXPIRED;
        return AccessLogger.Reason.NONE;
    }
}
