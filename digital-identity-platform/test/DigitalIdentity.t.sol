// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../contracts/DigitalIdentity.sol";

contract DigitalIdentityTest is Test {
    DigitalIdentity identity;
    address admin;
    address patient;
    address doctor;

    // fake hashes, no real data
    bytes32 emailHash = keccak256("salt+patient@example.test");
    bytes32 frontHash = sha256("front");
    bytes32 backHash = sha256("back");

    function setUp() public {
        admin = address(this);
        patient = makeAddr("patient");
        doctor = makeAddr("doctor");
        identity = new DigitalIdentity();
    }

    function _register() internal {
        vm.prank(patient);
        identity.registerUser(emailHash, "vault://patient", frontHash, backHash);
    }

    // --- Registration -------------------------------------------------

    function test_RegistersUser() public {
        _register();

        assertTrue(identity.isRegistered(patient));
        assertEq(identity.userCount(), 1);

        (bytes32 e, bytes32 f, bytes32 b, string memory ref, uint256 registeredAt) = identity.getUser(patient);
        assertEq(e, emailHash);
        assertEq(f, frontHash);
        assertEq(b, backHash);
        assertEq(ref, "vault://patient");
        assertEq(registeredAt, block.timestamp);
    }

    function test_EmitsUserRegistered() public {
        vm.expectEmit(true, true, true, true, address(identity));
        emit DigitalIdentity.UserRegistered(patient, emailHash);
        _register();
    }

    function test_RevertsDoubleRegistration() public {
        _register();
        vm.prank(patient);
        vm.expectRevert("Already registered");
        identity.registerUser(emailHash, "vault://patient", frontHash, backHash);
    }

    function test_RevertsEmptyEmailHash() public {
        vm.prank(patient);
        vm.expectRevert("Email hash required");
        identity.registerUser(bytes32(0), "vault://patient", frontHash, backHash);
    }

    function test_RevertsEmptyStorageRef() public {
        vm.prank(patient);
        vm.expectRevert("Storage reference required");
        identity.registerUser(emailHash, "", frontHash, backHash);
    }

    function test_RevertsEmptyDocumentHash() public {
        vm.prank(patient);
        vm.expectRevert("Document hashes required");
        identity.registerUser(emailHash, "vault://patient", frontHash, bytes32(0));
    }

    function test_RevertsRequesterRegisteringAsPatient() public {
        identity.approveRequester(doctor);
        vm.prank(doctor);
        vm.expectRevert("Requesters cannot register as patient");
        identity.registerUser(emailHash, "vault://doctor", frontHash, backHash);
    }

    function test_RevertsGetUserWhenNotRegistered() public {
        vm.expectRevert("User not registered");
        identity.getUser(patient);
    }

    // --- Update document ----------------------------------------------

    function test_UpdatesDocument() public {
        _register();
        bytes32 newFront = sha256("new front");
        bytes32 newBack = sha256("new back");

        vm.prank(patient);
        identity.updateDocument("vault://patient-v2", newFront, newBack);

        (, bytes32 f, bytes32 b, string memory ref, ) = identity.getUser(patient);
        assertEq(f, newFront);
        assertEq(b, newBack);
        assertEq(ref, "vault://patient-v2");
    }

    function test_RevertsUpdateWhenNotRegistered() public {
        vm.prank(patient);
        vm.expectRevert("Not registered");
        identity.updateDocument("vault://patient", frontHash, backHash);
    }

    // --- Requesters ---------------------------------------------------

    function test_AdminApprovesRequester() public {
        vm.expectEmit(true, true, true, true, address(identity));
        emit DigitalIdentity.RequesterApproved(doctor);
        identity.approveRequester(doctor);

        assertTrue(identity.isApprovedRequester(doctor));
    }

    function test_RevertsWhenNonAdminApproves() public {
        vm.prank(patient);
        vm.expectRevert("Not the owner");
        identity.approveRequester(doctor);
    }

    function test_RevertsApprovingAPatient() public {
        _register();
        vm.expectRevert("Address is a patient");
        identity.approveRequester(patient);
    }

    function test_RevertsApprovingTwice() public {
        identity.approveRequester(doctor);
        vm.expectRevert("Already approved");
        identity.approveRequester(doctor);
    }

    function test_RemovesRequester() public {
        identity.approveRequester(doctor);
        identity.removeRequester(doctor);
        assertFalse(identity.isApprovedRequester(doctor));
    }

    function test_RevertsRemovingUnknownRequester() public {
        vm.expectRevert("Not an approved requester");
        identity.removeRequester(doctor);
    }
}
