// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "../access/AccessController.sol";
import "../lib/SafeMath.sol";
import "../lib/SafeERC20.sol";
import "../lib/Strings.sol";
import "../token/IERC20.sol";
import "../token/HToken.sol";
import {ITokenPairData} from "./TokenPairData.sol";

contract TokenAuction is AccessController {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 private _homerContract;
    ITokenPairData private _tokenPairContract;

    address private _destructionAddress;

    uint256 public duration = 5 days;
    uint256 public miniHomer = 2000 ether;
    uint256 public miniInterval = 200 ether;
    uint256 public incentivePercent = 50;

    uint256 public tokenNum = 1;

    struct Auction {
        uint256 endTime;
        uint256 bid;
        address bidder;
        uint256 remain;
    }

    //0:ht;1:ela;2:eth
    mapping(uint256 => mapping(address => Auction)) private _auctions;
    mapping(uint256 => address[]) private _auctionTokens;

    constructor(address config) public AccessController(config){
        _initInstanceVariables();
    }

    function _initInstanceVariables() internal override {
        super._initInstanceVariables();
        _homerContract = IERC20(getContractAddress("homer"));
        _tokenPairContract = ITokenPairData(getContractAddress("tokenPairData"));
        _destructionAddress = getContractAddress("destruction");
    }

    function start(address token, uint256 amount,uint256 index) public {
        require((_tokenPairContract.getTokenPair(token) == address(0x0) || _isValidTokenIndex(token,index)), "TokenAuction: token already exists");
        require(_auctions[index][token].endTime == 0, "TokenAuction: token is on sale");
        require(!_tokenPairContract.isBlocked(token), "TokenAuction: token is blocked");
        require(amount >= miniHomer, "TokenAuction: 'amount' must be greater than 'miniHomer'");

        require(_homerContract.transferFrom(msg.sender, address(this), amount), "TokenAuction: transfer failed");

        IERC20 tokenERC20 = IERC20(token);
        tokenERC20.safeTransferFrom(msg.sender, address(this), 1);
        require(tokenERC20.balanceOf(address(this)) == 1, "TokenAuction: verify token failed");
        tokenERC20.safeTransfer(msg.sender, 1);
        require(tokenERC20.balanceOf(address(this)) == 0, "TokenAuction: verify token failed");


        Auction memory auction = Auction(now.add(duration), amount, msg.sender, amount);
        _auctions[index][token] = auction;
        _auctionTokens[index].push(token);
    }

    function bid(uint256 index,address token, uint256 amount) public {
        Auction storage auction = _auctions[index][token];
        require(auction.endTime != 0 && now <= auction.endTime, "TokenAuction: auction closed or not started");
        require(amount >= auction.bid.add(miniInterval), "TokenAuction: insufficient amount");

        uint256 excitation = amount.sub(auction.bid).mul(incentivePercent).div(100);
        require(_homerContract.transferFrom(msg.sender, address(this), amount), "TokenAuction: transfer failed");
        require(_homerContract.transfer(auction.bidder, auction.bid.add(excitation)), "TokenAuction: transfer failed");

        auction.remain = auction.remain.add(amount.sub(auction.bid)).sub(excitation);
        auction.bid = amount;
        auction.bidder = msg.sender;
    }

    function end(uint256 index, address token) public {
        uint256 nowTime = now;
        require(nowTime > _auctions[index][token].endTime && _auctions[index][token].endTime != 0, "TokenAuction: token is on sale");
        require(_homerContract.transfer(_destructionAddress, _auctions[index][token].remain), "TokenAuction: transfer failed");

        if(_tokenPairContract.getTokenPair(token) == address(0x0)){
            string memory tokenName = Strings.concat("HToken", _convertIntToString(tokenNum));
            string memory tokenSymbol = Strings.concat("H", _convertIntToString(tokenNum));
            HToken hToken = new HToken(tokenName, tokenSymbol, getConfiguration(), _auctions[index][token].bidder);
            _tokenPairContract.addTokenPair(token, address(hToken));
            tokenNum = tokenNum.add(1);
        }
        _setTokenIndex(token,index);
    }

    function getCount(uint256 index) public view returns (uint256){
        return _auctionTokens[index].length;
    }

    function getTokenAddress(uint256 index,uint256 num) public view returns (address){
        return _auctionTokens[index][num];
    }

    function getAuctionInfo(uint256 index,address token) public view returns (Auction memory){
        return _auctions[index][token];
    }

    function changeDuration(uint256 newDuration) public onlyAdmin {
        duration = newDuration;
    }

    function changeMiniHomer(uint256 newMiniHomer) public onlyAdmin {
        miniHomer = newMiniHomer;
    }

    function _isValidTokenIndex(address token,uint256 index) private view returns(bool){
        bool valid;
        if(index == 0){
            valid = _tokenPairContract.isHtToken(token);
        }else if(index == 1){
            valid = _tokenPairContract.isElaToken(token);
        }else {
            valid = _tokenPairContract.isEthToken(token);
        }
        return valid;
    }

    function _setTokenIndex(address token,uint256 index) private {
        if(index == 0){
            _tokenPairContract.enableHtToken(token);
        }else if(index == 1){
            _tokenPairContract.enableElaToken(token);
        }else {
            _tokenPairContract.enableEthToken(token);
        }
    }

    function _convertIntToString(uint256 iv) private pure returns (string memory) {
        bytes memory buf = new bytes(64);
        uint256 index = 0;
        do {
            buf[index++] = byte(uint8(iv % 10 + 48));
            iv /= 10;
        } while (iv > 0 || index < 4);
        bytes memory str = new bytes(index);
        for(uint256 i = 0; i < index; ++i) {
            str[i] = buf[index - i - 1];
        }
        return string(str);
    }
}
