// SPDX-License-Identifier: MIT 
pragma solidity ^0.6.10;

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVeTRU} from "./VeTRU.sol";
import {ClaimableContract} from "./common/ClaimableContract.sol";

contract TrueFiStaking is ClaimableContract {
    using SafeMath for uint256;
    IVeTRU public veTru;
    IERC20 public tru;

    /**
     * @dev Initialize sets the addresses of admin and the delay timestamp
     * @param veTru_ The address of veTRU contract
     * @param tru_ The address of TRU contract
     */
    function initialize(address veTru_, address tru_) external {
        require(!initalized, "Already initialized");

        veTru = IVeTRU(veTru_);
        tru = IERC20(tru_);

        owner_ = msg.sender;
        initalized = true;
    }

    function claimTruReward(address account) public {
        uint256 totalTruSurplus = tru.balanceOf(address(this)).sub(veTru.totalSupply());
        require(totalTruSurplus > 0, "not enough TRU to distribute");
        uint256 amountToDistribute = totalTruSurplus.div(veTru.balanceOf(account));
        stake(account, amountToDistribute);
    }
    
    function claimProtocolFees(address account) public {
        //TODO
    }

    /**
     * @dev Stake TRU and mint veTRU
     * @param account The target address to stake and mint veTRU
     * @param amount The amount to stake and mint 
     */
    function stake(address account, uint256 amount) public {
        require(tru.transferFrom(account, address(this), amount));
        veTru.mint(account, amount);
    }

    /**
     * @dev Unstake TRU and burn veTRU
     * @param account The target address to unstake and burn veTRU
     * @param amount The amount to unstake and burn
     */
    function unstake(address account, uint256 amount) public {
        veTru.burn(account, amount);
        tru.transfer(account, amount);
    }   

    function claimTruReward() public {

    }
}

// TODO:
// Track stake for multiple trauches
// Track multiple stakes in multiple trauches
// add lockupTime to stake/unstake functions

contract VoteBoostWithTime is TrueFiStaking{

    uint256 staked;
    uint256 unlockTime;     
    uint256 constant PRECISION = 100000000;
    
    /**
     * @dev Stake with boost on veTRU based on locktime
     * @param account The target address to stake and mint veTRU
     * @param amount The amount to stake and mint
     * @param time The desired locktime for the account
     */
    function stakeWithBoost(address account, uint256 amount, uint256 time) external {
        uint256 boost = calculateBoost(time);
        uint256 amountToMint = boost.mul(amount).div(PRECISION);
        stake(account, amountToMint);
        //culmulativeVotingPower += amount * boost
        // 
    }

    /**
     * @dev Unstake with boost on veTRU based on locktime
     * @param account The target address to unstake and burn veTRU
     */
    function unstakeWithBoost(address account, uint256 amount) external {
        unstake(account, amount);
    }

    /**
     * @dev Calculate boost as a function of time
     * @param time The desired locktime
     */
    function calculateBoost(uint256 time) internal pure returns (uint256) {
        // boost for 3 months
        if (time >= 90 days) {
            return 100000000;
        }
        // boost for 1 years
        if (time >= 365 days) {
            return 150000000;
        }
        // boost for 4 years
        if (time >= 365*4 days) {
            return 200000000;
        }
    }
}







