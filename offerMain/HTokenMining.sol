// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import "../access/AccessController.sol";
import "../token/IERC20.sol";
import "../lib/SafeMath.sol";
import {ITokenPairData} from "../auction/TokenPairData.sol";
import {IHToken} from "../token/HToken.sol";

contract HTokenMining is AccessController {
    using SafeMath for uint256;
    uint256 public decayPeriod = 10512000;
    uint256 public decayPercent = 60;
    uint256[11] public miningAmountList;
    uint256 public initialMiningAmount = 3.8 ether;
    uint256 public stableMiningAmount = 1 ether;
    uint256 public bidderRatio = 5;

    ITokenPairData private _tokenPairData;

    event Mined(uint256 blockNum, address token, address hToken, uint256 amount);

    constructor(address config) public AccessController(config){
        _initInstanceVariables();

        uint256 miningAmount = initialMiningAmount;
        for (uint256 i = 0; i <= 5; i++) {
            miningAmountList[i] = miningAmount;
            miningAmount = miningAmount.mul(decayPercent).div(100);
        }
    }

    function _initInstanceVariables() internal override {
        _tokenPairData = ITokenPairData(getContractAddress("tokenPairData"));
    }

    function mining(address token) public returns (uint256){
        require(!_tokenPairData.isBlocked(token) && _tokenPairData.isEnabled(token) && _tokenPairData.isValidToken(token), "HTokenMining: invalid token");
        IHToken hToken = IHToken(_tokenPairData.getTokenPair(token));
        (uint256 createBlock, uint256 recentUsedBlock) = hToken.getBlockInfo();
        uint256 decayPeriodNum = block.number.sub(createBlock).div(decayPeriod);
        uint256 miningAmountPerBlock = _singleBlockMining(decayPeriodNum);
        uint256 miningAmount = miningAmountPerBlock.mul(block.number.sub(recentUsedBlock));
        if (miningAmount > 0){
            hToken.mint(miningAmount);
            address bidder = hToken.getBidder();
            uint256 bidderAmount = miningAmount.mul(bidderRatio).div(100);
            require(hToken.transfer(bidder, bidderAmount), "HTokenMining: transfer to bidder failed");
            require(hToken.transfer(msg.sender, miningAmount.sub(bidderAmount)), "HTokenMining: transfer to offer contract failed");
            emit Mined(block.number, token, address(hToken), miningAmount);
            return miningAmount.sub(bidderAmount);
        }else{
            return 0;
        }
    }

    function _singleBlockMining(uint256 decayPeriodNum) private returns (uint256){
        if(miningAmountList[decayPeriodNum] == 0){
            miningAmountList[decayPeriodNum] = miningAmountList[decayPeriodNum.sub(1)].mul(decayPercent).div(100);
        }
        return miningAmountList[decayPeriodNum];
    }
}
