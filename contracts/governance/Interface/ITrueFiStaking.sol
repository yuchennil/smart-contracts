// SPDX-License-Identifier: MIT 
pragma solidity ^0.6.10;

import {IClaimableContract} from "./IClaimableContract.sol";
import {ILoanToken} from "../../truefi/interface/ILoanToken.sol";

interface ITrueFiStaking is IClaimableContract {

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
     * @dev Liquidation event
     * @param loanToken Address of the loanToken that is default
     */
    function liquidation(ILoanToken loanToken) external;

    /**
     * @dev Calculate the floating rate of the sktTru
     */
    function sktTruRate() external returns(uint256);
}


