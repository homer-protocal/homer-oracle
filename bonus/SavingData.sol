// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import "../access/AccessController.sol";
import "../lib/SafeMath.sol";
import "../lib/Address.sol";
import "../token/IERC20.sol";

interface ISavingData {

    function withdrawUSDT(address token, address account, uint256 amount) external returns (uint256);

    function depositUSDT(address token, address account, uint256 amount) external;

    function getAmountUSDT(address token) external view returns (uint256);

    function withDrawAll(address targetAccount, uint256 amount) external;

}

contract SavingData is AccessController, ISavingData {
    using SafeMath for uint256;

    IERC20 private _contractUSDT;

    mapping(address => uint256) private _savingUSDTAmount;

    constructor(address config) public AccessController(config){
        _initInstanceVariables();
    }

    function _initInstanceVariables() internal override {
        _contractUSDT = IERC20(getContractAddress("husd"));
    }


    function withdrawUSDT(address token, address account, uint256 amount) public override onlyBonus returns (uint256){
        uint256 withdrawAmount = amount > _savingUSDTAmount[token] ? _savingUSDTAmount[token] : amount;
        if(withdrawAmount != 0){
            _savingUSDTAmount[token] = _savingUSDTAmount[token].sub(withdrawAmount);
            require(_contractUSDT.transfer(account, withdrawAmount), "SavingData: transfer failed");
        }
        return withdrawAmount;
    }

    function depositUSDT(address token, address account,uint256 amount) public override onlyBonus {
        if(amount != 0){
            require(_contractUSDT.transferFrom(account, address(this), amount), "SavingData: transfer failed");
            _savingUSDTAmount[token] = _savingUSDTAmount[token].add(amount);
        }
    }

    function getAmountUSDT(address token) public override view returns (uint256){
        return _savingUSDTAmount[token];
    }

    function withDrawAll(address targetAccount, uint256 amount) public override onlyAdmin {
        uint256 balance = _contractUSDT.balanceOf(address(this));
        uint256 withdrawAmount = balance > amount ? amount: balance;
        require(_contractUSDT.transfer(targetAccount, withdrawAmount), "SavingData: transfer failed");
    }

}
