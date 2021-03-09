// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.6.0;

import "../lib/EnumerableSet.sol";

contract Configuration{
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private _admins;
    // homer:
    // hToken:
    // offerMain
    // tokenAuction
    // tokenPairData
    // bonus
    // bonusRevenueData
    // savingData
    // lockupData
    // mining
    // coder
    // destruction
    // hTokenMining
    // husd
    // priceData
    // elaPriceData
    // ethPriceData
    // ela
    // eth
    mapping(string => address) private _contracts;

    event ContractChanged(string indexed name, address oldAddress, address newAddress);
    event AdminGranted(address indexed account);
    event AdminRevoked(address indexed account);

    constructor() public {
        _admins.add(msg.sender);
    }

    modifier onlyAdmin() {
        require(_admins.contains(tx.origin), "Configuration: caller is not admin");
        _;
    }
    function setContractAddress(string memory name, address contractAddress) public onlyAdmin returns (bool) {
        address oldAddress = _contracts[name];
        emit ContractChanged(name, oldAddress, contractAddress);
        _contracts[name] = contractAddress;
        return true;
    }

    function getContractAddress(string memory name) public view returns (address){
        return _contracts[name];
    }

    function addAdmin(address account) public onlyAdmin returns (bool){
        if (_admins.add(account)) {
            emit AdminGranted(account);
            return true;
        }
        return false;
    }

    function revokeAdmin(address account) public onlyAdmin returns (bool){
        require(_admins.length() > 1, "can not revoke the last admin");
        if (_admins.remove(account)) {
            emit AdminRevoked(account);
            return true;
        }
        return false;
    }

    function isAdmin(address account) public view returns (bool){
        return _admins.contains(account);
    }


}
