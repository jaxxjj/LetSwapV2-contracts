// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Config} from "./Config.sol";

library Helper {
    // Sort tokens by address to ensure consistent pool creation
    function sortTokens(
        Config.TokenConfig memory tokenA, 
        Config.TokenConfig memory tokenB
    ) internal pure returns (Config.TokenConfig memory token0, Config.TokenConfig memory token1) {
        if (tokenA.addr < tokenB.addr) {
            return (tokenA, tokenB);
        }
        return (tokenB, tokenA);
    }

    // Calculate sqrtPriceX96 from price and decimals
    function calculateSqrtPriceX96(
        uint256 price,
        uint8 token0Decimals,
        uint8 token1Decimals
    ) internal pure returns (uint160) {
        // For 1:1 price between stablecoins
        if (token0Decimals == token1Decimals) {
            return 79228162514264337593543950336;  // 1.0 * 2^96
        }
        
        // If decimals are different, adjust the price
        uint256 decimalAdjustment = 10 ** uint256(token1Decimals > token0Decimals ? 
            token1Decimals - token0Decimals : 
            token0Decimals - token1Decimals);
            
        uint256 adjustedPrice;
        if (token1Decimals > token0Decimals) {
            adjustedPrice = price * decimalAdjustment;
        } else {
            adjustedPrice = price / decimalAdjustment;
        }
        
        // Calculate square root and multiply by 2^96
        uint256 sqrtPrice = sqrt(adjustedPrice);
        return uint160(sqrtPrice * (1 << 96));
    }

    // Helper function to calculate square root
    function sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        
        // Using binary search for square root
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }
} 