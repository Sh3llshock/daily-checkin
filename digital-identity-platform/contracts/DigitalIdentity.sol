// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title DigitalIdentity
 * @dev Registers patients and approved requesters (healthcare providers).
 *      Only hashes and a storage reference are kept on-chain. The ID photos
 *      and the personal details stay off-chain with the patient.
 */
contract DigitalIdentity {
    struct User {
        bytes32 emailHash;   // keccak256(salt, email), salt stays with the patient
        bytes32 frontHash;   // sha256 of the front photo of the ID
        bytes32 backHash;    // sha256 of the back photo of the ID
        string storageRef;   // where the patient's vault can be reached
        uint64 registeredAt; // uint64 + bool share one storage slot
        bool registered;
    }

    // State variables
    address public owner;
    uint256 public userCount;
    mapping(address => User) private users;
    mapping(address => bool) public isApprovedRequester;

    // Events
    event UserRegistered(address indexed user, bytes32 emailHash);
    event DocumentUpdated(address indexed user);
    event RequesterApproved(address indexed requester);
    event RequesterRemoved(address indexed requester);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not the owner");
        _;
    }

    modifier onlyRegistered() {
        require(users[msg.sender].registered, "Not registered");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    /**
     * @dev Register the caller as a patient
     * @param _emailHash salted hash of the email
     * @param _storageRef reference to the off-chain vault
     * @param _frontHash sha256 of the front photo
     * @param _backHash sha256 of the back photo
     */
    function registerUser(
        bytes32 _emailHash,
        string calldata _storageRef,
        bytes32 _frontHash,
        bytes32 _backHash
    ) external {
        require(!users[msg.sender].registered, "Already registered");
        require(!isApprovedRequester[msg.sender], "Requesters cannot register as patient");
        require(_emailHash != bytes32(0), "Email hash required");
        require(bytes(_storageRef).length > 0, "Storage reference required");
        require(_frontHash != bytes32(0) && _backHash != bytes32(0), "Document hashes required");

        users[msg.sender] = User({
            emailHash: _emailHash,
            frontHash: _frontHash,
            backHash: _backHash,
            storageRef: _storageRef,
            registeredAt: uint64(block.timestamp),
            registered: true
        });
        userCount++;

        emit UserRegistered(msg.sender, _emailHash);
    }

    /**
     * @dev Update the document hashes, e.g. after the ID was renewed
     */
    function updateDocument(
        string calldata _storageRef,
        bytes32 _frontHash,
        bytes32 _backHash
    ) external onlyRegistered {
        require(bytes(_storageRef).length > 0, "Storage reference required");
        require(_frontHash != bytes32(0) && _backHash != bytes32(0), "Document hashes required");

        User storage u = users[msg.sender];
        u.storageRef = _storageRef;
        u.frontHash = _frontHash;
        u.backHash = _backHash;

        emit DocumentUpdated(msg.sender);
    }

    /**
     * @dev Admin approves a healthcare provider as requester
     */
    function approveRequester(address _requester) external onlyOwner {
        require(_requester != address(0), "Invalid address");
        require(!users[_requester].registered, "Address is a patient");
        require(!isApprovedRequester[_requester], "Already approved");

        isApprovedRequester[_requester] = true;
        emit RequesterApproved(_requester);
    }

    function removeRequester(address _requester) external onlyOwner {
        require(isApprovedRequester[_requester], "Not an approved requester");

        isApprovedRequester[_requester] = false;
        emit RequesterRemoved(_requester);
    }

    function isRegistered(address _user) external view returns (bool) {
        return users[_user].registered;
    }

    /**
     * @dev Returns the stored hashes and reference of a patient
     */
    function getUser(address _user) external view returns (
        bytes32 emailHash,
        bytes32 frontHash,
        bytes32 backHash,
        string memory storageRef,
        uint256 registeredAt
    ) {
        require(users[_user].registered, "User not registered");
        User memory u = users[_user];
        return (u.emailHash, u.frontHash, u.backHash, u.storageRef, u.registeredAt);
    }
}
