// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.6.0;

import "./Configuration.sol";

contract AccessController {

    Configuration private _config;

    event ConfigurationChanged(address indexed origin, address indexed config);
    constructor(address config) public {
        _config = Configuration(config);
    }

    function changeConfig(address config) public virtual onlyAdmin returns (bool){
        emit ConfigurationChanged(address(_config), config);
        _config = Configuration(config);
        _initInstanceVariables();
        return true;
    }

    modifier onlyEOA() {
        require(msg.sender == tx.origin, "AccessController: only allow EOA access");
        _;
    }

    modifier onlyAdmin() {
        require(_config.isAdmin(msg.sender), "AccessController: only allow admin access");
        _;
    }

    modifier onlyOfferMain(){
        require((_config.getContractAddress("offerMain") == msg.sender
            || _config.getContractAddress("elaOfferMain") == msg.sender
            || _config.getContractAddress("ethOfferMain") == msg.sender), "AccessController: only allow offerMain access");
        _;
    }

    modifier onlyBonus(){
        require(_config.getContractAddress("bonus") == msg.sender, "AccessController: only allow bonus access");
        _;
    }

    modifier onlyTokenAuction(){
        require(_config.getContractAddress("tokenAuction") == msg.sender, "AccessController: only allow offerMain access");
        _;
    }

    modifier onlyHTokenMining(){
        require(_config.getContractAddress("hTokenMining") == msg.sender, "AccessController: only allow hTokenMining access");
        _;
    }

    modifier onlyPriceService(){
        require(_config.getContractAddress("priceService") == msg.sender, "AccessController: only allow priceService access");
        _;
    }

    function getConfiguration() internal view returns (address){
        return address(_config);
    }

    function getContractAddress(string memory name) public view returns (address){
        return _config.getContractAddress(name);
    }

    function addAdmin(address account) public onlyAdmin {
        _config.addAdmin(account);
    }

    function revokeAdmin(address account) public onlyAdmin {
        _config.revokeAdmin(account);
    }

    function _initInstanceVariables() internal virtual {}
}
