// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract USDC is ERC20 {
    constructor() ERC20("USDC", "USDC") {
        _mint(msg.sender, 100000000 * 10**decimals());
    }
    function decimals() public pure override returns (uint8) {
        return 6;
    }
    function mint(address to) public {
        _mint(to, 100 * 10**decimals());
    }
}
