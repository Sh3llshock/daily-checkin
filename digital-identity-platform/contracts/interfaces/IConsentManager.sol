// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IConsentManager {
    function getConsent(address patient, address requester) external view returns (
        uint8 scope,
        uint256 grantedAt,
        uint256 expiresAt,
        bool revoked,
        bool exists
    );
}
