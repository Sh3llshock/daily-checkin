// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IAccessToken {
    function mint(address to, uint256 amount) external;
}
