// SPDX-License-Identifier: MIT 
pragma solidity ^0.6.10;

interface IVeTru {

    function initialize() external;

    function mint(address _to, uint256 _amount) external;

    function burn(address _to, uint256 amount) external;

    function decimals() external pure returns (uint8);

    function rounding() external pure returns (uint8);

    function name() external pure returns (string memory);

    function symbol() external pure returns (string memory);

    function addWhitelist(address _address) external;
    
    function removeWhitelist(address _address) external;
    
    function _transfer(address sender,address recipient,uint256 _amount) external;

}
