// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library Config {
    struct TokenConfig {
        address addr;
        uint8 decimals;
    }

    struct NetworkTokens {
        TokenConfig WETH;
        TokenConfig USDT;
        TokenConfig USDC;
        TokenConfig DAI;
    }

    function getTokens(uint256 chainId) internal pure returns (NetworkTokens memory) {
        if (chainId == 11155111) { // Sepolia
            return NetworkTokens({
                WETH: TokenConfig(0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14, 18),
                USDT: TokenConfig(0x7169D38820dfd117C3FA1f22a697dBA58d90BA06, 6),
                USDC: TokenConfig(0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238, 6),
                DAI: TokenConfig(0x82fb927676b53b6eE07904780c7be9b4B50dB80b, 18)
            });
        } else if (chainId == 84532) { // Base Sepolia
            return NetworkTokens({
                WETH: TokenConfig(0x453f5d93A24feC85dAd475e58e2296784C5cc8bb, 18),
                USDT: TokenConfig(0x36138804A07495c7BB8A88718e791aCF0b3b5857, 6),
                USDC: TokenConfig(0x9557921b189CB5DA63277a51A5321205D9F6BDc6, 6),
                DAI: TokenConfig(0xa2527E126B0FB9065F06E2AdEd7a884970939aD3, 18)
            });
        } else if (chainId == 421614) { // Arbitrum Sepolia
            return NetworkTokens({
                WETH: TokenConfig(0xdD7C9A98627bFaE3d07061fBE38D8f4bC2907384, 18),
                USDT: TokenConfig(0x9865B4cf6Cb5332aF875D2aa35E332f6F9181a0b, 6),
                USDC: TokenConfig(0x0E7718f505B2994A8330459e0F75a981F7Bb7e8C, 6),
                DAI: TokenConfig(0x300606f4e4f37Cac651E34D4f7700546ac011a01, 18)
            });
        } else {
            revert("Unsupported chain");
        }
    }

    // Tick spacing for the simplified version
    function getTickSpacing() internal pure returns (int24) {
        return 60; // Using a standard tick spacing
    }
} 