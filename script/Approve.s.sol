// script/ApproveAndMint.s.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/interfaces/IERC20.sol";
import "../src/LetSwapPool.sol";

contract Approve is Script {
    // Pool and token addresses
    address constant POOL = 0xa1C147d72746B1cA4f15A4256C6CaB7e3C6F7191;
    address constant TOKEN0 = 0x9557921b189CB5DA63277a51A5321205D9F6BDc6;
    address constant TOKEN1 = 0x36138804A07495c7BB8A88718e791aCF0b3b5857;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        IERC20(TOKEN0).approve(POOL, type(uint256).max);
        IERC20(TOKEN1).approve(POOL, type(uint256).max);
        
        LetSwapPool pool = LetSwapPool(POOL);
        pool.mint(
            msg.sender,
            -240,  // tickLower
            240,   // tickUpper
            1000000000000000  // liquidity amount
        );
        vm.stopBroadcast();
    }
    
}

