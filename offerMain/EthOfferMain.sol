// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import "../access/AccessController.sol";
import "../lib/SafeMath.sol";
import "../lib/Address.sol";
import "../lib/Strings.sol";
import "../lib/SafeERC20.sol";
import {IPriceData} from "./PriceService.sol";
import "./Mining.sol";
import {ITokenPairData} from "../auction/TokenPairData.sol";
import {IBonusData} from "../bonus/BonusData.sol";
import "./HTokenMining.sol";

contract EthOfferMain is AccessController {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct Offer {
        address owner;
        bool isDeviate;
        address token;

        uint256 ethAmount;
        uint256 erc20Amount;
        uint256 remainingEthAmount;
        uint256 remainingERC20Amount;

        uint256 blockNum;
        uint256 miningFee;
    }

    enum TradeChoices {SendEthBuyERC20, SendERC20BuyEth}

    IPriceData private _priceDataContract;
    Mining private _mingContract;
    IERC20 private _homerContract;
    IBonusData private _bonusDataContract;
    ITokenPairData private _tokenPairData;
    HTokenMining private _hTokenMining;
    IERC20 private _ethContract;
    IERC20 private _husdContract;

    uint256 public tradeRatio = 2;
    uint256 public leastEth = 10 ether;
    uint256 public offerSpan = 10 ether;
    uint256 public deviationThreshold = 10;
    uint256 public deviationScale = 10;
    uint256 public blockLimit = 100;
    //fee husd:1ether
    uint256 public miningFee = 1 ether;
    uint256 public tradeFee = 1 ether;

    mapping(address => bool) public allowedToken;

    mapping(uint256 => mapping(address => uint256)) public feeOfBlock;
    mapping(uint256 => mapping(address => uint256)) public miningOfBlock;
    Offer[] private _offers;
    mapping(address => uint256[]) private _erc20OffersIndex;

    mapping(address => mapping(uint256 => uint256)) private _invalidOfBlock;
    mapping(address => mapping(uint => uint256)) private _invalidKeyIndex;
    mapping(address => uint) private _invalidLength;

    mapping(uint256 => mapping(address => uint256)) private _noTakeFeeOfBlock;
    mapping(uint256 => mapping(address => uint256)) private _takeFeeOfBlock;
    mapping(uint256 => mapping(address => uint256[])) private _indexOfBlock;

    mapping(uint256 => mapping(address => bool)) private _isReturnMiningOfBlock;

    event NewOfferAdded(address indexed offerIndex, address indexed token, uint256 ethAmount, uint256 erc20Amount, uint256 confirmedBlock, uint256 fee, address offerOwner);
    event OfferTraded(address indexed offerIndex, address indexed token, address trader, address offerOwner, uint256 tradeEthAmount, uint256 tradeERC20Amount);

    constructor(address config) public AccessController(config){
        _initInstanceVariables();
    }

    function _initInstanceVariables() internal override {
        super._initInstanceVariables();
        _priceDataContract = IPriceData(getContractAddress("ethPriceData"));
        _mingContract = Mining(getContractAddress("mining"));
        _homerContract = IERC20(getContractAddress("homer"));
        _bonusDataContract = IBonusData(getContractAddress("bonusData"));
        _tokenPairData = ITokenPairData(getContractAddress("tokenPairData"));
        _hTokenMining = HTokenMining(getContractAddress("hTokenMining"));
        _ethContract = IERC20(getContractAddress("eth"));
        _husdContract = IERC20(getContractAddress("husd"));
        require(_homerContract.approve(address(_mingContract), uint256(100000000 ether)), "offerMain: approve fail");
    }

    function offer(uint256 ethAmount, uint256 erc20Amount, address erc20) public onlyEOA {
        require(_tokenPairData.isValidToken(erc20), "offerMain: token not allowed");
        require(_tokenPairData.isEthToken(erc20), "offerMain: token type error");

        bool deviation = isDeviation(ethAmount, erc20Amount, erc20);
        if (deviation) {
            require(ethAmount >= leastEth.mul(deviationScale), "offerMain: EthAmount needs to be no less than 10 times of the minimum scale");
        }

        _ethContract.safeTransferFrom(msg.sender,address(this),ethAmount);

        _createOffer(ethAmount, erc20Amount, erc20, miningFee, deviation);

        IERC20(erc20).safeTransferFrom(msg.sender, address(this), erc20Amount);

        _ming(erc20);

        _husdContract.safeTransferFrom(msg.sender,address(this),miningFee);
        require(_husdContract.approve(address(_bonusDataContract),miningFee),"offerMain: approve failed");
        _bonusDataContract.depositUSDT(_tokenPairData.getTokenPair(erc20),address(this),miningFee);

        feeOfBlock[block.number][erc20] = feeOfBlock[block.number][erc20].add(miningFee);
        _noTakeFeeOfBlock[block.number][erc20] = _noTakeFeeOfBlock[block.number][erc20].add(miningFee);
        _addInvalidOfBlock(erc20,block.number,1);
    }

    function _ming(address token) private {
        uint256 miningAmount;
        if (_tokenPairData.isDefaultToken(token)) {
            miningAmount = _mingContract.mining(2);
            if (miningAmount > 0) {
                miningOfBlock[block.number][token] = miningAmount;
            }
        } else {
            miningAmount = _hTokenMining.mining(token);
            if (miningAmount > 0){
                miningOfBlock[block.number][token] = miningAmount;
            }
        }
    }

    function sendEthBuyErc20(uint256 ethAmount, uint256 erc20Amount, address offerIndex, uint256 tradeEthAmount, uint256 tradeErc20Amount, address erc20) public onlyEOA {
        _tradeOffer(TradeChoices.SendEthBuyERC20, ethAmount, erc20Amount, offerIndex, tradeEthAmount, tradeErc20Amount, erc20);
    }

    function sendErc20BuyEth(uint256 ethAmount, uint256 erc20Amount, address offerIndex, uint256 tradeEthAmount, uint256 tradeErc20Amount, address erc20) public onlyEOA {
        _tradeOffer(TradeChoices.SendERC20BuyEth, ethAmount, erc20Amount, offerIndex, tradeEthAmount, tradeErc20Amount, erc20);
    }

    function _tradeOffer(TradeChoices tradeChoices, uint256 ethAmount, uint256 erc20Amount, address offerIndex, uint256 tradeEthAmount, uint256 tradeErc20Amount, address erc20) private {
        uint256 index = uint256(offerIndex);
        Offer storage tradeOffer = _offers[index];

        require(tradeOffer.token == erc20, "offerMain: wrong token address");

        bool deviation = isDeviation(ethAmount, erc20Amount, erc20) || tradeOffer.isDeviate;
        if (deviation) {
            require(ethAmount >= tradeEthAmount.mul(deviationScale), "offerMain: EthAmount needs to be no less than 10 times of transaction scale");
        } else {
            require(ethAmount >= tradeEthAmount.mul(tradeRatio), "offerMain: EthAmount needs to be no less than 2 times of transaction scale");
        }

        require(tradeEthAmount.mod(offerSpan) == 0, "offerMain: Transaction size does not meet asset span");
        require(!_isConfirmed(tradeOffer.blockNum), "offerMain: price has been confirmed");
        require(tradeOffer.remainingEthAmount >= tradeEthAmount, "offerMain: insufficient trading eth");
        require(tradeOffer.remainingERC20Amount >= tradeErc20Amount, "offerMain: insufficient trading token");
        require(tradeErc20Amount == tradeOffer.remainingERC20Amount.mul(tradeEthAmount).div(tradeOffer.remainingEthAmount), "offerMain: wrong erc20 amount");

        if(_isNoArbitrage(index)){
            _noTakeFeeOfBlock[tradeOffer.blockNum][erc20]=_noTakeFeeOfBlock[tradeOffer.blockNum][erc20].sub(tradeOffer.miningFee);
            _takeFeeOfBlock[tradeOffer.blockNum][erc20]=_takeFeeOfBlock[tradeOffer.blockNum][erc20].add(tradeOffer.miningFee);
            if(_noTakeFeeOfBlock[tradeOffer.blockNum][erc20] == 0){
                _isReturnMiningOfBlock[tradeOffer.blockNum][erc20] = true;
            }
        }

        if (tradeChoices == TradeChoices.SendEthBuyERC20) {
            tradeOffer.ethAmount = tradeOffer.ethAmount.add(tradeEthAmount);
            tradeOffer.erc20Amount = tradeOffer.erc20Amount.sub(tradeErc20Amount);
        } else {
            tradeOffer.ethAmount = tradeOffer.ethAmount.sub(tradeEthAmount);
            tradeOffer.erc20Amount = tradeOffer.erc20Amount.add(tradeErc20Amount);
        }
        tradeOffer.remainingERC20Amount = tradeOffer.remainingERC20Amount.sub(tradeErc20Amount);
        tradeOffer.remainingEthAmount = tradeOffer.remainingEthAmount.sub(tradeEthAmount);

        _createOffer(ethAmount, erc20Amount, erc20, 0, deviation);
        uint256 amount;
        if (tradeChoices == TradeChoices.SendEthBuyERC20) {
            if (erc20Amount > tradeErc20Amount) {
                IERC20(erc20).safeTransferFrom(msg.sender, address(this), erc20Amount.sub(tradeErc20Amount));
            } else {
                IERC20(erc20).safeTransfer(msg.sender, tradeErc20Amount.sub(erc20Amount));
            }
            amount = ethAmount.add(tradeEthAmount);
        } else {
            IERC20(erc20).safeTransferFrom(msg.sender, address(this), tradeErc20Amount.add(erc20Amount));
            amount = ethAmount.sub(tradeEthAmount);
        }
        _ethContract.safeTransferFrom(msg.sender,address(this),amount);

        emit OfferTraded(offerIndex, erc20, msg.sender, tradeOffer.owner, tradeEthAmount, tradeErc20Amount);
        _priceDataContract.changePrice(erc20, tradeEthAmount, tradeErc20Amount, tradeOffer.blockNum.add(blockLimit));

        _husdContract.safeTransferFrom(msg.sender,address(this),tradeFee);
        require(_husdContract.approve(address(_bonusDataContract),tradeFee),"offerMain: approve failed");
        _bonusDataContract.depositUSDT(_tokenPairData.getTokenPair(erc20),address(this),tradeFee);
	
        if(tradeOffer.miningFee != 0){
            if(_isAllArbitrage(index)){
                _takeFeeOfBlock[tradeOffer.blockNum][erc20]=_takeFeeOfBlock[tradeOffer.blockNum][erc20].sub(tradeOffer.miningFee);
                tradeOffer.miningFee=0;
                bool allTake=true;
                for (uint i = 0; i < _indexOfBlock[tradeOffer.blockNum][erc20].length; i++) {
                    if(!_isAllArbitrage(_indexOfBlock[tradeOffer.blockNum][erc20][i])){
                        allTake=false;
                        break;
                    }
                }
                if(allTake){
                    _addInvalidOfBlock(erc20,block.number,2);
                }
            }else{
                uint256 originalEth = (tradeOffer.erc20Amount.mul(tradeOffer.remainingEthAmount).div(tradeOffer.remainingERC20Amount).add(tradeOffer.ethAmount)).mul(2);
                uint invalidFee = miningFee.mul(tradeEthAmount).div(originalEth);
                tradeOffer.miningFee = tradeOffer.miningFee.sub(invalidFee);
                _takeFeeOfBlock[tradeOffer.blockNum][erc20] = _takeFeeOfBlock[tradeOffer.blockNum][erc20].sub(invalidFee);
            }
        }
    }

    function withdraw(address offerIndex) public onlyEOA {
        uint256 index = uint256(offerIndex);
        Offer storage targetOffer = _offers[index];

        require(_isConfirmed(targetOffer.blockNum), "offerMain: offer has not benn confirmed");

        if (targetOffer.ethAmount > 0) {
            uint256 ethAmount = targetOffer.ethAmount;
            targetOffer.ethAmount = 0;
            _ethContract.safeTransfer(targetOffer.owner,ethAmount);
        }

        if (targetOffer.erc20Amount > 0) {
            uint256 erc20Amount = targetOffer.erc20Amount;
            targetOffer.erc20Amount = 0;
            IERC20(targetOffer.token).safeTransfer(targetOffer.owner, erc20Amount);
        }

        if (targetOffer.miningFee > 0) {
            uint256 mining = _getMiningOfBlock(targetOffer.token,targetOffer.blockNum);
            uint256 myMiningAmount;
            if(_isNoArbitrage(index)){
                uint256 takeMining = mining.mul(_takeFeeOfBlock[targetOffer.blockNum][targetOffer.token]).div(feeOfBlock[targetOffer.blockNum][targetOffer.token]);
                myMiningAmount = targetOffer.miningFee.mul(mining.sub(takeMining)).div(_noTakeFeeOfBlock[targetOffer.blockNum][targetOffer.token]);
            }else{
                myMiningAmount = targetOffer.miningFee.mul(mining).div(feeOfBlock[targetOffer.blockNum][targetOffer.token]);
            }
            targetOffer.miningFee = 0;
            if (_tokenPairData.isDefaultToken(targetOffer.token)) {
                require(_homerContract.transfer(targetOffer.owner, myMiningAmount), "OfferMain: homer transfer failed");
                if(_isReturnMiningOfBlock[targetOffer.blockNum][targetOffer.token]){
                    uint256 takeMining=mining.mul(_takeFeeOfBlock[targetOffer.blockNum][targetOffer.token]).div(feeOfBlock[targetOffer.blockNum][targetOffer.token]);
                    _mingContract.depositHomerInner(2,mining.sub(takeMining));
                    _isReturnMiningOfBlock[targetOffer.blockNum][targetOffer.token]=false;
                }
            } else {
                IERC20 htoken = IERC20(_tokenPairData.getTokenPair(targetOffer.token));
                require(htoken.transfer(targetOffer.owner, myMiningAmount), "OfferMain: hToken transfer failed.");
                if(_isReturnMiningOfBlock[targetOffer.blockNum][targetOffer.token]){
                    uint256 takeMining = mining.mul(_takeFeeOfBlock[targetOffer.blockNum][targetOffer.token]).div(feeOfBlock[targetOffer.blockNum][targetOffer.token]);
                    htoken.transfer(address(_hTokenMining),mining.sub(takeMining));
                    _isReturnMiningOfBlock[targetOffer.blockNum][targetOffer.token] = false;
                }
            }
        }
    }

    function getPriceCount() public view returns (uint256){
        return _offers.length;
    }

    function getPrice(uint256 index) public view returns (string memory){
        require(index < _offers.length, "offerMain: index overflow");
        return _convertOfferToString(_offers[index], index);
    }

    function find(address start, uint256 searchCount, uint256 maxReturnCount, address owner) public view returns (string memory){
        string memory result;
        uint256 curIndex = uint256(start) + 1;
        require(searchCount <= _offers.length, "offerMain: invalid search count");
        require(curIndex > 0 && curIndex <= _offers.length, "offerMain: invalid index");
        Offer memory targetOffer;
        while (curIndex > 0 && searchCount > 0 && maxReturnCount > 0) {
            targetOffer = _offers[curIndex-1];
            if (targetOffer.owner == owner) {
                maxReturnCount--;
                result = Strings.concat(result, _convertOfferToString(targetOffer, curIndex-1));
                result = Strings.concat(result, "|");
            }
            searchCount--;
            curIndex--;
        }
        return result;
    }

    function list(uint256 offset, uint256 pageCount) public view returns (string memory, uint256){
        string memory result;
        require(offset >= 0 && offset <= _offers.length, "offerMain: invalid offset");

        for (uint i = offset; i < _offers.length && i < offset.add(pageCount); i++) {
            if (i != offset) {
                result = Strings.concat(result, ";");
            }
            result = Strings.concat(result, _convertOfferToString(_offers[i], i));
        }
        return (result, _offers.length);
    }

    function query(address erc20,uint256 offset, uint256 pageCount) public view returns (string memory, uint256){
        string memory result;
        require(offset >= 0 && offset <= _erc20OffersIndex[erc20].length, "offerMain: invalid offset");
        for (uint i = offset; i < _erc20OffersIndex[erc20].length && i < offset.add(pageCount); i++) {
            if (i != offset) {
                result = Strings.concat(result, ";");
            }
            uint index = _erc20OffersIndex[erc20][i];
            result = Strings.concat(result,_convertOfferToString(_offers[index],index));
        }
        return (result, _erc20OffersIndex[erc20].length);
    }

    function queryToBeConfirmed(address erc20, uint256 searchCount, uint256 maxReturnCount, address owner) public view returns (string memory){
        string memory result;
        Offer memory targetOffer;
        uint256 curIndex = _erc20OffersIndex[erc20].length;
        uint256 offset = maxReturnCount;
        while (curIndex > 0 && searchCount >0 && maxReturnCount >0){
            targetOffer = _offers[_erc20OffersIndex[erc20][curIndex-1]];
            if((!_isConfirmed(targetOffer.blockNum)) || (targetOffer.owner == owner && (targetOffer.ethAmount != 0 || targetOffer.erc20Amount != 0))){
                if (offset != maxReturnCount) {
                    result = Strings.concat(result, ";");
                }
                result = Strings.concat(result, _convertOfferToString(targetOffer, curIndex-1));
                maxReturnCount--;
            }
            searchCount--;
            curIndex--;
        }
        return result;
    }

    function setMiningFee(uint256 fee) public onlyAdmin {
        miningFee = fee;
    }

    function setTradeFee(uint256 fee) public onlyAdmin {
        tradeFee = fee;
    }

    function _isConfirmed(uint256 blockNum) public view returns (bool){
        return block.number.sub(blockNum) > blockLimit;
    }

    function isDeviation(uint256 ethAmount, uint256 erc20Amount, address erc20) public view returns (bool){
        (uint256 latestEthAmount, uint256 latestERC20Amount,) = _priceDataContract.inquireLatestPriceInner(erc20);
        if (latestERC20Amount == 0 || latestEthAmount == 0)
            return false;
        uint256 suitableERC20Amount = ethAmount.mul(latestERC20Amount).div(latestEthAmount);
        return erc20Amount >= suitableERC20Amount.mul(uint256(100).add(deviationThreshold)).div(100) || erc20Amount <= suitableERC20Amount.mul(uint256(100).sub(deviationThreshold)).div(100);
    }

    function _createOffer(uint256 ethAmount, uint256 erc20Amount, address erc20, uint256 fee, bool deviation) private {
        require(ethAmount >= leastEth, "offerMain: Eth scale is smaller than the minimum scale");
        require(ethAmount.mod(offerSpan) == 0, "offerMain: Non compliant asset span");
        require(erc20Amount.mod(ethAmount.div(offerSpan)) == 0, "offerMain: Asset quantity is not divided");
        require(erc20Amount > 0);
        uint256 curIndex = _offers.length;
        emit NewOfferAdded(address(curIndex), erc20, ethAmount, erc20Amount, block.number.add(blockLimit), fee, msg.sender);
        _offers.push(Offer(msg.sender, deviation, erc20, ethAmount, erc20Amount, ethAmount, erc20Amount, block.number, fee));
        _erc20OffersIndex[erc20].push(curIndex);
        _indexOfBlock[block.number][erc20].push(curIndex);
        _priceDataContract.addPrice(erc20, ethAmount, erc20Amount, block.number.add(blockLimit), msg.sender);
    }

    function _isNoArbitrage(uint256 index) private view returns (bool){
        Offer storage tradeOffer = _offers[index];
        return tradeOffer.remainingERC20Amount==tradeOffer.erc20Amount&&tradeOffer.ethAmount==tradeOffer.remainingEthAmount;
    }

    function _isAllArbitrage(uint256 index) private view returns (bool){
        Offer storage tradeOffer = _offers[index];
        return tradeOffer.remainingEthAmount==0;
    }

    function _addInvalidOfBlock(address erc20,uint256 blockNum,uint256 isInvalid) private {
        if(_invalidOfBlock[erc20][blockNum]==0){
            _invalidKeyIndex[erc20][_invalidLength[erc20]]=blockNum;
            _invalidLength[erc20]=_invalidLength[erc20].add(1);
        }
        _invalidOfBlock[erc20][blockNum]=isInvalid;
    }

    function _getMiningOfBlock(address erc20,uint256 blockNum) private view returns (uint256){
        uint256 mining=miningOfBlock[blockNum][erc20];
        for(uint i=_invalidLength[erc20];i>0;i--){
            uint256 currentBlockNum=_invalidKeyIndex[erc20][i-1];
            if(currentBlockNum<blockNum){
                if(_invalidOfBlock[erc20][currentBlockNum]==1){
                    break;
                }
                mining = mining.add(miningOfBlock[currentBlockNum][erc20]);
            }
        }
        return mining;
    }

    function _convertOfferToString(Offer memory targetOffer, uint256 index) private pure returns (string memory){
        string memory offerString;
        offerString = Strings.concat(offerString, Strings.parseInt(index));
        offerString = Strings.concat(offerString, ",");
        offerString = Strings.concat(offerString, Strings.parseAddress(targetOffer.owner));
        offerString = Strings.concat(offerString, ",");
        offerString = Strings.concat(offerString, Strings.parseBoolean(targetOffer.isDeviate));
        offerString = Strings.concat(offerString, ",");
        offerString = Strings.concat(offerString, Strings.parseAddress(targetOffer.token));
        offerString = Strings.concat(offerString, ",");
        offerString = Strings.concat(offerString, Strings.parseInt(targetOffer.ethAmount));
        offerString = Strings.concat(offerString, ",");
        offerString = Strings.concat(offerString, Strings.parseInt(targetOffer.erc20Amount));
        offerString = Strings.concat(offerString, ",");
        offerString = Strings.concat(offerString, Strings.parseInt(targetOffer.remainingEthAmount));
        offerString = Strings.concat(offerString, ",");
        offerString = Strings.concat(offerString, Strings.parseInt(targetOffer.remainingERC20Amount));
        offerString = Strings.concat(offerString, ",");
        offerString = Strings.concat(offerString, Strings.parseInt(targetOffer.blockNum));
        offerString = Strings.concat(offerString, ",");
        offerString = Strings.concat(offerString, Strings.parseInt(targetOffer.miningFee));
        return offerString;
    }
}
