// SPDX-License-Identifier: MIT
pragma solidity 0.6.10;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";

import {Ownable} from "../truefi/common/UpgradeableOwnable.sol";
import {ITrueFiPool} from "../truefi/interface/ITrueFiPool.sol";
import {ITrueRatingAgency} from "../truefi/interface/ITrueRatingAgency.sol";
import {IBurnableERC20} from "../trusttoken/interface/IBurnableERC20.sol";

contract TrueCreditLine is Ownable {
    using SafeMath for uint256;

    // ================ WARNING ==================
    // ===== THIS CONTRACT IS INITIALIZABLE ======
    // === STORAGE VARIABLES ARE DECLARED BELOW ==
    // REMOVAL OR REORDER OF VARIABLES WILL RESULT
    // ========= IN STORAGE CORRUPTION ===========

    mapping(address => bool) public allowedBorrowers;
    address[] _allowedBorrowers;
    uint256 coreLendingRate;
    struct CreditLine {
        uint256 riskAdj;
        uint256 creditLimit;
        uint256 exposureAdj;
        uint256 balance;
        uint256 finalRate;
    }
    mapping(address => CreditLine) public creditLine;
    uint256 public maxCoreLendingRate = 2000;   // initialize to 20%
    uint256 lastTimestamp;
    uint256 public constant FLAT_FEE = 25;      // basis point
    mapping(address => uint256) public staked;         // amount tru that community staked


    // ===== Pool parameters =====

    ITrueFiPool public pool;
    IERC20 public currencyToken;
    ITrueRatingAgency public ratingAgency;
    address public timelock;
    IBurnableERC20 public tru;

    // ======= STORAGE DECLARATION END ============

    /**
     * @dev Modifier for only whitelisted borrowers
     */
    modifier onlyAllowedBorrowers() {
        require(allowedBorrowers[msg.sender], "TrueLender: Sender is not allowed to borrow");
        _;
    }

    /**
     * @dev Modifier for only lending pool
     */
    modifier onlyPool() {
        require(msg.sender == address(pool), "TrueLender: Sender is not a pool");
        _;
    }

    /**
     * @dev Initalize the contract with parameters
     * @param _pool Lending pool address
     * @param _ratingAgency Prediction market address
     */
    function initialize(ITrueFiPool _pool, ITrueRatingAgency _ratingAgency, address _timelock, IBurnableERC20 _tru) public initializer {
        Ownable.initialize();

        pool = _pool;
        currencyToken = _pool.currencyToken();
        currencyToken.approve(address(_pool), uint256(-1));
        ratingAgency = _ratingAgency;
        timelock = _timelock;
        tru = _tru;
    }

    /**
     * @dev Called by owner to change whitelist status for accounts
     * @param who Account to change whitelist status for
     * @param status New whitelist status for account
     */
    function allow(address who, bool status) external onlyOwner {
        allowedBorrowers[who] = status;
        if(status){
            _allowedBorrowers.push(who);
        }
    }

    /**
     * @dev Set new max core lending rate
     * @param newMax New maximum loan APY
     */
    function setMaxCoreLendingRate(uint256 newMax) external onlyOwner {
        maxCoreLendingRate = newMax;
    }

    /**
     * @dev Stake tru to increase the credit limit for a line of credit
     * @param who The address of the borrower
     * @param _amount The credit limit for a borrower
     */
    function addCreditLimit(address who, uint256 _amount) external {
        require(allowedBorrowers[who], "invaild address");
        require(tru.balanceOf(msg.sender)>= _amount, "not enough tru balance to stake");
        
        creditLine[who].creditLimit = creditLine[who].creditLimit.add(_amount);
        staked[msg.sender] = staked[msg.sender].add(_amount);
        update(who);
        require(tru.transferFrom(msg.sender,address(this),_amount),"TRU transfer failed");
    }

    /**
     * @dev Unstake tru to reduce the credit limit for a line of credit
     * @param who The address of the borrower
     * @param _amount The credit limit for a borrower
     */
    function reduceCreditLimit(address who, uint256 _amount) external {
        require(allowedBorrowers[who], "invaild address");
        require(_amount <= creditLine[who].creditLimit, "invaild credit limit to reduce");

        creditLine[who].creditLimit = creditLine[who].creditLimit.sub(_amount);
        staked[msg.sender] = staked[msg.sender].sub(_amount);
        update(who);
        require(tru.transfer(msg.sender,_amount),"TRU transfer failed");
    }

    /**
     * @dev Set new risk adjustment by timelock contract
     * @param who The address of the borrower
     * @param _riskAdj The risk adjustment for a borrower
     */
    function setRiskAdjustment(address who, uint256 _riskAdj) external {
        require(msg.sender == timelock, "only timelock contract can call setRiskAdjustment function");
        require(allowedBorrowers[who], "invaild address");
        require(_riskAdj >= 0 , "invaild risk adjustment");

        creditLine[who].riskAdj = _riskAdj;
        update(who);
    }

    /**
     * @dev update the current core lending rate
     */
    function updateCoreLendingRate() internal {
        // TODO
        uint256 curvefiRate = 1000; 
        uint256 percentLiquid = uint(1000).mul(pool.liquidValue()).div(pool.poolValue());
        // Q&A
        uint256 usageAdjustment = maxCoreLendingRate.mul((uint256(10000).sub(percentLiquid))**15);
        coreLendingRate = curvefiRate.add(usageAdjustment);
    }

    /**
     * @dev update the exposure adjustment for a borrower
     * @param who The address for the update
     */
    function updateExposureAdjustment(address who) internal {
        creditLine[who].exposureAdj = (creditLine[who].riskAdj).mul(creditLine[who].balance.div(creditLine[who].creditLimit)**3);
    }

    /**
     * @dev update the final rate for a credit line
     * @param who The address for the update
     */
    function updateFinalRate(address who) internal {
        creditLine[who].finalRate = creditLine[who].exposureAdj.add(creditLine[who].riskAdj).add(coreLendingRate);
    }

    /**
     * @dev Accrued interest for all current lines of credit
     */
    function accruedInterest() internal {
        uint256 deltaTimestamp = block.timestamp.sub(lastTimestamp);
        lastTimestamp = block.timestamp;
        for(uint i = 0; i < _allowedBorrowers.length-1; i++){
            address who = _allowedBorrowers[i];
            uint256 marginalInterest = creditLine[who].balance.mul(deltaTimestamp).mul(creditLine[who].finalRate).div(3600*24*365).div(10000);
            creditLine[who].balance = creditLine[who].balance.add(marginalInterest);
        }
    }

    /**
     * @dev Update on core lending rate, exposure, final rate and accrued interest
     * @param who The address for updating the risk adjustment and final rate
     */
    function update(address who) internal {
        updateCoreLendingRate();
        updateExposureAdjustment(who);
        updateFinalRate(who);
        accruedInterest();      // update it first
    }

    /**
     * @dev Check if the amount to borrow if within the credit limit
     * @param who The address for borrower
     * @param _amount The intended amount to borrow
     */
    function borrowWithinBound(address who, uint256 _amount) public view returns(bool) {
        return creditLine[who].creditLimit >= _amount.add(creditLine[who].balance);
    }

    /**
     * @dev Check if the repayment amount is within bound
     * @param who The address for borrower
     * @param _amount The intended amount to repay
     */
    function repayWithinBound(address who, uint256 _amount) public view returns(bool) {
        return _amount <= creditLine[who].balance;
    }

    /**
     * @dev Borrow capital from a credit line
     * @param _amount The amount of capital to borrow
     */
    function borrow(uint256 _amount) external onlyAllowedBorrowers {
        require(borrowWithinBound(msg.sender,_amount), "not enough credit limit");
        creditLine[msg.sender].balance = creditLine[msg.sender].balance.add(_amount);
        update(msg.sender);

        _borrow(_amount);
    }

    function _borrow(uint256 _amount) internal {
        uint256 amountWithoutFee = _amount.sub(_amount.mul(FLAT_FEE).div(10000));
        pool.borrow(_amount, amountWithoutFee);
        require(currencyToken.transfer(msg.sender,_amount));
    }

    /**
     * @dev repay capital back to the pool
     * @param _amount The amount of capital to repay
     */
    function repay(uint256 _amount) external onlyAllowedBorrowers {
        require(repayWithinBound(msg.sender,_amount), "invaild amount for repayment");
        creditLine[msg.sender].balance = creditLine[msg.sender].balance.sub(_amount);
        update(msg.sender);

        _repay(_amount);
    }

    function _repay(uint256 _amount) internal {
        require(currencyToken.transferFrom(msg.sender,address(this),_amount));
        //currencyToken.approve(address(pool),_amount);
        pool.repay(_amount);
    }




}
