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
    event AccessDenied(address indexed user, address indexed requester, string reason);

    constructor(DigitalIdentityRegistry _registry, ConsentManager _consentManager, AccessLogger _accessLogger) {
        registry = _registry;
        consentManager = _consentManager;
        accessLogger = _accessLogger;
    }

    /// @notice Request access to a user's document reference. Reverts with no
    /// data released if consent is missing, revoked, or expired; the attempt
    /// is logged either way.
    function requestAccess(address user)
        external
        returns (string memory documentLink, bytes32 frontHash, bytes32 backHash)
    {
        if (consentManager.isConsentValid(user, msg.sender)) {
            (, string memory link, bytes32 front, bytes32 back, ) = registry.getUserRecord(user);

            (ConsentManager.Scope scope, , , , ) = consentManager.getConsent(user, msg.sender);
            if (scope == ConsentManager.Scope.FRONT_ONLY) {
                back = bytes32(0);
            } else if (scope == ConsentManager.Scope.BACK_ONLY) {
                front = bytes32(0);
            }

            accessLogger.logAccess(user, msg.sender, AccessLogger.Outcome.GRANTED, "");
            emit AccessGranted(user, msg.sender);
            return (link, front, back);
        }

        string memory reason = _denialReason(user, msg.sender);
        accessLogger.logAccess(user, msg.sender, AccessLogger.Outcome.DENIED, reason);
        emit AccessDenied(user, msg.sender, reason);
        revert(string(abi.encodePacked("DataSharingManager: access denied - ", reason)));
    }

    function _denialReason(address user, address requester) internal view returns (string memory) {
        (, , uint256 expiresAt, bool revoked, bool exists) = consentManager.getConsent(user, requester);
        if (!exists) return "NO_CONSENT";
        if (revoked) return "REVOKED";
        if (block.timestamp > expiresAt) return "EXPIRED";
        return "NO_CONSENT";
    }
}
