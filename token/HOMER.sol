// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import "./ERC20.sol";

contract HOMER is ERC20 {

    uint256 private _INITIAL_SUPPLY = 300000000 ether;
    string private _name = "HOMER";
    string private _symbol = "HOMER";

    constructor() public ERC20(_name, _symbol){
        _mint(msg.sender, _INITIAL_SUPPLY);
    }
}
