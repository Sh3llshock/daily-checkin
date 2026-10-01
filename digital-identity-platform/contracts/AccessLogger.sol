// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

/// @title AccessLogger
/// @notice Append-only audit trail. There is deliberately no delete/edit
/// function anywhere in this contract -- every entry, once written, is
/// permanent, and is additionally emitted as an event for independent
/// off-chain verification.
contract AccessLogger is Ownable {
    enum Outcome { DENIED, GRANTED }

    /// @notice Why an attempt was denied; NONE on GRANTED entries.
    /// @dev An enum is one byte, where the string it replaced needed its own
    /// storage slot (TASKS A4).
    enum Reason { NONE, NO_CONSENT, REVOKED, EXPIRED }

    /// @dev 20 + 8 + 1 + 1 = 30 bytes, so a whole entry fits in ONE storage
    /// slot: each new entry costs a single zero-to-non-zero SSTORE instead of
    /// three (TASKS A4). uint64 seconds lasts far beyond any realistic date.
    struct LogEntry {
        address requester;
        uint64 timestamp;
        Outcome outcome;
        Reason reason;
    }

    address public dataSharingManager;
    mapping(address => LogEntry[]) private logs;

    event DataSharingManagerUpdated(address indexed newManager);
    event AccessLogged(address indexed user, address indexed requester, Outcome outcome, Reason reason, uint256 timestamp);

    constructor() Ownable(msg.sender) {}

    modifier onlyDataSharingManager() {
        require(msg.sender == dataSharingManager, "AccessLogger: caller is not DataSharingManager");
        _;
    }

    /// @notice Wire up the one contract allowed to write log entries. Admin
    /// only, and only once: after the first call the writer can never change,
    /// so not even the admin can later point it at their own wallet and
    /// forge entries.
    /// @dev Not a constructor argument because DataSharingManager takes this
    /// logger's address in *its* constructor, so the logger has to be deployed
    /// first and wired afterwards (see ignition/modules/DigitalIdentityPlatform.ts).
    function setDataSharingManager(address manager) external onlyOwner {
        require(dataSharingManager == address(0), "AccessLogger: manager already set");
        require(manager != address(0), "AccessLogger: zero address");
        dataSharingManager = manager;
        emit DataSharingManagerUpdated(manager);
    }

    /// @notice Append a new immutable entry. Only DataSharingManager may call
    /// this -- no externally-owned account can write directly.
    function logAccess(address user, address requester, Outcome outcome, Reason reason)
        external
        onlyDataSharingManager
    {
        logs[user].push(LogEntry({
            requester: requester,
            timestamp: uint64(block.timestamp),
            outcome: outcome,
            reason: reason
        }));
        emit AccessLogged(user, requester, outcome, reason, block.timestamp);
    }

    function getLogCount(address user) external view returns (uint256) {
        return logs[user].length;
    }

    /// @notice Read a user's full access history. Anyone can call this.
    /// @dev The log is public on purpose: all contract storage can be read
    /// with eth_getStorageAt and every entry is also an AccessLogged event, so
    /// a `msg.sender` check here would only look like privacy (an eth_call can
    /// set any `from` address). The audit trail is transparent, not secret;
    /// the data itself is protected off-chain by the gatekeeper.
    function getLogs(address user) external view returns (LogEntry[] memory) {
        return logs[user];
    }
}
