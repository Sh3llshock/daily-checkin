// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../contracts/AccessToken.sol";
import "../contracts/DigitalIdentity.sol";
import "../contracts/ConsentManager.sol";
import "../contracts/DataSharing.sol";

/**
 * Tests whole user workflows over all four contracts.
 */
contract IntegrationTest is Test {
    AccessToken token;
    DigitalIdentity identity;
    ConsentManager consent;
    DataSharing sharing;

    address admin;
    address alice;   // patient
    address bob;     // patient
    address doctor;
    address lab;

    function setUp() public {
        admin = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        doctor = makeAddr("doctor");
        lab = makeAddr("lab");

        // same order as the ignition module
        token = new AccessToken();
        identity = new DigitalIdentity();
        consent = new ConsentManager(address(identity), address(token));
        sharing = new DataSharing(address(identity), address(consent));
        token.setMinter(address(consent));
    }

    function _register(address _patient, string memory _ref) internal {
        // sha256 is a precompile call, so it has to happen before vm.prank
        bytes32 front = sha256(abi.encodePacked(_ref, "front"));
        bytes32 back = sha256(abi.encodePacked(_ref, "back"));
        vm.prank(_patient);
        identity.registerUser(keccak256(abi.encodePacked(_ref)), _ref, front, back);
    }

    function test_FullWorkflow() public {
        // admin approves the doctor, alice registers
        identity.approveRequester(doctor);
        _register(alice, "vault://alice");

        // 1. no consent yet -> denied
        vm.prank(doctor);
        assertFalse(sharing.requestAccess(alice));

        // 2. alice grants 30 days -> reward + granted
        vm.prank(alice);
        consent.grantConsent(doctor, ConsentManager.Scope.Both, 30);
        assertEq(token.balanceOf(alice), 10 ether);
        vm.prank(doctor);
        assertTrue(sharing.requestAccess(alice));

        // 3. alice revokes -> denied
        vm.prank(alice);
        consent.revokeConsent(doctor);
        vm.prank(doctor);
        assertFalse(sharing.requestAccess(alice));

        // 4. new consent for 7 days, no new reward, granted
        vm.prank(alice);
        consent.grantConsent(doctor, ConsentManager.Scope.FrontOnly, 7);
        assertEq(token.balanceOf(alice), 10 ether);
        vm.prank(doctor);
        assertTrue(sharing.requestAccess(alice));

        // 5. 7 days later -> expired
        vm.warp(block.timestamp + 7 days);
        vm.prank(doctor);
        assertFalse(sharing.requestAccess(alice));

        // the log has all 5 attempts with the right reasons
        DataSharing.AccessLog[] memory logs = sharing.getLogs(alice);
        assertEq(logs.length, 5);
        assertEq(uint(logs[0].reason), uint(DataSharing.Reason.NoConsent));
        assertEq(uint(logs[1].result), uint(DataSharing.Result.Granted));
        assertEq(uint(logs[2].reason), uint(DataSharing.Reason.Revoked));
        assertEq(uint(logs[3].scope), uint(ConsentManager.Scope.FrontOnly));
        assertEq(uint(logs[4].reason), uint(DataSharing.Reason.Expired));
    }

    function test_ConsentIsPerPatientAndPerRequester() public {
        identity.approveRequester(doctor);
        identity.approveRequester(lab);
        _register(alice, "vault://alice");
        _register(bob, "vault://bob");

        // alice only trusts the doctor
        vm.prank(alice);
        consent.grantConsent(doctor, ConsentManager.Scope.Both, 30);

        vm.prank(doctor);
        assertTrue(sharing.requestAccess(alice));
        // the doctor has no consent from bob
        vm.prank(doctor);
        assertFalse(sharing.requestAccess(bob));
        // the lab has no consent from alice
        vm.prank(lab);
        assertFalse(sharing.requestAccess(alice));

        assertEq(sharing.getLogCount(alice), 2);
        assertEq(sharing.getLogCount(bob), 1);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_RemovedRequesterLosesAccess() public {
        identity.approveRequester(doctor);
        _register(alice, "vault://alice");
        vm.prank(alice);
        consent.grantConsent(doctor, ConsentManager.Scope.Both, 30);

        identity.removeRequester(doctor);

        vm.prank(doctor);
        assertFalse(sharing.requestAccess(alice));
        assertEq(uint(sharing.getLog(alice, 0).reason), uint(DataSharing.Reason.NotApproved));
    }

    function test_DocumentUpdateKeepsConsent() public {
        identity.approveRequester(doctor);
        _register(alice, "vault://alice");
        vm.prank(alice);
        consent.grantConsent(doctor, ConsentManager.Scope.Both, 30);

        // alice renews her ID and updates the hashes
        bytes32 newFront = sha256("new front");
        bytes32 newBack = sha256("new back");
        vm.prank(alice);
        identity.updateDocument("vault://alice", newFront, newBack);

        vm.prank(doctor);
        assertTrue(sharing.requestAccess(alice));
        (, bytes32 front, , , ) = identity.getUser(alice);
        assertEq(front, newFront);
    }
}
