// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../contracts/AccessToken.sol";
import "../contracts/DigitalIdentity.sol";
import "../contracts/ConsentManager.sol";
import "../contracts/DataSharing.sol";

contract DataSharingTest is Test {
    AccessToken token;
    DigitalIdentity identity;
    ConsentManager consent;
    DataSharing sharing;

    address patient;
    address doctor;
    address stranger;

    function setUp() public {
        patient = makeAddr("patient");
        doctor = makeAddr("doctor");
        stranger = makeAddr("stranger");

        token = new AccessToken();
        identity = new DigitalIdentity();
        consent = new ConsentManager(address(identity), address(token));
        sharing = new DataSharing(address(identity), address(consent));
        token.setMinter(address(consent));

        identity.approveRequester(doctor);
        // sha256 is a precompile call, so compute it before vm.prank
        bytes32 front = sha256("front");
        bytes32 back = sha256("back");
        vm.prank(patient);
        identity.registerUser(keccak256("email"), "vault://patient", front, back);
    }

    function _grant(ConsentManager.Scope _scope, uint256 _days) internal {
        vm.prank(patient);
        consent.grantConsent(doctor, _scope, _days);
    }

    function _request(address _requester) internal returns (bool) {
        vm.prank(_requester);
        return sharing.requestAccess(patient);
    }

    // --- Granted ------------------------------------------------------

    function test_GrantedWithValidConsent() public {
        _grant(ConsentManager.Scope.Both, 30);

        assertTrue(_request(doctor));

        DataSharing.AccessLog memory log = sharing.getLog(patient, 0);
        assertEq(log.requester, doctor);
        assertEq(uint(log.result), uint(DataSharing.Result.Granted));
        assertEq(uint(log.reason), uint(DataSharing.Reason.None));
        assertEq(uint(log.scope), uint(ConsentManager.Scope.Both));
        assertEq(uint256(log.timestamp), block.timestamp);
    }

    function test_EmitsAccessGranted() public {
        _grant(ConsentManager.Scope.FrontOnly, 30);

        vm.expectEmit(true, true, true, true, address(sharing));
        emit DataSharing.AccessGranted(patient, doctor, uint8(ConsentManager.Scope.FrontOnly), 0);
        _request(doctor);
    }

    // --- Denied (must not revert, must be logged) ----------------------

    function test_DeniedWithoutConsent() public {
        vm.expectEmit(true, true, true, true, address(sharing));
        emit DataSharing.AccessDenied(patient, doctor, DataSharing.Reason.NoConsent, 0);

        assertFalse(_request(doctor));

        DataSharing.AccessLog memory log = sharing.getLog(patient, 0);
        assertEq(uint(log.result), uint(DataSharing.Result.Denied));
        assertEq(uint(log.reason), uint(DataSharing.Reason.NoConsent));
    }

    function test_DeniedWhenRevoked() public {
        _grant(ConsentManager.Scope.Both, 30);
        vm.prank(patient);
        consent.revokeConsent(doctor);

        assertFalse(_request(doctor));
        assertEq(uint(sharing.getLog(patient, 0).reason), uint(DataSharing.Reason.Revoked));
    }

    function test_DeniedWhenExpired() public {
        _grant(ConsentManager.Scope.Both, 7);
        vm.warp(block.timestamp + 7 days);

        assertFalse(_request(doctor));
        assertEq(uint(sharing.getLog(patient, 0).reason), uint(DataSharing.Reason.Expired));
    }

    function test_DeniedWhenRequesterNotApproved() public {
        assertFalse(_request(stranger));
        DataSharing.AccessLog memory log = sharing.getLog(patient, 0);
        assertEq(log.requester, stranger);
        assertEq(uint(log.reason), uint(DataSharing.Reason.NotApproved));
    }

    function test_DeniedAfterRequesterRemoved() public {
        _grant(ConsentManager.Scope.Both, 30);
        identity.removeRequester(doctor);

        assertFalse(_request(doctor));
        assertEq(uint(sharing.getLog(patient, 0).reason), uint(DataSharing.Reason.NotApproved));
    }

    function test_RevertsForUnregisteredPatient() public {
        vm.prank(doctor);
        vm.expectRevert("Patient not registered");
        sharing.requestAccess(makeAddr("nobody"));
    }

    // --- Audit log ----------------------------------------------------

    function test_LogKeepsEveryAttemptInOrder() public {
        _request(doctor);                        // denied, no consent
        _grant(ConsentManager.Scope.Both, 30);
        _request(doctor);                        // granted
        _request(stranger);                      // denied, not approved

        assertEq(sharing.getLogCount(patient), 3);

        DataSharing.AccessLog[] memory logs = sharing.getLogs(patient);
        assertEq(uint(logs[0].result), uint(DataSharing.Result.Denied));
        assertEq(uint(logs[1].result), uint(DataSharing.Result.Granted));
        assertEq(logs[2].requester, stranger);
    }

    function test_RevertsGetLogWithInvalidIndex() public {
        vm.expectRevert("Invalid index");
        sharing.getLog(patient, 0);
    }

    function test_NoTokensMoveDuringAccess() public {
        _grant(ConsentManager.Scope.Both, 30);
        uint256 supplyBefore = token.totalSupply();
        uint256 patientBefore = token.balanceOf(patient);

        _request(doctor);
        _request(doctor);

        assertEq(token.totalSupply(), supplyBefore);
        assertEq(token.balanceOf(patient), patientBefore);
        assertEq(token.balanceOf(doctor), 0);
    }

    // --- Pause --------------------------------------------------------

    function test_PauseBlocksRequests() public {
        sharing.pause();
        vm.prank(doctor);
        vm.expectRevert("Contract is paused");
        sharing.requestAccess(patient);

        sharing.unpause();
        _request(doctor);
        assertEq(sharing.getLogCount(patient), 1);
    }

    function test_RevertsWhenNonOwnerPauses() public {
        vm.prank(doctor);
        vm.expectRevert("Not the owner");
        sharing.pause();
    }
}
