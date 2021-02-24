// SPDX-License-Identifier: MIT
pragma solidity 0.6.10;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";

import {Initializable} from "./common/Initializable.sol";
import {ITrueDistributor} from "./interface/ITrueDistributor.sol";
import {ITrueFarm} from "./interface/ITrueFarm.sol";
import {IMasterChef} from "./interface/IMasterChef.sol";

/**
 * @title TrueSushiFarm
 * @notice Deposit liquidity tokens to earn TRU and SUSHI rewards over time
 * @dev Staking pool where tokens are staked for TRU rewards
 * A Distributor contract decides how much TRU a farm can earn over time
 */
contract TrueSushiFarm is ITrueFarm, Initializable {
    using SafeMath for uint256;
    uint256 constant PRECISION = 1e30;

    struct Rewards {
        // track overall cumulative rewards
        uint256 cumulativeRewardPerToken;
        // track previous cumulate rewards for accounts
        mapping(address => uint256) previousCumulatedRewardPerToken;
        // track claimable rewards for accounts
        mapping(address => uint256) claimableReward;
        // track total rewards
        uint256 totalClaimedRewards;
        uint256 totalFarmRewards;
    }

    // ================ WARNING ==================
    // ===== THIS CONTRACT IS INITIALIZABLE ======
    // === STORAGE VARIABLES ARE DECLARED BELOW ==
    // REMOVAL OR REORDER OF VARIABLES WILL RESULT
    // ========= IN STORAGE CORRUPTION ===========

    IERC20 public override stakingToken;
    IERC20 public override trustToken;
    IERC20 public sushi;
    IMasterChef public masterChef;
    ITrueDistributor public override trueDistributor;
    string public override name;

    // track stakes
    uint256 public override totalStaked;
    mapping(address => uint256) public staked;
    mapping(IERC20 => Rewards) public rewards;


    // ======= STORAGE DECLARATION END ============

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

    /**
     * @dev Initalize staking pool with a Distributor contract
     * The distributor contract calculates how much TRU rewards this contract
     * gets, and stores TRU for distribution.
     * @param _stakingToken Token to stake
     * @param _trueDistributor Distributor contract
     * @param _name Farm name
     */
    function initialize(
        IERC20 _stakingToken,
        IERC20 _sushi,
        IMasterChef _masterChef,
        ITrueDistributor _trueDistributor,
        string memory _name
    ) public initializer {
        stakingToken = _stakingToken;
        sushi = _sushi;
        masterChef = _masterChef;
        trueDistributor = _trueDistributor;
        trustToken = _trueDistributor.trustToken();
        name = _name;
        require(trueDistributor.farm() == address(this), "TrueFarm: Distributor farm is not set");
        rewards[trustToken] = Rewards({
            cumulativeRewardPerToken: 0,
            totalClaimedRewards: 0,
            totalFarmRewards: 0
        });
        rewards[sushi] = Rewards({
            cumulativeRewardPerToken: 0,
            totalClaimedRewards: 0,
            totalFarmRewards: 0
        });
    }

    /**
     * @dev Stake tokens for TRU rewards.
     * Also claims any existing rewards.
     * @param amount Amount of tokens to stake
     */
    function stake(uint256 amount) external override update(trustToken) update(sushi) {
        if (rewards[trustToken].claimableReward[msg.sender] > 0) {
            _claim(trustToken);
        }
        if (rewards[sushi].claimableReward[msg.sender] > 0) {
            _claim(sushi);
        }
        staked[msg.sender] = staked[msg.sender].add(amount);
        totalStaked = totalStaked.add(amount);

        require(stakingToken.transferFrom(msg.sender, address(this), amount));
        stakingToken.approve(address(masterChef), amount);
        masterChef.deposit(SUSHI_POOL_ID, amount);

        emit Stake(msg.sender, amount);
    }

    /**
     * @dev Internal unstake function
     * @param amount Amount of tokens to unstake
     */
    function _unstake(uint256 amount) internal {
        require(amount <= staked[msg.sender], "TrueFarm: Cannot withdraw amount bigger than available balance");
        staked[msg.sender] = staked[msg.sender].sub(amount);
        totalStaked = totalStaked.sub(amount);

        masterChef.withdraw(SUSHI_POOL_ID, amount);
        require(stakingToken.transfer(msg.sender, amount));
        
        emit Unstake(msg.sender, amount);
    }

    /**
     * @dev Internal claim function
     */
    function _claim(IERC20 token) internal {
        rewards[token].totalClaimedRewards = rewards[token].totalClaimedRewards.add(rewards[token].claimableReward[msg.sender]);
        uint256 rewardToClaim = rewards[token].claimableReward[msg.sender];
        rewards[token].claimableReward[msg.sender] = 0;
        require(token.transfer(msg.sender, rewardToClaim));
        emit Claim(msg.sender, rewardToClaim);
    }

    /**
     * @dev Remove staked tokens
     * @param amount Amount of tokens to unstake
     */
    function unstake(uint256 amount) external override update(trustToken) update(sushi) {
        _unstake(amount);
    }

    /**
     * @dev Claim TRU & SUSHI rewards
     */
    function claim() external override update(trustToken) update(sushi) {
        _claim(trustToken);
        _claim(sushi);
    }

    /**
     * @dev Claim rewards of choice
     */
    function claim(IERC20 token) external update(trustToken) update(sushi) {
        _claim(token);
    }

    /**
     * @dev Unstake amount and claim rewards
     * @param amount Amount of tokens to unstake
     */
    function exit(uint256 amount) external override update(trustToken) update(sushi) {
        _unstake(amount);
        _claim(trustToken);
        _claim(sushi);
    }

    /**
     * @dev View to estimate the claimable reward for an account
     * @return claimable rewards for account
     */
    function claimable(address account, IERC20 token) external view returns (uint256) {
        if (staked[account] == 0) {
            return rewards[token].claimableReward[account];
        }
        // estimate pending reward from distributor
        uint256 pending = trueDistributor.nextDistribution();
        // calculate total rewards (including pending)
        uint256 newTotalFarmRewards = trustToken.balanceOf(address(this)).add(pending).add(rewards[token].totalClaimedRewards).mul(PRECISION);
        // calculate block reward
        uint256 totalBlockReward = newTotalFarmRewards.sub(rewards[token].totalFarmRewards);
        // calculate next cumulative reward per token
        uint256 nextcumulativeRewardPerToken = rewards[token].cumulativeRewardPerToken.add(totalBlockReward.div(totalStaked));
        // return claimable reward for this account
        // prettier-ignore
        return rewards[token].claimableReward[account].add(
            staked[account].mul(nextcumulativeRewardPerToken.sub(rewards[token].previousCumulatedRewardPerToken[account])).div(PRECISION));
    }

    /**
     * @dev Update state and get TRU from distributor
     */
    modifier update(IERC20 token) {
        // pull TRU from distributor
        // only pull if there is distribution and distributor farm is set to this farm
        if (token == trustToken && trueDistributor.nextDistribution() > 0 && trueDistributor.farm() == address(this)) {
            trueDistributor.distribute();
        }
        // calculate total rewards
        uint256 newTotalFarmRewards = trustToken.balanceOf(address(this)).add(rewards[token].totalClaimedRewards).mul(PRECISION);
        // calculate block reward
        uint256 totalBlockReward = newTotalFarmRewards.sub(rewards[token].totalFarmRewards);
        // update farm rewards
        rewards[token].totalFarmRewards = newTotalFarmRewards;
        // if there are stakers
        if (totalStaked > 0) {
            rewards[token].cumulativeRewardPerToken = rewards[token].cumulativeRewardPerToken.add(totalBlockReward.div(totalStaked));
        }
        // update claimable reward for sender
        rewards[token].claimableReward[msg.sender] = rewards[token].claimableReward[msg.sender].add(
            staked[msg.sender].mul(rewards[token].cumulativeRewardPerToken.sub(rewards[token].previousCumulatedRewardPerToken[msg.sender])).div(PRECISION)
        );
        // update previous cumulative for sender
        rewards[token].previousCumulatedRewardPerToken[msg.sender] = rewards[token].cumulativeRewardPerToken;
        _;
    }
}
