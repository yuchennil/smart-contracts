// SPDX-License-Identifier: MIT 
pragma solidity ^0.6.10;

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVeTRU} from "./VeTRU.sol";
import {ITrueDistributor} from "../truefi/interface/ITrueDistributor.sol";
import {ClaimableContract} from "./common/ClaimableContract.sol";

contract TrueFiStaking is ClaimableContract {
    using SafeMath for uint256;
    uint256 constant PRECISION = 100000000;
    IVeTRU public veTru;
    IERC20 public tru;
    ITrueDistributor public trueDistributor;

    /**
     * @dev Emitted when an account stakes
     * @param who Account staking
     * @param amountStaked Amount of tokens staked
     */
    event Stake(address indexed who, uint256 amountStaked);

    /**
     * @dev Emitted when an account unstakes
     * @param who Account unstaking
     * @param amountUnstaked Amount of tokens unstaked
     */
    event Unstake(address indexed who, uint256 amountUnstaked);

    /**
     * @dev Emitted when an account claims TRU rewards
     * @param who Account claiming
     * @param amountClaimed Amount of TRU claimed
     */
    event Claim(address indexed who, uint256 amountClaimed);
    

    // track total stakes
    uint256 public totalStaked;
    // track stakes for each account
    mapping(address => uint256) public staked;
    // track overall cumulative rewards
    uint256 public cumulativeRewardPerToken;
    // track previous cumulate rewards for accounts
    mapping(address => uint256) public previousCumulatedRewardPerToken;
    // track claimable rewards for accounts
    mapping(address => uint256) public claimableReward;
    // track total claimed rewards
    uint256 public totalClaimedRewards;
    // track total farm rewards
    uint256 public totalFarmRewards;

    /**
     * @dev Initialize sets the addresses of admin and the delay timestamp
     * @param veTru_ The address of veTRU contract
     * @param tru_ The address of TRU contract
     */
    function initialize(address veTru_, address tru_, address _trueDistributor) external {
        require(!initalized, "Already initialized");

        veTru = IVeTRU(veTru_);
        tru = IERC20(tru_);
        trueDistributor = ITrueDistributor(_trueDistributor);

        owner_ = msg.sender;
        initalized = true;

        require(trueDistributor.farm() == address(this), "TrueFarm: Distributor farm is not set");
    }

    /**
     * @dev Stake TRU and mint veTRU
     * @param account The target address to stake and mint veTRU
     * @param amount The amount to stake and mint 
     */
    function stake(address account, uint256 amount) public update {
        require(tru.transferFrom(account, address(this), amount));
        veTru.mint(account, amount);
        emit Stake(account, amount);
    }

    /**
     * @dev Unstake TRU and burn veTRU
     * @param account The target address to unstake and burn veTRU
     * @param amount The amount to unstake and burn
     */
    function unstake(address account, uint256 amount) public update {
        veTru.burn(account, amount);
        require(tru.transfer(account, amount));
        emit Unstake(account, amount);
    }   

    /**
     * @dev Claim reward function
     */
    function claim() public update {
        totalClaimedRewards = totalClaimedRewards.add(claimableReward[msg.sender]);
        uint256 rewardToClaim = claimableReward[msg.sender];
        claimableReward[msg.sender] = 0;
        require(tru.transfer(msg.sender, rewardToClaim));
        emit Claim(msg.sender, rewardToClaim);
    }

    modifier update() {
        // pull TRU from distributor
        // only pull if there is distribution and distributor farm is set to this farm
        if (trueDistributor.nextDistribution() > 0 && trueDistributor.farm() == address(this)) {
            trueDistributor.distribute();
        }
        // calculate total rewards
        uint256 newTotalFarmRewards = tru.balanceOf(address(this)).add(totalClaimedRewards).mul(PRECISION);
        // calculate block reward
        uint256 totalBlockReward = newTotalFarmRewards.sub(totalFarmRewards);
        // update farm rewards
        totalFarmRewards = newTotalFarmRewards;
        // if there are stakers
        if (totalStaked > 0) {
            cumulativeRewardPerToken = cumulativeRewardPerToken.add(totalBlockReward.div(totalStaked));
        }
        // update claimable reward for sender
        claimableReward[msg.sender] = claimableReward[msg.sender].add(
            staked[msg.sender].mul(cumulativeRewardPerToken.sub(previousCumulatedRewardPerToken[msg.sender])).div(PRECISION)
        );
        // update previous cumulative for sender
        previousCumulatedRewardPerToken[msg.sender] = cumulativeRewardPerToken;
        _;
    }
}




contract VoteBoostWithTime is TrueFiStaking{

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







