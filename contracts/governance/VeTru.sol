// SPDX-License-Identifier: MIT 
pragma solidity ^0.6.10;

import {VoteToken} from "./VoteToken.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";


contract VeTru is VoteToken {
    mapping(address => bool) public whitelist;
    address public admin;

    using SafeMath for uint256;

    function initialize() public {
        require(!initalized, "already initialized");
        owner_ = msg.sender;
        initalized = true;
    }

    function mint(address _to, uint256 _amount) external onlyWhiteList{
        _mint(_to, _amount);
    }

    function burn(address _to, uint256 amount) external {
        _burn(_to, amount);
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

    function addWhitelist(address _address) public {
        whitelist[_address] = true;
    }
    
    function removeWhitelist(address _address) public {
        whitelist[_address] = false;
    }
    
    /**
     * @dev Override ERC20 _transfer so only whitelisted addresses can transfer
     * @param sender sender of the transaction
     * @param recipient recipient of the transaction
     * @param _amount amount to send
     */
    function _transfer(address sender,address recipient,uint256 _amount) internal override onlyWhiteList() {
        return super._transfer(sender, recipient, _amount);
    }

    modifier onlyWhiteList {
        require(whitelist[msg.sender] == true,
        "Only whitelist addresses can call this function."
        );
        _;
    }
}
