// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title squeek (SQUEEK)
/// @notice Fixed-supply ERC-20. X: @squeekchain, website: squeekchain.com.
/// @dev The whole supply is minted once to the deployer (the launch factory). No owner, no mint,
/// no pause, no fees: plain ERC-20 transfers only.
contract SqueekToken {
    string public constant name = "squeek";
    string public constant symbol = "SQUEEK";
    uint8 public constant decimals = 18;
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    error InvalidReceiver(address receiver);
    error InvalidSpender(address spender);
    error InsufficientBalance(address sender, uint256 balance, uint256 needed);
    error InsufficientAllowance(address spender, uint256 allowance, uint256 needed);

    constructor() {
        totalSupply = TOTAL_SUPPLY;
        balanceOf[msg.sender] = TOTAL_SUPPLY;
        emit Transfer(address(0), msg.sender, TOTAL_SUPPLY);
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function approve(address spender, uint256 value) external returns (bool) {
        if (spender == address(0)) revert InvalidSpender(spender);
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        uint256 current = allowance[from][msg.sender];
        if (current != type(uint256).max) {
            if (current < value) revert InsufficientAllowance(msg.sender, current, value);
            unchecked {
                allowance[from][msg.sender] = current - value;
            }
        }
        _transfer(from, to, value);
        return true;
    }

    function _transfer(address from, address to, uint256 value) private {
        if (to == address(0)) revert InvalidReceiver(to);
        uint256 bal = balanceOf[from];
        if (bal < value) revert InsufficientBalance(from, bal, value);
        unchecked {
            balanceOf[from] = bal - value;
            balanceOf[to] += value;
        }
        emit Transfer(from, to, value);
    }
}
