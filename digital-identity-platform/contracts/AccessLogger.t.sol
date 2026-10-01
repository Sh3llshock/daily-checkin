// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// AI-assisted: this test file was generated with Claude Code (Claude Opus 5.5)
// on 2026-09-30 and updated for TASKS A1-A4 on 2026-10-01. Per the coursebook
// GenAI rules it must be fully reviewed by the team before submission and
// declared in the report's AI statement.

import "forge-std/Test.sol";
import "./AccessLogger.sol";

/// Unit tests for AccessLogger.
contract AccessLoggerTest is Test {
    AccessLogger logger;
    address manager = address(0xD5A); // stands in for DataSharingManager
    address user = address(0x1001);
    address otherUser = address(0x1002);
    address requester = address(0x2001);
    address stranger = address(0xBAD);

    function setUp() public {
        logger = new AccessLogger(); // this test contract plays the admin
        logger.setDataSharingManager(manager);
    }

    function _log(address forUser, AccessLogger.Outcome outcome, AccessLogger.Reason reason) internal {
        vm.prank(manager);
        logger.logAccess(forUser, requester, outcome, reason);
    }

    // setUp already wired `logger`, so the setDataSharingManager tests below
    // use a fresh, unwired logger wherever they need the first call to succeed.

    function test_SetDataSharingManager() public {
        AccessLogger fresh = new AccessLogger();
        vm.expectEmit(true, false, false, false, address(fresh));
        emit AccessLogger.DataSharingManagerUpdated(manager);
        fresh.setDataSharingManager(manager);
        assertEq(fresh.dataSharingManager(), manager);
    }

    function test_OnlyAdminCanSetDataSharingManager() public {
        AccessLogger fresh = new AccessLogger();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        fresh.setDataSharingManager(stranger);
    }

    function test_RejectsZeroManager() public {
        AccessLogger fresh = new AccessLogger();
        vm.expectRevert("AccessLogger: zero address");
        fresh.setDataSharingManager(address(0));
    }

    function test_OnlyDataSharingManagerCanLog() public {
        vm.prank(stranger);
        vm.expectRevert("AccessLogger: caller is not DataSharingManager");
        logger.logAccess(user, stranger, AccessLogger.Outcome.GRANTED, AccessLogger.Reason.NONE);

        vm.prank(user);
        vm.expectRevert("AccessLogger: caller is not DataSharingManager");
        logger.logAccess(user, requester, AccessLogger.Outcome.DENIED, AccessLogger.Reason.NO_CONSENT);

        // not even the admin can write entries directly
        vm.expectRevert("AccessLogger: caller is not DataSharingManager");
        logger.logAccess(user, requester, AccessLogger.Outcome.GRANTED, AccessLogger.Reason.NONE);
    }

    function test_ManagerCanOnlyBeSetOnce() public {
        // Not even the admin can re-point the writer, e.g. at their own wallet
        // to forge entries.
        vm.expectRevert("AccessLogger: manager already set");
        logger.setDataSharingManager(address(this));
        assertEq(logger.dataSharingManager(), manager);

        _log(user, AccessLogger.Outcome.GRANTED, AccessLogger.Reason.NONE);
        assertEq(logger.getLogCount(user), 1);
    }

    function test_LogAppendsEntry() public {
        _log(user, AccessLogger.Outcome.GRANTED, AccessLogger.Reason.NONE);
        assertEq(logger.getLogCount(user), 1);

        vm.prank(user);
        AccessLogger.LogEntry[] memory entries = logger.getLogs(user);
        assertEq(entries.length, 1);
        assertEq(entries[0].requester, requester);
        assertEq(entries[0].timestamp, block.timestamp);
        assertEq(uint8(entries[0].outcome), uint8(AccessLogger.Outcome.GRANTED));
        assertEq(uint8(entries[0].reason), uint8(AccessLogger.Reason.NONE));
    }

    function test_LogEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(logger));
        emit AccessLogger.AccessLogged(user, requester, AccessLogger.Outcome.DENIED, AccessLogger.Reason.EXPIRED, block.timestamp);
        _log(user, AccessLogger.Outcome.DENIED, AccessLogger.Reason.EXPIRED);
    }

    function test_EntriesAreKeptInOrder() public {
        uint256 t0 = block.timestamp;
        _log(user, AccessLogger.Outcome.DENIED, AccessLogger.Reason.NO_CONSENT);
        vm.warp(t0 + 1 days);
        _log(user, AccessLogger.Outcome.GRANTED, AccessLogger.Reason.NONE);
        vm.warp(t0 + 2 days);
        _log(user, AccessLogger.Outcome.DENIED, AccessLogger.Reason.REVOKED);

        vm.prank(user);
        AccessLogger.LogEntry[] memory entries = logger.getLogs(user);
        assertEq(entries.length, 3);
        assertEq(uint8(entries[0].reason), uint8(AccessLogger.Reason.NO_CONSENT));
        assertEq(entries[0].timestamp, t0);
        assertEq(uint8(entries[1].outcome), uint8(AccessLogger.Outcome.GRANTED));
        assertEq(entries[1].timestamp, t0 + 1 days);
        assertEq(uint8(entries[2].reason), uint8(AccessLogger.Reason.REVOKED));
        assertEq(entries[2].timestamp, t0 + 2 days);
    }

    function test_OldEntriesNeverChange() public {
        _log(user, AccessLogger.Outcome.DENIED, AccessLogger.Reason.NO_CONSENT);
        AccessLogger.LogEntry memory first = logger.getLogs(user)[0];

        vm.warp(block.timestamp + 1 hours);
        _log(user, AccessLogger.Outcome.GRANTED, AccessLogger.Reason.NONE);
        _log(user, AccessLogger.Outcome.DENIED, AccessLogger.Reason.REVOKED);

        AccessLogger.LogEntry memory firstAgain = logger.getLogs(user)[0];
        assertEq(logger.getLogCount(user), 3);
        assertEq(firstAgain.requester, first.requester);
        assertEq(firstAgain.timestamp, first.timestamp);
        assertEq(uint8(firstAgain.outcome), uint8(first.outcome));
        assertEq(uint8(firstAgain.reason), uint8(first.reason));
    }

    function test_LogsArePerUser() public {
        _log(user, AccessLogger.Outcome.GRANTED, AccessLogger.Reason.NONE);
        _log(user, AccessLogger.Outcome.GRANTED, AccessLogger.Reason.NONE);
        _log(otherUser, AccessLogger.Outcome.DENIED, AccessLogger.Reason.NO_CONSENT);

        assertEq(logger.getLogCount(user), 2);
        assertEq(logger.getLogCount(otherUser), 1);
    }

    /// TASKS A3: the log is public on purpose. A `msg.sender` check on a view
    /// function is not privacy (an eth_call can set any `from`), so anyone can
    /// read it, just as anyone can read the AccessLogged events.
    function test_AnyoneCanReadLogs() public {
        _log(user, AccessLogger.Outcome.GRANTED, AccessLogger.Reason.NONE);

        vm.prank(user);
        assertEq(logger.getLogs(user).length, 1);

        vm.prank(requester);
        assertEq(logger.getLogs(user).length, 1);

        vm.prank(stranger);
        assertEq(logger.getLogs(user).length, 1);

        assertEq(logger.getLogs(user).length, 1); // admin
    }
}
