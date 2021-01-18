// SPDX-License-Identifier: MIT 
pragma solidity ^0.6.10;

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStkTRU} from "./StkTRU.sol";
import {ClaimableContract} from "./common/ClaimableContract.sol";
import {ITrueFiPool} from "../truefi/interface/ITrueFiPool.sol";
import {ILoanToken} from "../truefi/interface/ILoanToken.sol";
import {ITrueFiStaking} from "./Interface/ITrueFiStaking.sol";

contract TrueFiStaking is ClaimableContract, ITrueFiStaking {
    using SafeMath for uint256;

    struct CoolDown {
        uint256 time;
        bool activated;     
    }
    uint256 constant COOLDOWNPERIOD = 80640;        // 14 days, assume 15sec per block
    uint256 constant MAXSLASH = 1000;               // max percentage of the TRU that can be slashed (10%)
    uint256 constant PRECISION = 10000;

    IStkTRU public stkTRU;
    IERC20 public tru;
    ITrueFiPool public pool;
    mapping(address => CoolDown) coolDown;          // track the individual cool down time left

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
     * @dev Emitted when the staking pool get slashed
     * @param amountSlashed The amount that slashed
     */
    event Liquidation(uint256 amountSlashed);
 
    /**
     * @dev Initialize sets the addresses of admin and the delay timestamp
     * @param stkTRU_ The address of stkTRU contract
     * @param tru_ The address of TRU contract
     * @param _pool The address of TrueFi pool
     */
    function initialize(
        IStkTRU stkTRU_, 
        IERC20 tru_, 
        ITrueFiPool _pool
    ) external {
        require(!initalized, "Already initialized");
        owner_ = msg.sender;
        initalized = true;

        stkTRU = stkTRU_;
        tru = tru_;
        pool = _pool;
    }

    /**
     * @dev Activate for the cool down period
     */
    function activate() external {
         require(coolDown[msg.sender].activated == false, "can't activate again during the cool down period");
         coolDown[msg.sender].activated = true;
         coolDown[msg.sender].time = block.timestamp.add(COOLDOWNPERIOD);
    }

    /**
     * @dev Stake TRU and mint stkTRU
     * @param amount The amount to stake and mint 
     */
    function stake(uint256 amount) public override {
        require(coolDown[msg.sender].activated == false, "can't stake during the cool down period");
        require(tru.transferFrom(msg.sender, address(this), amount));

        uint256 amountToMint = amount.div(sktTruRate());
        stkTRU.mint(msg.sender, amountToMint);
        emit Stake(msg.sender, amountToMint);
    }

    /**
     * @dev Unstake TRU and burn stkTRU
     */
    function unstake() public override {
        require(coolDown[msg.sender].activated,"need to activate first");
        require(coolDown[msg.sender].time >= block.timestamp,"haven't passed the cool down period");
        
        coolDown[msg.sender].activated = false;
        uint256 sktTruAmount = stkTRU.balanceOf(msg.sender);
        uint256 truAmount = sktTruAmount.mul(sktTruRate());

        require(tru.transfer(msg.sender, truAmount));
        stkTRU.burn(msg.sender, sktTruAmount);
        emit Unstake(msg.sender, sktTruAmount);
    }   

    /**
     * @dev Calculate the floating rate of the sktTru
     */
    function sktTruRate() public override returns(uint256) {
        uint256 rate = tru.balanceOf(address(this)).div(stkTRU.totalSupply());
        return rate;
    }

    /**
     * @dev Liquidation event
     * @param loanToken Address of the loanToken that is default
     */
    function liquidation(ILoanToken loanToken) external override {
        require(loanToken.status() == ILoanToken.Status.Defaulted,"loanToken has not defaulted");

        uint256 truPrice = getTruPrice();
        uint256 amountDefault = loanToken.amount()
                                            .mul(loanToken.balanceOf(address(pool)))
                                                .div(loanToken.totalSupply());

        uint256 maxToSlash = tru.balanceOf(address(this))
                                    .mul(truPrice).div(PRECISION)
                                        .mul(MAXSLASH).div(PRECISION);

        uint256 usdToPay = amountDefault > maxToSlash ? maxToSlash : amountDefault;
        uint256 truToPay = usdToPay.div(truPrice);

        require(tru.transfer(address(pool), truToPay));
        emit Liquidation(truToPay);
    }

    /**
     * @dev Return the Tru price
     */
    function getTruPrice() internal pure returns(uint256) {
        return 2500;                                    // Hard coded: 2500/PRICISION = $0.25
    }
}


