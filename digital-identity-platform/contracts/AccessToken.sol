// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title AccessToken (ACT)
/// @notice Pure incentive token. Minted only when a user grants consent.
/// Holding ACT never grants data access by itself -- access is decided
/// exclusively by ConsentManager/DataSharingManager, which never check
/// token balances.
contract AccessToken is ERC20, Ownable {
    address public minter;

    event MinterUpdated(address indexed newMinter);

    constructor() ERC20("Access Token", "ACT") Ownable(msg.sender) {}

    /// @notice Restrict minting to a single designated contract (ConsentManager).
    /// Only the platform owner can (re)point this, and only once at deployment
    /// under normal operation.
    function setMinter(address newMinter) external onlyOwner {
        require(newMinter != address(0), "AccessToken: zero minter");
        minter = newMinter;
        emit MinterUpdated(newMinter);
    }

    /// @notice Reward a user for granting consent. Callable only by the
    /// ConsentManager contract -- never by data access, never by an EOA.
    function mintReward(address user, uint256 amount) external {
        require(msg.sender == minter, "AccessToken: caller is not minter");
        _mint(user, amount);
    }
}
