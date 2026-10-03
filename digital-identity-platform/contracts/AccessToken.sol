// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title AccessToken
 * @dev ERC-20 reward token (ACT). Patients get it when they grant consent.
 *      Only the minter (the ConsentManager contract) can create new tokens.
 *      Holding tokens does not give access to any data.
 */
contract AccessToken {
    string public name = "Access Token";
    string public symbol = "ACT";
    uint8 public decimals = 18;
    uint256 public totalSupply;

    address public owner;
    address public minter;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event MinterChanged(address indexed newMinter);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not the owner");
        _;
    }

    modifier onlyMinter() {
        require(msg.sender == minter, "Not the minter");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    /**
     * @dev Makes ConsentManager the only minter. Can only be called once, so
     *      the owner can't later switch the minter to their own wallet and mint
     *      unlimited tokens. It's not a constructor argument because
     *      ConsentManager needs this contract's address when it's deployed.
     */
    function setMinter(address _minter) public onlyOwner {
        require(minter == address(0), "Minter already set");
        require(_minter != address(0), "Invalid minter");
        minter = _minter;
        emit MinterChanged(_minter);
    }

    function mint(address _to, uint256 _amount) public onlyMinter {
        require(_to != address(0), "Mint to zero address");

        totalSupply += _amount;
        balanceOf[_to] += _amount;

        emit Transfer(address(0), _to, _amount);
    }

    function transfer(address _to, uint256 _amount) public returns (bool) {
        require(_to != address(0), "Transfer to zero address");
        require(balanceOf[msg.sender] >= _amount, "Insufficient balance");

        balanceOf[msg.sender] -= _amount;
        balanceOf[_to] += _amount;

        emit Transfer(msg.sender, _to, _amount);
        return true;
    }

    function approve(address _spender, uint256 _amount) public returns (bool) {
        require(_spender != address(0), "Approve to zero address");

        allowance[msg.sender][_spender] = _amount;

        emit Approval(msg.sender, _spender, _amount);
        return true;
    }

    function transferFrom(address _from, address _to, uint256 _amount) public returns (bool) {
        require(_to != address(0), "Transfer to zero address");
        require(balanceOf[_from] >= _amount, "Insufficient balance");
        require(allowance[_from][msg.sender] >= _amount, "Insufficient allowance");

        balanceOf[_from] -= _amount;
        balanceOf[_to] += _amount;
        allowance[_from][msg.sender] -= _amount;

        emit Transfer(_from, _to, _amount);
        return true;
    }
}
