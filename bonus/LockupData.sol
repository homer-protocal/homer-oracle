// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import "../lib/SafeMath.sol";
import "../access/AccessController.sol";
import "../token/IERC20.sol";

interface ILockupData {
    function deposit(address token, address account, uint256 amount) external;

    function withdraw(address token, address account, uint256 amount) external;

    function getAmount(address token, address account) external view returns (uint256);
}

contract LockupData is AccessController, ILockupData {
    using SafeMath for uint256;

    mapping(address => mapping(address => uint256)) _lockupData;
    constructor(address config) public AccessController(config) {
    }

    function deposit(address token, address account, uint256 amount) public override onlyBonus {
        require(IERC20(token).transferFrom(account, address(this), amount), "lockupDate: transfer failed");
        _lockupData[token][account] =_lockupData[token][account].add(amount);
    }

    function withdraw(address token, address account, uint256 amount) public override onlyBonus {
        require(amount <= _lockupData[token][account], "lockupData: Insufficient storage balance");
        _lockupData[token][account] = _lockupData[token][account].sub(amount);
        require(IERC20(token).transfer(account, amount), "lockupData: transfer failed");
    }

    function getAmount(address token, address account) public view override returns (uint256){
        return _lockupData[token][account];
    }
}
