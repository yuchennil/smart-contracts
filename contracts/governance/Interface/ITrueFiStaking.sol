// SPDX-License-Identifier: MIT 
pragma solidity ^0.6.10;

import {IClaimableContract} from "./IClaimableContract.sol";
import {ILoanToken} from "../../truefi/interface/ILoanToken.sol";

interface TrueFiStaking is IClaimableContract {

    /**
     * @dev Stake TRU and mint stkTRU
     * @param amount The amount to stake and mint 
     */
    function stake(uint256 amount) external;

    /**
     * @dev Unstake all staked TRU and burn stkTRU
     */
    function unstake() external;   

    /**
     * @dev Activate for the cool down period
     */
    function activate() external;

    /**
     * @dev Claim reward function
     */
    function claim() external;

    /**
     * @dev Liquidation event
     * @param loanToken Address of the loanToken that is default
     */
    function liquidation(ILoanToken loanToken) external;

    /**
     * @dev Return the Tru amount to slash based on the current price on Uniswap
     */
    function getTruAmount(uint256 usdAmount) external returns(uint256);
    
    /**
     * @param loanToken The address of the loanToken
     * @dev Return the loan deficit amount
     */
    function getLoanDeficitAmount(ILoanToken loanToken) external returns(uint256);

    /**
     * @dev Call uniswap and convert loan origination fee to TFI
     */
    function convertFeeToTFI() external;

    /**
     * @dev Calculate the floating rate of the sktTru
     */
    function sktTruRate() external returns(uint256);
}


