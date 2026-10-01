// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./DigitalIdentityRegistry.sol";
import "./AccessToken.sol";

/// @title ConsentManager
/// @notice Users grant/revoke time-limited, scoped consent to whitelisted
/// requesters. A user's first consent grant to each requester mints an ACT
/// reward; the token is a pure incentive and is never checked when deciding
/// data access.
contract ConsentManager is Ownable {
    enum Scope { FRONT_ONLY, BACK_ONLY, BOTH }

    /// @dev 1 + 8 + 8 + 1 + 1 = 19 bytes, so a whole consent record fits in
    /// ONE storage slot instead of four: a first grant writes one new slot,
    /// and every validity check reads one (TASKS A4). uint64 seconds lasts far
    /// beyond any realistic date.
    struct Consent {
        Scope scope;
        uint64 grantedAt;
        uint64 expiresAt;
        bool revoked;
        bool exists;
    }

    uint256 public constant MIN_DURATION_DAYS = 1;
    uint256 public constant MAX_DURATION_DAYS = 365;
    uint256 public rewardAmount = 10 * 1e18; // 10 ACT per consent grant

    DigitalIdentityRegistry public immutable registry;
    AccessToken public immutable accessToken;

    // user => requester => Consent
    mapping(address => mapping(address => Consent)) private consents;

    event ConsentGranted(address indexed user, address indexed requester, Scope scope, uint256 expiresAt);
    event ConsentRevoked(address indexed user, address indexed requester);
    event RewardAmountUpdated(uint256 newAmount);

    constructor(DigitalIdentityRegistry _registry, AccessToken _accessToken) Ownable(msg.sender) {
        registry = _registry;
        accessToken = _accessToken;
    }

    /// @notice Admin-only tuning of the incentive rate. Never affects access logic.
    function setRewardAmount(uint256 newAmount) external onlyOwner {
        rewardAmount = newAmount;
        emit RewardAmountUpdated(newAmount);
    }

    /// @notice Grant time-limited, scoped consent to a whitelisted requester.
    /// Only the identity owner may call this for their own record.
    function setConsent(address requester, Scope scope, uint256 durationDays) external {
        require(registry.isRegistered(msg.sender), "ConsentManager: user not registered");
        require(registry.isApprovedRequester(requester), "ConsentManager: requester not whitelisted");
        require(
            durationDays >= MIN_DURATION_DAYS && durationDays <= MAX_DURATION_DAYS,
            "ConsentManager: duration out of range"
        );

        // `exists` is never cleared (revoking only sets `revoked`), so this is
        // true only the very first time this user consents to this requester.
        bool firstGrant = !consents[msg.sender][requester].exists;

        uint256 expiresAt = block.timestamp + (durationDays * 1 days);
        consents[msg.sender][requester] = Consent({
            scope: scope,
            grantedAt: uint64(block.timestamp),
            expiresAt: uint64(expiresAt),
            revoked: false,
            exists: true
        });

        emit ConsentGranted(msg.sender, requester, scope, expiresAt);

        // Incentive only -- no tokens ever move during data access.
        // Rewarded once per (user, requester) pair: re-granting or
        // revoke-then-re-grant to the same requester must not mint again,
        // otherwise a user could farm ACT by looping setConsent.
        if (firstGrant) {
            accessToken.mintReward(msg.sender, rewardAmount);
        }
    }

    /// @notice Revoke an active consent immediately. Only the identity owner
    /// may revoke their own consent -- no admin override.
    function revokeConsent(address requester) external {
        Consent storage c = consents[msg.sender][requester];
        require(c.exists, "ConsentManager: no such consent");
        require(!c.revoked, "ConsentManager: already revoked");
        c.revoked = true;
        emit ConsentRevoked(msg.sender, requester);
    }

    /// @notice True only if a non-revoked, non-expired consent record exists.
    function isConsentValid(address user, address requester) public view returns (bool) {
        Consent storage c = consents[user][requester];
        return c.exists && !c.revoked && block.timestamp <= c.expiresAt;
    }

    function getConsent(address user, address requester)
        external
        view
        returns (Scope scope, uint256 grantedAt, uint256 expiresAt, bool revoked, bool exists)
    {
        Consent storage c = consents[user][requester];
        return (c.scope, c.grantedAt, c.expiresAt, c.revoked, c.exists);
    }
}
