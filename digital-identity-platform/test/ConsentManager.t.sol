// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../contracts/AccessToken.sol";
import "../contracts/DigitalIdentity.sol";
import "../contracts/ConsentManager.sol";

contract ConsentManagerTest is Test {
    AccessToken token;
    DigitalIdentity identity;
    ConsentManager consent;

    address patient;
    address doctor;
    address lab;

    function setUp() public {
        patient = makeAddr("patient");
        doctor = makeAddr("doctor");
        lab = makeAddr("lab");

        token = new AccessToken();
        identity = new DigitalIdentity();
        consent = new ConsentManager(address(identity), address(token));
        token.setMinter(address(consent));

        identity.approveRequester(doctor);
        identity.approveRequester(lab);

        // sha256 is a precompile call, so compute it before vm.prank
        bytes32 front = sha256("front");
        bytes32 back = sha256("back");
        vm.prank(patient);
        identity.registerUser(keccak256("email"), "vault://patient", front, back);
    }

    function _grant(address _requester, ConsentManager.Scope _scope, uint256 _days) internal {
        vm.prank(patient);
        consent.grantConsent(_requester, _scope, _days);
    }

    // --- Granting -----------------------------------------------------

    function test_GrantsConsent() public {
        _grant(doctor, ConsentManager.Scope.Both, 30);

        (ConsentManager.Scope scope, uint256 grantedAt, uint256 expiresAt, bool revoked, bool exists) =
            consent.getConsent(patient, doctor);
        assertEq(uint(scope), uint(ConsentManager.Scope.Both));
        assertEq(grantedAt, block.timestamp);
        assertEq(expiresAt, block.timestamp + 30 days);
        assertFalse(revoked);
        assertTrue(exists);
        assertTrue(consent.isConsentValid(patient, doctor));
    }

    function test_EmitsConsentGranted() public {
        vm.expectEmit(true, true, true, true, address(consent));
        emit ConsentManager.ConsentGranted(patient, doctor, ConsentManager.Scope.FrontOnly, block.timestamp + 7 days);
        _grant(doctor, ConsentManager.Scope.FrontOnly, 7);
    }

    function test_RevertsIfPatientNotRegistered() public {
        vm.prank(makeAddr("nobody"));
        vm.expectRevert("Not registered");
        consent.grantConsent(doctor, ConsentManager.Scope.Both, 30);
    }

    function test_RevertsIfRequesterNotApproved() public {
        vm.prank(patient);
        vm.expectRevert("Requester not approved");
        consent.grantConsent(makeAddr("random"), ConsentManager.Scope.Both, 30);
    }

    function test_RevertsOnZeroDays() public {
        vm.prank(patient);
        vm.expectRevert("Duration must be 1-365 days");
        consent.grantConsent(doctor, ConsentManager.Scope.Both, 0);
    }

    function test_RevertsOnMoreThan365Days() public {
        vm.prank(patient);
        vm.expectRevert("Duration must be 1-365 days");
        consent.grantConsent(doctor, ConsentManager.Scope.Both, 366);
    }

    function test_AcceptsBoundaryDurations() public {
        _grant(doctor, ConsentManager.Scope.Both, 1);
        _grant(lab, ConsentManager.Scope.Both, 365);
        assertTrue(consent.isConsentValid(patient, doctor));
        assertTrue(consent.isConsentValid(patient, lab));
    }

    function testFuzz_AnyDurationInRangeWorks(uint256 _days) public {
        _days = bound(_days, 1, 365);
        _grant(doctor, ConsentManager.Scope.Both, _days);
        (, , uint256 expiresAt, , ) = consent.getConsent(patient, doctor);
        assertEq(expiresAt, block.timestamp + _days * 1 days);
    }

    function test_GrantAgainReplacesConsent() public {
        _grant(doctor, ConsentManager.Scope.Both, 30);
        vm.prank(patient);
        consent.revokeConsent(doctor);

        vm.warp(block.timestamp + 1 days);
        _grant(doctor, ConsentManager.Scope.BackOnly, 10);

        (ConsentManager.Scope scope, , uint256 expiresAt, bool revoked, ) = consent.getConsent(patient, doctor);
        assertEq(uint(scope), uint(ConsentManager.Scope.BackOnly));
        assertEq(expiresAt, block.timestamp + 10 days);
        assertFalse(revoked);
        assertTrue(consent.isConsentValid(patient, doctor));
    }

    // --- Rewards ------------------------------------------------------

    function test_MintsRewardOnFirstGrant() public {
        _grant(doctor, ConsentManager.Scope.Both, 30);
        assertEq(token.balanceOf(patient), 10 ether);
        assertTrue(consent.rewarded(patient, doctor));
    }

    function test_NoSecondRewardForSameRequester() public {
        _grant(doctor, ConsentManager.Scope.Both, 30);
        vm.prank(patient);
        consent.revokeConsent(doctor);
        _grant(doctor, ConsentManager.Scope.Both, 30);
        _grant(doctor, ConsentManager.Scope.FrontOnly, 5);

        assertEq(token.balanceOf(patient), 10 ether);
    }

    function test_RewardForEachNewRequester() public {
        _grant(doctor, ConsentManager.Scope.Both, 30);
        _grant(lab, ConsentManager.Scope.FrontOnly, 30);
        assertEq(token.balanceOf(patient), 20 ether);
    }

    function test_OwnerChangesRewardAmount() public {
        consent.setRewardAmount(5 ether);
        _grant(doctor, ConsentManager.Scope.Both, 30);
        assertEq(token.balanceOf(patient), 5 ether);
    }

    function test_RevertsWhenNonOwnerChangesReward() public {
        vm.prank(patient);
        vm.expectRevert("Not the owner");
        consent.setRewardAmount(1000 ether);
    }

    // --- Revoking -----------------------------------------------------

    function test_RevokesConsent() public {
        _grant(doctor, ConsentManager.Scope.Both, 30);

        vm.expectEmit(true, true, true, true, address(consent));
        emit ConsentManager.ConsentRevoked(patient, doctor);
        vm.prank(patient);
        consent.revokeConsent(doctor);

        assertFalse(consent.isConsentValid(patient, doctor));
        (, , , bool revoked, ) = consent.getConsent(patient, doctor);
        assertTrue(revoked);
    }

    function test_RevertsRevokeWithoutConsent() public {
        vm.prank(patient);
        vm.expectRevert("No consent found");
        consent.revokeConsent(doctor);
    }

    function test_RevertsRevokeTwice() public {
        _grant(doctor, ConsentManager.Scope.Both, 30);
        vm.startPrank(patient);
        consent.revokeConsent(doctor);
        vm.expectRevert("Already revoked");
        consent.revokeConsent(doctor);
        vm.stopPrank();
    }

    function test_RevertsRevokeAfterExpiry() public {
        _grant(doctor, ConsentManager.Scope.Both, 1);
        vm.warp(block.timestamp + 2 days);
        vm.prank(patient);
        vm.expectRevert("Consent already expired");
        consent.revokeConsent(doctor);
    }

    function test_RequesterCannotRevokeForPatient() public {
        _grant(doctor, ConsentManager.Scope.Both, 30);
        // revoke only looks at consents given by msg.sender, the doctor has none
        vm.prank(doctor);
        vm.expectRevert("No consent found");
        consent.revokeConsent(patient);
        assertTrue(consent.isConsentValid(patient, doctor));
    }

    // --- Expiry -------------------------------------------------------

    function test_ConsentExpiresExactlyAtExpiresAt() public {
        _grant(doctor, ConsentManager.Scope.Both, 7);
        (, , uint256 expiresAt, , ) = consent.getConsent(patient, doctor);

        vm.warp(expiresAt - 1);
        assertTrue(consent.isConsentValid(patient, doctor));

        vm.warp(expiresAt);
        assertFalse(consent.isConsentValid(patient, doctor));
    }

    function test_NoConsentIsNotValid() public view {
        assertFalse(consent.isConsentValid(patient, doctor));
    }
}
