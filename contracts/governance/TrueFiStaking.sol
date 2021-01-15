// SPDX-License-Identifier: MIT 
pragma solidity ^0.6.10;

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStkTRU} from "./StkTRU.sol";
import {ITrueDistributor} from "../truefi/interface/ITrueDistributor.sol";
import {ClaimableContract} from "./common/ClaimableContract.sol";
import {ITrueFiPool} from "../truefi/interface/ITrueFiPool.sol";
import {ILoanToken} from "../truefi/interface/ILoanToken.sol";
import {IUniswapRouter} from "../truefi/interface/IUniswapRouter.sol";


contract TrueFiStaking is ClaimableContract {
    using SafeMath for uint256;
    uint256 constant PRECISION = 100000000;
    IStkTRU public stkTRU;
    IERC20 public tru;
    ITrueDistributor public trueDistributor;
    ITrueFiPool public pool;
    IUniswapRouter public uniRouter;

    address public TUSD;
    address public WETH;
    address public TRU;

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
     * @dev Emitted when the staking pool get slashed
     * @param amountSlashed The amount that slashed
     */
    event Liquidation(uint256 amountSlashed);

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
    // the cool down period for unstake

    struct CoolDown {
        uint256 time;
        bool activated;     
    }
    uint256 public constant COOLDOWNPERIOD = 80640; // 14 days, assume 15sec per block
    // track the individual cool down time left
    mapping(address => CoolDown) coolDown;
    // max percentage of the TRU that can be slashed (10%)
    uint256 public constant MAXSLASH = 1000;

    /**
     * @dev Initialize sets the addresses of admin and the delay timestamp
     * @param stkTRU_ The address of stkTRU contract
     * @param tru_ The address of TRU contract
     * @param _trueDistributor The address of True Distributor
     * @param _pool The address of TrueFi pool
     * @param _uniRouter The address of uniswap router
     */
    function initialize(
        IStkTRU stkTRU_, 
        IERC20 tru_, 
        ITrueDistributor _trueDistributor, 
        ITrueFiPool _pool,
        IUniswapRouter _uniRouter,
        address _TUSD,
        address _WETH,
        address _TRU
    ) external {
        require(!initalized, "Already initialized");
        
        stkTRU = stkTRU_;
        tru = tru_;
        trueDistributor = _trueDistributor;
        pool = _pool;
        uniRouter = _uniRouter;
        owner_ = msg.sender;
        initalized = true;

        TUSD = _TUSD;
        WETH = _WETH;
        TRU = _TRU;

        require(trueDistributor.farm() == address(this), "TrueFarm: Distributor farm is not set");
    }

    /**
     * @dev Stake TRU and mint stkTRU
     * @param amount The amount to stake and mint 
     */
    function stake(uint256 amount) public update {
        require(tru.transferFrom(msg.sender, address(this), amount));
        require(coolDown[msg.sender].activated == false, "can't stake during the cool down period");

        uint256 amountToMint = amount.div(sktTruRate());
        stkTRU.mint(msg.sender, amountToMint);
        emit Stake(msg.sender, amountToMint);
    }

    /**
     * @dev Unstake TRU and burn stkTRU
     */
    function unstake() public update {
        require(coolDown[msg.sender].activated,"need to activate first");
        require(coolDown[msg.sender].time >= block.timestamp,"haven't passed the cool down period");
        coolDown[msg.sender].activated = false;

        uint256 sktTruAmount = stkTRU.balanceOf(msg.sender);
        uint256 truAmount = sktTruAmount.mul(sktTruRate());
        
        stkTRU.burn(msg.sender, sktTruAmount);
        require(tru.transfer(msg.sender, truAmount));
        emit Unstake(msg.sender, sktTruAmount);
    }   

    /**
     * @dev Activate for the cool down period
     */
    function activate() external {
         coolDown[msg.sender].activated = true;
         coolDown[msg.sender].time = block.timestamp.add(COOLDOWNPERIOD);
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

    /**
     * @dev Liquidation event
     * @param loanToken Address of the loanToken that is default
     */
    function liquidation(ILoanToken loanToken) external {
        require(loanToken.status() == ILoanToken.Status.Defaulted,"loanToken has not defaulted");

        uint256 amountDeficit = getLoanDeficitAmount(loanToken);
        uint256 maxToSlash = tru.balanceOf(address(this)).mul(MAXSLASH).div(10000);
        amountDeficit = amountDeficit > maxToSlash ? maxToSlash : amountDeficit;
        uint256 amountToPay = getTruAmount(amountDeficit);

        require(tru.transfer(address(pool), amountToPay));
        emit Liquidation(amountToPay);
    }

    /**
     * @dev Return the Tru amount based on the current price on Uniswap
     */
    function getTruAmount(uint256 usdAmount) internal returns(uint256) {
        address[] memory path = new address[](2);
        path[0] = TUSD;                                             // TUSD address on mainnet
        path[1] = WETH;                                             // WETH address on mainnet
        uint[] memory EthPrice = uniRouter.getAmountsIn(1, path);
        uint256 EthAmount = usdAmount.div(EthPrice[0]).mul(1e10);
        path[0] = TRU;                                              // TRU address on mainnet
        uint[] memory truAmount = uniRouter.getAmountsIn(EthAmount, path);
        return truAmount[0];
    }

    function getLoanDeficitAmount(ILoanToken loanToken) internal returns(uint256) {
        uint256 poolBalance = loanToken.balanceOf(address(pool));
        uint256 amountDefault = loanToken.amount().mul(poolBalance).div(loanToken.totalSupply());
        return amountDefault;
    }

    function convertFeeToTFI() external {
        // TODO
        // uint256 amountIn;
        // uint256 amountOutMin;
        // address[] memory path = new address[](2);
        // uniRouter.swapExactTokensForTokens(amountIn, amountOutMin, path, address(this), block.timestamp + 1 hours);
    }

    /**
     * @dev Calculate the floating rate of the sktTru
     */
    function sktTruRate() internal returns(uint256) {
        uint256 rate = tru.balanceOf(address(this)).div(stkTRU.totalSupply());
        return rate;
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


