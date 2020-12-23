// SPDX-License-Identifier: MIT 
pragma solidity ^0.6.10;

import {VoteToken} from "./VoteToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";

contract VeTRU is VoteToken {
    mapping(address=>bool) whitelisted;

    /**
     * @dev Modifier to check whitelist address
     */
    modifier onlyWhitelisted {
        require(whitelisted[msg.sender], "sender not whiteslited");
        _;
    }

    /**
     * @dev Add or remove an address to whitelist
     * @param account The target address to add or remove from whitelist
     * @param status A boolean status of add or remove from whitelist
     */
    function whitelist(address account, bool status) external onlyOwner {
        whitelisted[account] = status;
    }

    /**
     * @dev Mint veTRU token to an address
     * @param account The target address to mint veTRU
     * @param amount The amount to mint
     */
    function mint(address account, uint256 amount) external onlyWhitelisted {
        _mint(account, amount);
    }

    /**
     * @dev Burn veTRU token from an address
     * @param account The target address to burn veTRU
     * @param amount The amount to burn
     */
    function burn(address account, uint256 amount) external onlyWhitelisted {
        _burn(account, amount);
    }

    /**
     * @dev Transfer function for veTRU 
     */
    function _transfer() public pure {
        // can user call _transfer(addr, addr, amount) from parent contract?
        revert("veTRU is non-transferrable");
    }

    function decimals() public override pure returns (uint8) {
        return 8;
    }

    function rounding() public pure returns (uint8) {
        return 8;
    }

    function name() public override pure returns (string memory) {
        return "VeTRU";
    }

    function symbol() public override pure returns (string memory) {
        return "VeTRU";
    }
}

interface IVeTRU {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function mint(address account, uint256 amount) external;
    function burn(address account, uint256 amount) external; 
}