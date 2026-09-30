// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

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

    function _log(address forUser, AccessLogger.Outcome outcome, string memory reason) internal {
        vm.prank(manager);
        logger.logAccess(forUser, requester, outcome, reason);
    }

    function test_SetDataSharingManager() public {
        address newManager = address(0xD5B);
        vm.expectEmit(true, false, false, false, address(logger));
        emit AccessLogger.DataSharingManagerUpdated(newManager);
        logger.setDataSharingManager(newManager);
        assertEq(logger.dataSharingManager(), newManager);
    }

    function test_OnlyAdminCanSetDataSharingManager() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        logger.setDataSharingManager(stranger);
    }

    function test_RejectsZeroManager() public {
        vm.expectRevert("AccessLogger: zero address");
        logger.setDataSharingManager(address(0));
    }

    function test_OnlyDataSharingManagerCanLog() public {
        vm.prank(stranger);
        vm.expectRevert("AccessLogger: caller is not DataSharingManager");
        logger.logAccess(user, stranger, AccessLogger.Outcome.GRANTED, "");

        vm.prank(user);
        vm.expectRevert("AccessLogger: caller is not DataSharingManager");
        logger.logAccess(user, requester, AccessLogger.Outcome.DENIED, "NO_CONSENT");

        // not even the admin can write entries directly
        vm.expectRevert("AccessLogger: caller is not DataSharingManager");
        logger.logAccess(user, requester, AccessLogger.Outcome.GRANTED, "");
    }

    function test_RepointedManagerRevokesOldManager() public {
        logger.setDataSharingManager(address(0xD5B));
        vm.prank(manager);
        vm.expectRevert("AccessLogger: caller is not DataSharingManager");
        logger.logAccess(user, requester, AccessLogger.Outcome.GRANTED, "");
    }

    function test_LogAppendsEntry() public {
        _log(user, AccessLogger.Outcome.GRANTED, "");
        assertEq(logger.getLogCount(user), 1);

        vm.prank(user);
        AccessLogger.LogEntry[] memory entries = logger.getLogs(user);
        assertEq(entries.length, 1);
        assertEq(entries[0].requester, requester);
        assertEq(entries[0].timestamp, block.timestamp);
        assertEq(uint8(entries[0].outcome), uint8(AccessLogger.Outcome.GRANTED));
        assertEq(entries[0].reason, "");
    }

    function test_LogEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(logger));
        emit AccessLogger.AccessLogged(user, requester, AccessLogger.Outcome.DENIED, "EXPIRED", block.timestamp);
        _log(user, AccessLogger.Outcome.DENIED, "EXPIRED");
    }

    function test_EntriesAreKeptInOrder() public {
        uint256 t0 = block.timestamp;
        _log(user, AccessLogger.Outcome.DENIED, "NO_CONSENT");
        vm.warp(t0 + 1 days);
        _log(user, AccessLogger.Outcome.GRANTED, "");
        vm.warp(t0 + 2 days);
        _log(user, AccessLogger.Outcome.DENIED, "REVOKED");

        vm.prank(user);
        AccessLogger.LogEntry[] memory entries = logger.getLogs(user);
        assertEq(entries.length, 3);
        assertEq(entries[0].reason, "NO_CONSENT");
        assertEq(entries[0].timestamp, t0);
        assertEq(uint8(entries[1].outcome), uint8(AccessLogger.Outcome.GRANTED));
        assertEq(entries[1].timestamp, t0 + 1 days);
        assertEq(entries[2].reason, "REVOKED");
        assertEq(entries[2].timestamp, t0 + 2 days);
    }

    function test_LogsArePerUser() public {
        _log(user, AccessLogger.Outcome.GRANTED, "");
        _log(user, AccessLogger.Outcome.GRANTED, "");
        _log(otherUser, AccessLogger.Outcome.DENIED, "NO_CONSENT");

        assertEq(logger.getLogCount(user), 2);
        assertEq(logger.getLogCount(otherUser), 1);
    }

    function test_UserAndAdminCanReadLogs() public {
        _log(user, AccessLogger.Outcome.GRANTED, "");

        vm.prank(user);
        assertEq(logger.getLogs(user).length, 1);

        assertEq(logger.getLogs(user).length, 1); // admin
    }

    function test_OthersCannotReadUsersLogs() public {
        _log(user, AccessLogger.Outcome.GRANTED, "");

        vm.prank(requester);
        vm.expectRevert("AccessLogger: not authorized");
        logger.getLogs(user);

        vm.prank(otherUser);
        vm.expectRevert("AccessLogger: not authorized");
        logger.getLogs(user);
    }
}
