// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IDigitalIdentity {
    function isRegistered(address user) external view returns (bool);
    function isApprovedRequester(address requester) external view returns (bool);
}
