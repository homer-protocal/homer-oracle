// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import "../access/AccessController.sol";
import "../lib/SafeMath.sol";
import "../token/IERC20.sol";
import {ILockupData} from "./LockupData.sol";
import {ISavingData} from "./SavingData.sol";
import {IBonusData} from "./BonusData.sol";
import {ITokenPairData} from "../auction/TokenPairData.sol";

interface IBonus {
    function lockup(uint256 amount, address token) external returns (bool);

    function unlock(address token, uint256 amount) external returns (bool);

    function receiveBonus(address token) external returns (bool);

    function getNextTime() external view returns (uint256);

    function getTokenCirculationSnapshot(address token, uint256 periodNo) external view returns (uint256);

    function getBonusSnapshot(address token, uint256 periodNo, address account) external view returns (uint256);

    function getPeriodNo() external view returns (uint256);

    function getLocked(address token, address account) external view returns (uint256);

    function isInDistributionTime() external view returns(bool);
}

contract Bonus is AccessController, IBonus {
    using SafeMath for uint256;

    IERC20 private _homerContract;
    ILockupData private _lockupDataContract;
    ISavingData private _savingDataContract;
    IBonusData private _bonusDataContract;
    ITokenPairData private _tokenPairDataContract;
    address private _destructionAddress;
    IERC20 private _contractUSDT;


    uint256 public timeLimit = 168 hours;
    uint256 public bonusTimeLimit = 60 hours;
    uint256 public periodNum;
    uint256 public miniBonusIncrement = 3;
    uint256[3] public savingPercent = [10, 20, 30];
    uint256[2] public threshold = [1000 ether, 5000 ether];
    uint256 public expectSpanForHomer = 100000000 ether;
    uint256 public expectSpanForHToken = 1000000 ether;
    uint256 miniUSDTBonus = 100 ether;

    uint256 private _distributionTime;
    mapping(address => mapping(uint256 => uint256)) public circulationHistoryRecord;           // token => period => totalCirculation
    mapping(address => mapping(uint256 => bool)) public distributionStatus;                    // token => period => isSettled
    mapping(address => mapping(uint256 => mapping(address => uint256))) public lockedRecord;        // token => period => account => locked up amount

    mapping(address => uint256) public currentUSDTDistribution;                                    // token => revenue
    mapping(address => mapping(uint256 => mapping(address => uint256))) public receiveUSDTRecord;       // token => period => account => isReceived

    event BonusReceived(address indexed token, address indexed account, uint256 indexed periodNum, uint256 amount);

    constructor(address config, uint256 firstTime) public AccessController(config){
        _initInstanceVariables();
        _distributionTime = firstTime;
    }

    function _initInstanceVariables() internal override {
        super._initInstanceVariables();
        _homerContract = IERC20(getContractAddress("homer"));
        _lockupDataContract = ILockupData(getContractAddress("lockupData"));
        _savingDataContract = ISavingData(getContractAddress("savingData"));
        _bonusDataContract = IBonusData(getContractAddress("bonusData"));
        _tokenPairDataContract = ITokenPairData(getContractAddress("tokenPairData"));
        _contractUSDT = IERC20(getContractAddress("husd"));
    }

    function lockup(uint256 amount, address token) external override returns (bool) {
        require(_isValidToken(token), "bonus: invalid token");
        require(!_isInDistributionTime(now), "bonus: can not deposit in bonus time");
        _lockupDataContract.deposit(token, msg.sender, amount);
        return true;
    }

    function unlock(address token, uint256 amount) public override returns(bool) {
        require(_isValidToken(token), "bonus: invalid token");
        require(amount > 0, "bonus: amount can not be zero");
        require(amount <= _lockupDataContract.getAmount(token, msg.sender), "bonus: insufficient balance");
        _lockupDataContract.withdraw(token, msg.sender, amount);
        return true;
    }

    function receiveBonus(address token) public override returns(bool){
        require(_isValidToken(token), "bonus: invalid token");
        uint256 lockedAmount = _lockupDataContract.getAmount(token, msg.sender);
        require(lockedAmount > 0, "bonus: no locked token");

        uint256 nowTime = now;
        require(_isInDistributionTime(nowTime), "bonus: not in distribution time");

        uint256 nextTime = _computeNextDistributionTime(nowTime);
        if (nextTime > _distributionTime) {
            _distributionTime = nextTime;
            periodNum = periodNum.add(1);
        }

        settlement(token);
        require(receiveUSDTRecord[token][periodNum.sub(1)][msg.sender] == 0, "bonus: have received");

        lockedRecord[token][periodNum.sub(1)][msg.sender] = lockedAmount;
        require(circulationHistoryRecord[token][periodNum.sub(1)] > 0, "bonus: total circulation error");

        if(currentUSDTDistribution[token]>0){
            uint256 selfUSDTAmount = lockedAmount.mul(currentUSDTDistribution[token]).div(circulationHistoryRecord[token][periodNum.sub(1)]);
            require(selfUSDTAmount > 0, "bonus: bonus usdt can not be zero");
            receiveUSDTRecord[token][periodNum.sub(1)][msg.sender] = selfUSDTAmount;
            _bonusDataContract.withdrawUSDT(token, msg.sender, selfUSDTAmount);
            emit BonusReceived(token, msg.sender, periodNum.sub(1), selfUSDTAmount);
        }
        return true;
    }

    function getNextTime() public view  override returns(uint256){
        return _computeNextDistributionTime(now);
    }

    function setNextTime(uint256 nextTime) public onlyAdmin {
        require(nextTime >= now);
        _distributionTime = nextTime;
    }
    function getPeriodNo() public view override returns (uint256){
        return periodNum;
    }

    function getTokenCirculationSnapshot(address token, uint256 periodNo) external view override returns (uint256){
        return circulationHistoryRecord[token][periodNo];
    }

    function getLocked(address token, address account) external view override returns (uint256){
        return _lockupDataContract.getAmount(token, account);
    }

    function getBonusSnapshot(address token, uint256 periodNo, address account) external view override returns (uint256) {
        return receiveUSDTRecord[token][periodNo][account];
    }

    function setDistributionTime(uint256 distributionTime) public onlyAdmin {
        _distributionTime = distributionTime;
    }

    function getDistributionTime() public view returns(uint256){
        return _distributionTime;
    }

    function settlement(address token) private {
        if (!distributionStatus[token][periodNum.sub(1)]) {
            uint256 expectedMiniUSDTBonus = _getExpectedMiniBonus(miniUSDTBonus,token);
            uint256 revenueUSDT = _bonusDataContract.getAmountUSDT(token);
            _savingUSDT(revenueUSDT, expectedMiniUSDTBonus, token);

            currentUSDTDistribution[token] = _bonusDataContract.getAmountUSDT(token);

            circulationHistoryRecord[token][periodNum.sub(1)] = _getTotalCirculation(token);
            distributionStatus[token][periodNum.sub(1)] = true;
        }
    }

    // 计算出token的总流通量
    // 如果是home: 总流通量 = 总发行量 - 已销毁数量 - 矿池剩余
    // 如果是htoken: 直接获取总发行量
    function _getTotalCirculation(address token) public view returns (uint256){
        if (token == address(address(_homerContract))) {
            uint256 totalSupply = _homerContract.totalSupply();
            uint256 destroyed = _homerContract.balanceOf(_destructionAddress);
            uint256 miningPool = _homerContract.balanceOf(getContractAddress("mining"));
            return totalSupply.sub(destroyed).sub(miningPool);
        } else {
            return IERC20(token).totalSupply();
        }
    }

    function _computeNextDistributionTime(uint256 nowTime) private view returns (uint256){
        if (nowTime >= _distributionTime) {
            uint256 times = nowTime.sub(_distributionTime).div(timeLimit);
            return _distributionTime.add(times.add(1).mul(timeLimit));
        } else {
            return _distributionTime;
        }
    }

    function _isInDistributionTime(uint256 nowTime) private view returns (bool){
        uint256 nextTime = _computeNextDistributionTime(nowTime);
        return nowTime >= nextTime.sub(timeLimit) && nowTime <= nextTime.sub(timeLimit).add(bonusTimeLimit);
//        return nowTime >= nextTime && nowTime <= nextTime + bonusTimeLimit;
    }

    function isInDistributionTime() external view override returns(bool){
        return _isInDistributionTime(now);
    }

    function _getExpectedMiniBonus(uint256 _miniBonus,address token) public view returns (uint256) {
        uint256 circulation = _getTotalCirculation(token);

        uint256 steps;
        if (token == address(_homerContract)) {
            steps = circulation.div(expectSpanForHomer);
        } else {
            steps = circulation.div(expectSpanForHToken);
        }

        uint256 expectedMiniBonus = _miniBonus;
        for (uint256 i = 0; i < steps; i++) {
            expectedMiniBonus = expectedMiniBonus.add(expectedMiniBonus.mul(miniBonusIncrement).div(100));
        }
        return expectedMiniBonus;
    }

    function _savingUSDT(uint256 revenue, uint256 expectedMiniBonus, address token) private {

        if (revenue > expectedMiniBonus) {
            uint256 savingAmount = _getSavingAmount(revenue,expectedMiniBonus);

            _bonusDataContract.withdrawUSDT(token, address(this), savingAmount);
            require(_contractUSDT.approve(address(_savingDataContract),savingAmount),"Bonus: approve failed");
            _savingDataContract.depositUSDT(token,address(this),savingAmount);
        } else {
            uint256 withdrawAmount = _savingDataContract.withdrawUSDT(token, address(this), expectedMiniBonus.sub(revenue));
            if(withdrawAmount>0){
                require(_contractUSDT.approve(address(_bonusDataContract),withdrawAmount),"Bonus: approve failed");
                _bonusDataContract.depositUSDT(token,address(this),withdrawAmount);
            }
        }
    }

    // (0, 1000] - 10%
    // (1000, 5000] - 20%
    // (5000, ] - 30%
    function _getSavingAmount(uint256 revenue, uint256 expectedMiniBonus) private view returns (uint256 savingAmount){
        if (revenue <= threshold[0]) {
            savingAmount = revenue.mul(savingPercent[0]).div(100);
        } else if (revenue > threshold[0] && revenue <= threshold[1]) {
            savingAmount = revenue.mul(savingPercent[1]).div(100);
        } else {
            savingAmount = revenue.mul(savingPercent[2]).div(100);
        }

        if (revenue.sub(savingAmount) < expectedMiniBonus) {
            savingAmount = revenue.sub(expectedMiniBonus);
        }
        return savingAmount;
    }

    function _isValidToken(address token) private view returns (bool){
        return _tokenPairDataContract.isHToken(token) || token == address(_homerContract);
    }

    receive() external payable {}
}
