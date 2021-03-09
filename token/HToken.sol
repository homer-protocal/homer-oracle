// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import "../lib/SafeMath.sol";
import "./ERC20.sol";
import "../access/AccessController.sol";

interface IHToken is IERC20 {
    function mint(uint256 amount) external returns (bool);

    function getBlockInfo() external view returns (uint256, uint256);

    function getBidder() external view returns (address);

}
contract HToken is IHToken, ERC20, AccessController {
    using SafeMath for uint256;

    uint256 private _createdBlock;
    uint256 private _recentUsedBlock;
    address private _bidder;

    constructor(string memory name, string memory symbol, address config, address bidder) public ERC20(name, symbol) AccessController(config) {
        _createdBlock = block.number;
        _recentUsedBlock = block.number;
        _bidder = bidder;
    }

    function mint(uint256 amount) external override onlyHTokenMining returns (bool) {
        _mint(msg.sender, amount);
        _recentUsedBlock = block.number;
        return true;
    }

    function getBlockInfo() public view override returns (uint256, uint256){
        return (_createdBlock, _recentUsedBlock);
    }

    function getBidder() public view override returns (address){
        return _bidder;
    }

}
