// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./interfaces/IDigitalIdentity.sol";
import "./interfaces/IConsentManager.sol";

/**
 * @title DataSharing
 * @dev Requesters ask for access to a patient's ID here. The contract checks
 *      the consent and writes every attempt to the audit log, also the failed
 *      ones. The files themselves are handed out by the patient's off-chain
 *      vault, which only does that after it sees an AccessGranted event.
 */
contract DataSharing {
    enum Result { Granted, Denied }
    enum Reason { None, NotApproved, NoConsent, Revoked, Expired }

    // fits in one storage slot (20 + 1 + 1 + 1 + 8 bytes)
    struct AccessLog {
        address requester;
        uint8 scope;
        Result result;
        Reason reason;
        uint64 timestamp;
    }

    // State variables
    address public owner;
    bool public paused;
    IDigitalIdentity public immutable identity;
    IConsentManager public immutable consentManager;

    // patient => list of all access attempts (append only, nothing can delete it)
    mapping(address => AccessLog[]) private accessLogs;

    // Events
    event AccessGranted(address indexed patient, address indexed requester, uint8 scope, uint256 logIndex);
    event AccessDenied(address indexed patient, address indexed requester, Reason reason, uint256 logIndex);
    event Paused(bool isPaused);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not the owner");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "Contract is paused");
        _;
    }

    constructor(address _identity, address _consentManager) {
        require(_identity != address(0) && _consentManager != address(0), "Invalid address");
        owner = msg.sender;
        identity = IDigitalIdentity(_identity);
        consentManager = IConsentManager(_consentManager);
    }

    /**
     * @dev Request access to a patient's ID documents.
     *      A failed request does not revert, otherwise the log entry
     *      would be rolled back too. It just returns false.
     * @param _patient the patient whose documents are requested
     * @return granted true if the requester has a valid consent
     */
    function requestAccess(address _patient) external whenNotPaused returns (bool granted) {
        require(identity.isRegistered(_patient), "Patient not registered");

        Reason reason = Reason.None;
        uint8 scope = 0;

        if (!identity.isApprovedRequester(msg.sender)) {
            reason = Reason.NotApproved;
        } else {
            (uint8 s, , uint256 expiresAt, bool revoked, bool exists) = consentManager.getConsent(_patient, msg.sender);
            scope = s;
            if (!exists) {
                reason = Reason.NoConsent;
            } else if (revoked) {
                reason = Reason.Revoked;
            } else if (block.timestamp >= expiresAt) {
                reason = Reason.Expired;
            }
        }

        granted = (reason == Reason.None);

        accessLogs[_patient].push(AccessLog({
            requester: msg.sender,
            scope: scope,
            result: granted ? Result.Granted : Result.Denied,
            reason: reason,
            timestamp: uint64(block.timestamp)
        }));

        uint256 index = accessLogs[_patient].length - 1;
        if (granted) {
            emit AccessGranted(_patient, msg.sender, scope, index);
        } else {
            emit AccessDenied(_patient, msg.sender, reason, index);
        }
    }

    function getLogCount(address _patient) external view returns (uint256) {
        return accessLogs[_patient].length;
    }

    function getLog(address _patient, uint256 _index) external view returns (AccessLog memory) {
        require(_index < accessLogs[_patient].length, "Invalid index");
        return accessLogs[_patient][_index];
    }

    function getLogs(address _patient) external view returns (AccessLog[] memory) {
        return accessLogs[_patient];
    }

    // Emergency stop, like in the EscrowManager from lab 4
    function pause() external onlyOwner {
        paused = true;
        emit Paused(true);
    }

    function unpause() external onlyOwner {
        paused = false;
        emit Paused(false);
    }
}
