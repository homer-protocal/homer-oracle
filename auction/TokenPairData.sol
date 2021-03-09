// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import "../access/AccessController.sol";
import "../token/ERC20.sol";
import "../lib/Strings.sol";

interface ITokenPairData {
    function addTokenPair(address token, address hToken) external;

    function changeTokenPair(address token, address hToken) external;

    function blockToken(address token) external;

    function unBlockToken(address token) external;

    function disableToken(address token) external;

    function enableToken(address token) external;

    function isBlocked(address token) external view returns (bool);

    function isEnabled(address token) external view returns (bool);

    function isHToken(address hToken) external view returns (bool);

    function isValidToken(address token) external view returns(bool);

    function getTokenPair(address token) external view returns (address);

    function getDefaultToken() external view returns(address);

    function isDefaultToken(address token) external view returns(bool);

    function isHtToken(address token) external view returns(bool);

    function isElaToken(address token) external view returns(bool);

    function isEthToken(address token) external view returns(bool);

    function enableHtToken(address token) external;

    function enableElaToken(address token) external;

    function enableEthToken(address token) external;

    function disableHtToken(address token) external;

    function disableElaToken(address token) external;

    function disableEthToken(address token) external;

}

contract TokenPairData is AccessController, ITokenPairData {

    mapping(address => address) public tokenPair;
    mapping(uint256 => address) private _tokenPairIndex;
    uint256 public tokenPairLength;
    mapping(address => bool) public hTokens;
    mapping(address => bool) public blockedToken;
    mapping(address => bool) public disabledToken;

    mapping(address => bool) public htToken;
    mapping(address => bool) public ethToken;
    mapping(address => bool) public elaToken;

    address public defaultToken;

    address private _homerAddress;

    event TokenPairChanged(address indexed token, address indexed hToken);

    constructor(address config) public AccessController(config){
        _initInstanceVariables();
    }

    function _initInstanceVariables() internal override {
        super._initInstanceVariables();
        _homerAddress = getContractAddress("homer");
    }

    function addTokenPair(address token, address hToken) public override onlyTokenAuction {
        require(hToken != address(0x0), "TokenPairDaa: hToken address can not be zero address");
        require(tokenPair[token] == address(0x0), "TokenPairData: token already exist");
        tokenPair[token] = hToken;
        _tokenPairIndex[tokenPairLength] = token;
        tokenPairLength = tokenPairLength + 1;
        hTokens[hToken] = true;
        emit TokenPairChanged(token, hToken);
    }

    function changeTokenPair(address token, address hToken) public override onlyAdmin {
        require(token != address(0x0), "tokenPairData: invalid token");
//        require(hToken != address(0x0), "tokenPairData: invalid hToken");

        hTokens[tokenPair[token]] = false;
        tokenPair[token] = hToken;
        emit TokenPairChanged(token, hToken);
    }

    function blockToken(address token) public override onlyAdmin {
        require(!blockedToken[token], "tokenPairData: token is blocked already");
        require(tokenPair[token] == address(0x0), "tokenPairData: token is effective");
        blockedToken[token] = true;
    }

    function unBlockToken(address token) public override onlyAdmin {
        require(blockedToken[token], "tokenPairData: token is not blocked");
        blockedToken[token] = false;
    }

    function disableToken(address token) public override onlyAdmin {
        require(!disabledToken[token], "tokenPairData: token is disabled");
        disabledToken[token] = true;
    }

    function enableToken(address token) public override onlyAdmin {
        require(disabledToken[token], "tokenPairData: token is enabled");
        disabledToken[token] = false;
    }

    function isBlocked(address token) public view override returns (bool){
        return blockedToken[token];
    }

    function isEnabled(address token) public view override returns (bool){
        return !disabledToken[token];
    }

    function isHToken(address hToken) public view override returns (bool) {
        return hTokens[hToken];
    }

    function getTokenPair(address token) public view override returns (address) {
        return tokenPair[token];
    }

    function setDefaultTokenPair(address token) public onlyAdmin {
        require(tokenPair[token] == address(0x0), "TokenPairData: token already exist");
        defaultToken = token;
        tokenPair[token] = _homerAddress;
        _tokenPairIndex[tokenPairLength] = token;
        tokenPairLength = tokenPairLength + 1;
        ethToken[token] = true;
        elaToken[token] = true;
        htToken[token] = true;
    }

    function getDefaultToken() external view override returns(address){
        return defaultToken;
    }

    function isDefaultToken(address token) external view override returns(bool){
        return (token == defaultToken);
    }

    function isValidToken(address token) public view override returns(bool){
        return tokenPair[token] != address(0x0);
    }

    function isHtToken(address token) public view override returns (bool) {
        return htToken[token];
    }

    function isElaToken(address token) public view override returns (bool) {
        return elaToken[token];
    }

    function isEthToken(address token) public view override returns (bool) {
        return ethToken[token];
    }

    function enableHtToken(address token) public override onlyTokenAuction {
        require(!htToken[token], "tokenPairData: ht token is enabled");
        htToken[token] = true;
    }

    function enableElaToken(address token) public override onlyTokenAuction {
        require(!elaToken[token], "tokenPairData: ela token is enabled");
        elaToken[token] = true;
    }

    function enableEthToken(address token) public override onlyTokenAuction {
        require(!ethToken[token], "tokenPairData: eth token is enabled");
        ethToken[token] = true;
    }

    function disableHtToken(address token) public override onlyAdmin {
        require(htToken[token], "tokenPairData: ht token is disable");
        htToken[token] = false;
    }

    function disableElaToken(address token) public override onlyAdmin {
        require(elaToken[token], "tokenPairData: ela token is disable");
        elaToken[token] = false;
    }

    function disableEthToken(address token) public override onlyAdmin {
        require(ethToken[token], "tokenPairData: eth token is disable");
        ethToken[token] = false;
    }

    function list(uint256 offset, uint256 pageCount) public view returns (string memory, uint256){
        string memory result;
        require(offset >= 0 && offset <= tokenPairLength, "TokenPairData: invalid offset");

        for (uint256 i = offset; i < tokenPairLength && i < (offset + pageCount); i++) {
            if (i != offset) {
                result = Strings.concat(result, ";");
            }
            result = Strings.concat(result, _convertTokenPairToString(i,_tokenPairIndex[i]));
        }
        return (result, tokenPairLength);
    }

    function _convertTokenPairToString(uint256 index,address token) private view returns (string memory){
        string memory tokenPairString;
        tokenPairString = Strings.concat(tokenPairString, Strings.parseInt(index));
        tokenPairString = Strings.concat(tokenPairString, ",");
        tokenPairString = Strings.concat(tokenPairString, ERC20(token).symbol());
        tokenPairString = Strings.concat(tokenPairString, ",");
        tokenPairString = Strings.concat(tokenPairString, Strings.parseAddress(token));
        tokenPairString = Strings.concat(tokenPairString, ",");
        tokenPairString = Strings.concat(tokenPairString, Strings.parseAddress(tokenPair[token]));
        tokenPairString = Strings.concat(tokenPairString, ",");
        tokenPairString = Strings.concat(tokenPairString, Strings.parseBoolean(isEnabled(token)));
        tokenPairString = Strings.concat(tokenPairString, ",");
        tokenPairString = Strings.concat(tokenPairString, Strings.parseBoolean(isHtToken(token)));
        tokenPairString = Strings.concat(tokenPairString, ",");
        tokenPairString = Strings.concat(tokenPairString, Strings.parseBoolean(isElaToken(token)));
        tokenPairString = Strings.concat(tokenPairString, ",");
        tokenPairString = Strings.concat(tokenPairString, Strings.parseBoolean(isEthToken(token)));
        return tokenPairString;
    }
}
