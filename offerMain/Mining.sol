// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import "../access/AccessController.sol";
import "../token/IERC20.sol";
import "../lib/SafeMath.sol";

contract Mining is AccessController {
    using SafeMath for uint256;

    IERC20 private _homerContract;

    address public coder;
    uint256 public coderPercent = 10;
    uint256 public incomePeriod = 4;

    uint256 public decayPeriod = 10512000;
    uint256 public decayPercent = 40;
    mapping(uint256 => mapping(uint256 => uint256)) public miningAmountList;
    uint256 public initialMiningAmount = 3.8 ether;
    uint256 public stableMiningAmount = 1 ether;
    mapping(uint256 => uint256) public firstBlock;
    mapping(uint256 => uint256) public latestBlock;
    mapping(uint256 => uint256) public pool;

    event Mined(uint256 blockNum, uint256 homerAmount);

    constructor(address config) public AccessController(config){
        _initInstanceVariables();
    }

    function _initInstanceVariables() internal override {
        _homerContract = IERC20(getContractAddress("homer"));
        coder = getContractAddress("coder");
        miningAmountList[0][0] = initialMiningAmount;
        miningAmountList[1][0] = initialMiningAmount;
        miningAmountList[2][0] = initialMiningAmount;
    }

    function mining(uint256 index) public onlyOfferMain returns (uint256){
        uint256 miningAmount = _miningAmount(index);

        if (pool[index] < miningAmount) {
            miningAmount = pool[index];
        }

        if (miningAmount > 0) {
            pool[index] = pool[index].sub(miningAmount);
            emit Mined(block.number, miningAmount);
            if(miningAmountList[index][4] == 0){
                uint256 coderAmount = miningAmount.mul(coderPercent).div(100);
                require(_homerContract.transfer(coder, coderAmount), "mining: transfer fail");
                require(_homerContract.transfer(msg.sender, miningAmount.sub(coderAmount)), "mining: transfer failed");
                miningAmount = miningAmount.sub(coderAmount);
            }else{
                require(_homerContract.transfer(msg.sender, miningAmount), "mining: transfer failed");
            }
        }
        latestBlock[index] = block.number;
        return miningAmount;
    }

    function withdrawAllHomer(uint256 index,address account) public onlyAdmin {
        require(_homerContract.transfer(account, _homerContract.balanceOf(address(this))), "mining: transfer failed");
        pool[index] = 0;
    }

    function depositHomer(uint256 index,uint256 amount) public onlyAdmin {
        require(_homerContract.transferFrom(msg.sender,address(this),amount),"mining: transferFrom failed");
        if(pool[index] == 0){
            firstBlock[index] = block.number;
            latestBlock[index] = block.number;
        }
        pool[index] = pool[index].add(amount);
    }

    function depositHomerInner(uint256 index,uint256 amount) public onlyOfferMain {
        require(_homerContract.transferFrom(msg.sender,address(this),amount),"mining: transferFrom failed");
        if(pool[index] == 0){
            firstBlock[index] = block.number;
            latestBlock[index] = block.number;
        }
        pool[index] = pool[index].add(amount);
    }

    function _miningAmount(uint256 index) private returns (uint256) {
        uint256 decayPeriodNum = block.number.sub(firstBlock[index]).div(decayPeriod);
        uint256 miningAmountPerBlock = _singleBlockMining(index,decayPeriodNum);
        return miningAmountPerBlock.mul(block.number.sub(latestBlock[index]));
    }

    function _singleBlockMining(uint256 index,uint256 decayPeriodNum) private returns (uint256){
        if(miningAmountList[index][decayPeriodNum] == 0){
            miningAmountList[index][decayPeriodNum] = pool[index].mul(decayPercent).div(100).mul(decayPeriod);
        }
        return miningAmountList[index][decayPeriodNum];
    }
}
