// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "../access/AccessController.sol";
import "../lib/SafeMath.sol";
import "../lib/SafeERC20.sol";
import "../lib/Address.sol";
import "../token/IERC20.sol";
import {ITokenPairData}  from "../auction/TokenPairData.sol";
import {IBonusData} from "../bonus/BonusData.sol";
import {IHToken} from "../token/HToken.sol";

interface IPriceService{
    struct AWarrant {
        uint256 level;
        uint256 price;
        uint256 endBlock;
        bool activation;
    }

    function payForInquirePrice(uint256 index,address token, uint256 amountUSDT) external;

    function inquireLatestPrice(uint256 index,address token) external view returns (uint256 ethAmount, uint256 erc20Amount, uint256 blockNum);

    function addAWarrantAccount(address token,uint256 price) external;

    function activateAccount(address token) external;

    function getAWarrantLevel(address token) external view returns (uint256 level, uint256 endBlock, bool activation);

    function setPriceLevel(uint256 price, uint256 level) external;

    function setLevelCost(uint256 level, uint256 cost) external;
}

interface IPriceData {
    struct Price {
        uint256 ethAmount;
        uint256 erc20Amount;
        uint256 frontBlock;
        address priceOwner;
    }

    struct TokenInfo {
        mapping(uint256 => Price) prices;         // block number => Offer
        uint256 latestOfferBlock;
    }

    //    function addPriceCost(address token) external;

    function addPrice(address token, uint256 ethAmount, uint256 erc20Amount, uint256 endBlock, address account) external;

    function changePrice(address token, uint256 ethAmount, uint256 erc20Amount, uint256 endBlock) external;

    function inquireLatestPrice(address token) external view returns (uint256 ethAmount, uint256 erc20Amount, uint256 blockNum);

    function inquireLatestPriceFree(address token) external view returns (uint256 ethAmount, uint256 erc20Amount, uint256 blockNum);

    function inquireLatestPriceInner(address token) external view returns (uint256 ethAmount, uint256 erc20Amount, uint256 blockNum);

    function inquirePriceForBlock(address token, uint256 blockNum) external view returns (uint256 ethAmount, uint256 erc20Amount);
}

