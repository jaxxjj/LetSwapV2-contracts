// script/WithdrawLiquidity.s.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/LetSwapPool.sol";

contract WithdrawLiquidity is Script {
    address constant POOL = 0xa1C147d72746B1cA4f15A4256C6CaB7e3C6F7191;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        LetSwapPool pool = LetSwapPool(POOL);

        vm.startBroadcast(deployerPrivateKey);

        // 1. First burn the liquidity
        (uint256 amount0, uint256 amount1) = pool.burn(
            -240,
            240,
            10000000   // withdraw all liquidity
        );

        // 2. Then collect the tokens
        pool.collect(
            msg.sender,          // recipient
            -240,
            240,
            uint128(amount0),    // amount to collect for token0
            uint128(amount1)     // amount to collect for token1
        );

        vm.stopBroadcast();

        console.log("Withdrawn token0:", amount0);
        console.log("Withdrawn token1:", amount1);
    }
}