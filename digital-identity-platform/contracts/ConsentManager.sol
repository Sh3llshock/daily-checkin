// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./interfaces/IDigitalIdentity.sol";
import "./interfaces/IAccessToken.sol";

/**
 * @title ConsentManager
 * @dev Patients give time limited consent to approved requesters and can
 *      revoke it at any time. The first consent to a requester is rewarded
 *      with ACT tokens.
 */
contract ConsentManager {
    // Which part of the ID the requester is allowed to see
    enum Scope { FrontOnly, BackOnly, Both }

    // all fields fit in one storage slot (1 + 8 + 8 + 1 + 1 + 1 bytes)
    struct Consent {
        Scope scope;
        uint64 grantedAt;
        uint64 expiresAt;
        bool revoked;
        bool exists;
        bool rewarded;   // patient already got tokens for this requester
    }

    // State variables
    address public owner;
    IDigitalIdentity public immutable identity;
    IAccessToken public immutable token;

    uint256 public constant MIN_DAYS = 1;
    uint256 public constant MAX_DAYS = 365;
    uint256 public rewardAmount = 10 * 10**18;

    // patient => requester => consent
    mapping(address => mapping(address => Consent)) private consents;

    // Events
    event ConsentGranted(address indexed patient, address indexed requester, Scope scope, uint256 expiresAt);
    event ConsentRevoked(address indexed patient, address indexed requester);
    event RewardAmountChanged(uint256 newAmount);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not the owner");
        _;
    }

    constructor(address _identity, address _token) {
        require(_identity != address(0) && _token != address(0), "Invalid address");
        owner = msg.sender;
        identity = IDigitalIdentity(_identity);
        token = IAccessToken(_token);
    }

    /**
     * @dev Give a requester access to (part of) your ID for some days.
     *      Granting again to the same requester replaces the old consent.
     * @param _requester approved healthcare provider
     * @param _scope FrontOnly, BackOnly or Both
     * @param _days duration, 1 to 365 days
     */
    function grantConsent(address _requester, Scope _scope, uint256 _days) external {
        require(identity.isRegistered(msg.sender), "Not registered");
        require(identity.isApprovedRequester(_requester), "Requester not approved");
        require(_days >= MIN_DAYS && _days <= MAX_DAYS, "Duration must be 1-365 days");

        uint256 expiresAt = block.timestamp + (_days * 1 days);

        // reward only once per requester, otherwise you could grant and
        // revoke in a loop to farm tokens
        bool firstTime = !consents[msg.sender][_requester].rewarded;

        consents[msg.sender][_requester] = Consent({
            scope: _scope,
            grantedAt: uint64(block.timestamp),
            expiresAt: uint64(expiresAt),
            revoked: false,
            exists: true,
            rewarded: true
        });

        emit ConsentGranted(msg.sender, _requester, _scope, expiresAt);

        if (firstTime) {
            token.mint(msg.sender, rewardAmount);
        }
    }

    /**
     * @dev Revoke consent. Works straight away.
     */
    function revokeConsent(address _requester) external {
        Consent storage c = consents[msg.sender][_requester];
        require(c.exists, "No consent found");
        require(!c.revoked, "Already revoked");
        require(block.timestamp < c.expiresAt, "Consent already expired");

        c.revoked = true;
        emit ConsentRevoked(msg.sender, _requester);
    }

    /**
     * @dev A consent is valid if it exists, is not revoked and not expired
     */
    function isConsentValid(address _patient, address _requester) public view returns (bool) {
        Consent memory c = consents[_patient][_requester];
        return c.exists && !c.revoked && block.timestamp < c.expiresAt;
    }

    function getConsent(address _patient, address _requester) external view returns (
        Scope scope,
        uint256 grantedAt,
        uint256 expiresAt,
        bool revoked,
        bool exists
    ) {
        Consent memory c = consents[_patient][_requester];
        return (c.scope, c.grantedAt, c.expiresAt, c.revoked, c.exists);
    }

    function rewarded(address _patient, address _requester) external view returns (bool) {
        return consents[_patient][_requester].rewarded;
    }

    function setRewardAmount(uint256 _amount) external onlyOwner {
        rewardAmount = _amount;
        emit RewardAmountChanged(_amount);
    }
}
