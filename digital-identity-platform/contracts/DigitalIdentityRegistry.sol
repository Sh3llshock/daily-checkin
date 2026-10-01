// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

/// @title DigitalIdentityRegistry
/// @notice Stores only the minimal reference data needed to verify a
/// government ID: a hash of the user's email (for uniqueness, not identity),
/// an off-chain document link (e.g. link.com/george), and SHA-256 hashes of
/// the front/back ID images. Raw personal data and the images themselves are
/// never stored on-chain.
contract DigitalIdentityRegistry is Ownable {
    /// @dev There is no separate `registered` flag: registerUser rejects a zero
    /// emailHash, so `emailHash != 0` holds exactly for registered users. That
    /// saves one zero-to-non-zero SSTORE per registration (TASKS A4).
    struct Identity {
        bytes32 emailHash;
        string documentLink;
        bytes32 frontHash;
        bytes32 backHash;
    }

    mapping(address => Identity) private identities;
    mapping(bytes32 => bool) private usedEmailHashes;
    mapping(address => bool) public approvedRequesters;

    event UserRegistered(address indexed user, bytes32 emailHash, string documentLink);
    event DocumentUpdated(address indexed user, string newLink);
    event RequesterStatusChanged(address indexed requester, bool approved);

    constructor() Ownable(msg.sender) {}

    modifier onlyRegistered() {
        require(identities[msg.sender].emailHash != bytes32(0), "DigitalIdentityRegistry: not registered");
        _;
    }

    /// @notice Register a new user with minimal hashed/reference data.
    function registerUser(
        bytes32 emailHash,
        string calldata documentLink,
        bytes32 frontHash,
        bytes32 backHash
    ) external {
        require(identities[msg.sender].emailHash == bytes32(0), "DigitalIdentityRegistry: already registered");
        require(emailHash != bytes32(0), "DigitalIdentityRegistry: empty email hash");
        require(bytes(documentLink).length > 0, "DigitalIdentityRegistry: empty link");
        require(frontHash != bytes32(0) && backHash != bytes32(0), "DigitalIdentityRegistry: empty image hash");
        require(!usedEmailHashes[emailHash], "DigitalIdentityRegistry: email already used");

        identities[msg.sender] = Identity({
            emailHash: emailHash,
            documentLink: documentLink,
            frontHash: frontHash,
            backHash: backHash
        });
        usedEmailHashes[emailHash] = true;

        emit UserRegistered(msg.sender, emailHash, documentLink);
    }

    /// @notice Update the document reference (e.g. renewed/re-uploaded ID)
    /// without re-registering the whole account.
    function updateDocument(
        string calldata newLink,
        bytes32 newFrontHash,
        bytes32 newBackHash
    ) external onlyRegistered {
        require(bytes(newLink).length > 0, "DigitalIdentityRegistry: empty link");
        require(newFrontHash != bytes32(0) && newBackHash != bytes32(0), "DigitalIdentityRegistry: empty image hash");

        Identity storage id = identities[msg.sender];
        id.documentLink = newLink;
        id.frontHash = newFrontHash;
        id.backHash = newBackHash;

        emit DocumentUpdated(msg.sender, newLink);
    }

    /// @notice Whitelist (or de-whitelist) a healthcare-provider address as a
    /// legitimate requester. Admin only -- the admin never touches consent or data.
    function setRequesterStatus(address requester, bool approved) external onlyOwner {
        approvedRequesters[requester] = approved;
        emit RequesterStatusChanged(requester, approved);
    }

    function isApprovedRequester(address requester) external view returns (bool) {
        return approvedRequesters[requester];
    }

    function isRegistered(address user) external view returns (bool) {
        return identities[user].emailHash != bytes32(0);
    }

    /// @notice Query a user's stored reference/hash data.
    function getUserRecord(address user)
        external
        view
        returns (bytes32 emailHash, string memory documentLink, bytes32 frontHash, bytes32 backHash, bool registered)
    {
        Identity storage id = identities[user];
        return (id.emailHash, id.documentLink, id.frontHash, id.backHash, id.emailHash != bytes32(0));
    }
}
