// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../AccessLogger.sol";

/// @title EventsOnlyAccessLogger (gas experiment, NOT deployed)
/// @notice TASKS A4 experiment: the same `logAccess` interface and the same
/// `AccessLogged` event as AccessLogger, but with no storage array. Used only
/// by `GAS_BENCH_LOGGER=EventsOnlyAccessLogger npm run gas:bench` to measure
/// what the on-chain copy of the log costs. Events are still permanent and
/// can't be deleted, but contracts can't read them back, so `getLogs` would
/// have to be rebuilt off-chain from the AccessLogged events (eth_getLogs
/// filtered on the indexed `user`).
/// @dev AI-assisted: written with Claude Code (Claude Opus 5.5) on 2026-10-01;
/// must be reviewed by the team and declared in the report's AI statement.
contract EventsOnlyAccessLogger is Ownable {
    address public dataSharingManager;

    event DataSharingManagerUpdated(address indexed newManager);
    event AccessLogged(
        address indexed user,
        address indexed requester,
        AccessLogger.Outcome outcome,
        AccessLogger.Reason reason,
        uint256 timestamp
    );

    constructor() Ownable(msg.sender) {}

    function setDataSharingManager(address manager) external onlyOwner {
        require(dataSharingManager == address(0), "AccessLogger: manager already set");
        require(manager != address(0), "AccessLogger: zero address");
        dataSharingManager = manager;
        emit DataSharingManagerUpdated(manager);
    }

    function logAccess(address user, address requester, AccessLogger.Outcome outcome, AccessLogger.Reason reason)
        external
    {
        require(msg.sender == dataSharingManager, "AccessLogger: caller is not DataSharingManager");
        emit AccessLogged(user, requester, outcome, reason, block.timestamp);
    }
}
