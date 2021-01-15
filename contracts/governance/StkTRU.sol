// SPDX-License-Identifier: MIT 
pragma solidity ^0.6.10;

import {VoteToken} from "./VoteToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";

contract StkTRU is VoteToken {

    address public stakingContract;
    /**
     * @dev initialize trusttoken and give ownership to sender
     * This is necessary to set ownership for proxy
     */
    function initialize(address _stakingContract) public {
        require(!initalized, "already initialized");
        owner_ = msg.sender;
        initalized = true;
        stakingContract = _stakingContract;
    }

    /**
     * @dev Mint stkTRU token to an address
     * @param account The target address to mint stkTRU
     * @param amount The amount to mint
     */
    function mint(address account, uint256 amount) external onlyStakingContract {
        _mint(account, amount);
    }

    /**
     * @dev Burn stkTRU token from an address
     * @param account The target address to burn stkTRU
     * @param amount The amount to burn
     */
    function burn(address account, uint256 amount) external onlyStakingContract {
        _burn(account, amount);
    }

    function decimals() public override pure returns (uint8) {
        return 8;
    }

    function rounding() public pure returns (uint8) {
        return 8;
    }

    function name() public override pure returns (string memory) {
        return "Staked TRU";
    }

    function symbol() public override pure returns (string memory) {
        return "stkTRU";
    }

    modifier onlyStakingContract() {
        require(msg.sender == stakingContract,"only staking contract is allowed");
        _;
    }
}

interface IStkTRU {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function mint(address account, uint256 amount) external;
    function burn(address account, uint256 amount) external; 
}