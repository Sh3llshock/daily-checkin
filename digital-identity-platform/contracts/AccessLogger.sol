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

    struct LogEntry {
        address requester;
        uint256 timestamp;
        Outcome outcome;
        string reason; // "" on GRANTED; "NO_CONSENT" | "EXPIRED" | "REVOKED" on DENIED
    }

    address public dataSharingManager;
    mapping(address => LogEntry[]) private logs;

    event DataSharingManagerUpdated(address indexed newManager);
    event AccessLogged(address indexed user, address indexed requester, Outcome outcome, string reason, uint256 timestamp);

    constructor() Ownable(msg.sender) {}

    modifier onlyDataSharingManager() {
        require(msg.sender == dataSharingManager, "AccessLogger: caller is not DataSharingManager");
        _;
    }

    /// @notice Wire up the one contract allowed to write log entries. Admin only.
    function setDataSharingManager(address manager) external onlyOwner {
        require(manager != address(0), "AccessLogger: zero address");
        dataSharingManager = manager;
        emit DataSharingManagerUpdated(manager);
    }

    /// @notice Append a new immutable entry. Only DataSharingManager may call
    /// this -- no externally-owned account can write directly.
    function logAccess(address user, address requester, Outcome outcome, string calldata reason)
        external
        onlyDataSharingManager
    {
        logs[user].push(LogEntry({
            requester: requester,
            timestamp: block.timestamp,
            outcome: outcome,
            reason: reason
        }));
        emit AccessLogged(user, requester, outcome, reason, block.timestamp);
    }

    function getLogCount(address user) external view returns (uint256) {
        return logs[user].length;
    }

    /// @notice Read a user's own full access history (or the admin, for
    /// compliance review). Requesters can never read anyone else's log.
    function getLogs(address user) external view returns (LogEntry[] memory) {
        require(msg.sender == user || msg.sender == owner(), "AccessLogger: not authorized");
        return logs[user];
    }
}