contract PriceService is IPriceService, AccessController {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 private _homerContract;
    IBonusData private _bonusDataContract;
    ITokenPairData private _tokenPairDataContract;
    address private _miningAddress;
    address private _hTokenMiningAddress;
    IERC20 private _contractUSDT;
    IPriceData private _priceData;
    IPriceData private _elaPriceData;
    IPriceData private _ethPriceData;


    //msg.sender=>token=>AWarrant
    mapping(address => mapping(address => AWarrant)) public tokenAWarrant;
    //key price value level
    mapping(uint256 => uint256) public priceLevel;
    mapping(uint256 => uint256) public levelCost;
    uint256[] private _prices = [20 ether,40 ether,80 ether];
    uint256[] private _cost = [50000000000000000,20000000000000000,5000000000000000];
    uint256 public noAWarrantCost = 100000000000000000;
    uint256 public effectBlock = 864000;
    uint256 public hTokenPercent = 80;
    mapping(uint256 => mapping(address => mapping(address => uint256))) paymentInformation;

    constructor(address config) public AccessController(config) {
        _initInstanceVariables();
    }

    function _initInstanceVariables() internal override {
        super._initInstanceVariables();
        _homerContract = IERC20(getContractAddress("homer"));
        _tokenPairDataContract = ITokenPairData(getContractAddress("tokenPairData"));
        _bonusDataContract = IBonusData(getContractAddress("bonusData"));
        _miningAddress = getContractAddress("mining");
        _hTokenMiningAddress = getContractAddress("hTokenMining");
        _contractUSDT = IERC20(getContractAddress("husd"));
        _priceData = IPriceData(getContractAddress("priceData"));
        _elaPriceData = IPriceData(getContractAddress("elaPriceData"));
        _ethPriceData = IPriceData(getContractAddress("ethPriceData"));
        _initAWarrantConfig();
    }

    function _initAWarrantConfig() internal {
        for(uint256 i=0;i<3;i++){
            uint256 level = i.add(1);
            priceLevel[_prices[i]]=level;
            levelCost[level]=_cost[i];
        }
    }

    function payForInquirePrice(uint256 index,address token, uint256 amountUSDT) public override {
        uint256 costUSDT;
        if(_verifyAWarrantAccount(msg.sender,token)){
            costUSDT = levelCost[tokenAWarrant[msg.sender][token].level];
        }else{
            costUSDT = noAWarrantCost;
        }
        require(amountUSDT >= costUSDT,"priceData: less than least cost");
        uint256 ethAmount;
        uint256 erc20Amount;
        uint256 blockNum;
        (ethAmount, erc20Amount, blockNum) = _getPriceDataByIndex(token,index);
        require(blockNum > 0, "priceData: no confirmed price;");

        address hToken = _tokenPairDataContract.getTokenPair(token);

        require(_contractUSDT.transferFrom(msg.sender,address(this),costUSDT),"priceData: transfer failed");
        require(_contractUSDT.approve(address(_bonusDataContract),costUSDT),"priceData:BonusData: approve failed");
        if (hToken == address(_homerContract)) {
            _bonusDataContract.depositUSDT(address(_homerContract),address(this),costUSDT);
        } else {
            _bonusDataContract.depositUSDT(address(_homerContract),address(this),costUSDT.sub(costUSDT.mul(hTokenPercent).div(100)));
            _bonusDataContract.depositUSDT(hToken,address(this),costUSDT.mul(hTokenPercent).div(100));
        }
        paymentInformation[index][token][msg.sender] = blockNum;
    }

    function inquireLatestPrice(uint256 index, address token) public view override returns (uint256 ethAmount, uint256 erc20Amount, uint256 blockNum){
        blockNum = paymentInformation[index][token][msg.sender];
        require(blockNum > 0,"priceData: no payment");
        (ethAmount,erc20Amount) = _getPriceDataForBlockByIndex(token,blockNum,index);
        return (ethAmount,erc20Amount,blockNum);
    }

    function addAWarrantAccount(address token,uint256 price) public override onlyEOA {
        require(!_verifyAWarrantAccount(msg.sender,token),"priceData: The account is in effect");
        require(!_verifyActivateAccount(msg.sender,token),"priceData: Account to be activated");
        require(priceLevel[price]!=0,"priceData: AW price does not meet asset span");
        tokenAWarrant[msg.sender][token]= AWarrant(priceLevel[price],price,0,false);
        address hTokenAddress = _tokenPairDataContract.getTokenPair(token);
        if (hTokenAddress == address(_homerContract)) {
            require(_homerContract.transferFrom(msg.sender, address(this), price), "priceData: homer transfer failed");
        } else {
            IHToken hToken = IHToken(hTokenAddress);
            require(hToken.transferFrom(msg.sender, address(this), price), "priceData: hToken transfer failed");
        }
    }

    function activateAccount(address token) public override onlyEOA {
        require(_verifyActivateAccount(msg.sender,token),"priceData: The account is not in the pending activation state");
        AWarrant storage aWarrant = tokenAWarrant[msg.sender][token];
        aWarrant.endBlock = block.number.add(effectBlock);
        aWarrant.activation = true;
        uint256 price = aWarrant.price;
        address hTokenAddress = _tokenPairDataContract.getTokenPair(token);
        if (hTokenAddress == address(_homerContract)) {
            require(_homerContract.transfer(_miningAddress, price), "priceData: homer transfer failed");
        } else {
            IHToken hToken = IHToken(hTokenAddress);
            require(hToken.transfer(_hTokenMiningAddress, price), "priceData: hToken transfer failed");
        }
    }

    function getAWarrantLevel(address token) public view override onlyEOA returns (uint256 level, uint256 endBlock,bool activation){
        return (tokenAWarrant[msg.sender][token].level,tokenAWarrant[msg.sender][token].endBlock,tokenAWarrant[msg.sender][token].activation);
    }

    function setPriceLevel(uint256 price, uint256 level) public override onlyAdmin {
        priceLevel[price] = level;
    }

    function setLevelCost(uint256 level, uint256 cost) public override onlyAdmin {
        levelCost[level] = cost;
    }

    function _verifyAWarrantAccount(address account,address token) private view returns (bool){
        AWarrant storage aWarrant = tokenAWarrant[account][token];
        return (aWarrant.level != 0 && block.number <= aWarrant.endBlock && aWarrant.activation);
    }

    function _verifyActivateAccount(address account,address token) private view returns (bool){
        AWarrant storage aWarrant = tokenAWarrant[account][token];
        return (aWarrant.level != 0 && aWarrant.endBlock ==0 && !(aWarrant.activation));
    }

    function _getPriceDataByIndex(address token,uint256 index) private view returns (uint256 ethAmount, uint256 erc20Amount, uint256 blockNum) {
        if(index == 0){
            (ethAmount, erc20Amount, blockNum) = _priceData.inquireLatestPrice(token);
        }else if(index == 1){
            (ethAmount, erc20Amount, blockNum) = _elaPriceData.inquireLatestPrice(token);
        }else {
            (ethAmount, erc20Amount, blockNum) = _ethPriceData.inquireLatestPrice(token);
        }
        return (ethAmount, erc20Amount, blockNum);
    }

    function _getPriceDataForBlockByIndex(address token,uint256 blockNum,uint256 index) private view returns (uint256 ethAmount, uint256 erc20Amount) {
        if(index == 0){
            (ethAmount, erc20Amount) = _priceData.inquirePriceForBlock(token,blockNum);
        }else if(index == 1){
            (ethAmount, erc20Amount) = _elaPriceData.inquirePriceForBlock(token,blockNum);
        }else {
            (ethAmount, erc20Amount) = _ethPriceData.inquirePriceForBlock(token,blockNum);
        }
        return (ethAmount, erc20Amount);
    }
}
