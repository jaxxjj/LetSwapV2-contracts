// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "./Config.sol";
import "./Helper.sol";
import "../src/LetSwapPool.sol";

contract DeployStablePools is Script {
    using Helper for *;

    struct PoolInfo {
        string name;
        address token0;
        address token1;
        uint8 token0Decimals;
        uint8 token1Decimals;
    }

    function run() external {
        // Get network configuration
        uint256 chainId = block.chainid;
        Config.NetworkTokens memory tokens = Config.getTokens(chainId);
        int24 tickSpacing = Config.getTickSpacing();
        uint24 fee = 0; 

        // Define pools to deploy
        PoolInfo[] memory pools = new PoolInfo[](3);

        // Pre-sort token pairs based on addresses
        if (tokens.USDC.addr < tokens.USDT.addr) {
            pools[0] = PoolInfo("USDC/USDT", tokens.USDC.addr, tokens.USDT.addr, tokens.USDC.decimals, tokens.USDT.decimals);
        } else {
            pools[0] = PoolInfo("USDT/USDC", tokens.USDT.addr, tokens.USDC.addr, tokens.USDT.decimals, tokens.USDC.decimals);
        }

        if (tokens.USDT.addr < tokens.DAI.addr) {
            pools[1] = PoolInfo("USDT/DAI", tokens.USDT.addr, tokens.DAI.addr, tokens.USDT.decimals, tokens.DAI.decimals);
        } else {
            pools[1] = PoolInfo("DAI/USDT", tokens.DAI.addr, tokens.USDT.addr, tokens.DAI.decimals, tokens.USDT.decimals);
        }

        if (tokens.USDC.addr < tokens.DAI.addr) {
            pools[2] = PoolInfo("USDC/DAI", tokens.USDC.addr, tokens.DAI.addr, tokens.USDC.decimals, tokens.DAI.decimals);
        } else {
            pools[2] = PoolInfo("DAI/USDC", tokens.DAI.addr, tokens.USDC.addr, tokens.DAI.decimals, tokens.USDC.decimals);
        }

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy and initialize pools
        for (uint256 i = 0; i < pools.length; i++) {
            require(pools[i].token0 < pools[i].token1, "Invalid token order");

            // Deploy pool
            LetSwapPool pool = new LetSwapPool(
                pools[i].token0,
                pools[i].token1,
                fee,
                tickSpacing
            );

            // Use fixed sqrtPriceX96 for 1:1 price
            uint160 sqrtPriceX96 = 79228162514264337593543950336;  // 1.0 * 2^96

            // Initialize pool
            pool.initialize(sqrtPriceX96);

            console.log(
                "Deployed %s pool at %s",
                pools[i].name,
                address(pool)
            );
            console.log("Initial sqrtPriceX96:", uint256(sqrtPriceX96));
            console.log("Token0:", pools[i].token0);
            console.log("Token1:", pools[i].token1);
            console.log("Token0 decimals:", pools[i].token0Decimals);
            console.log("Token1 decimals:", pools[i].token1Decimals);
            console.log("Fee:", fee);
            console.log("Tick Spacing:", tickSpacing);
            console.log("-------------------");
        }

        vm.stopBroadcast();

        console.log("\nDeployment Summary:");
        console.log("Network:", getNetworkName(chainId));
        console.log("Fee:", fee);
        console.log("Tick Spacing:", tickSpacing);
    }

    function getNetworkName(uint256 chainId) internal pure returns (string memory) {
        if (chainId == 11155111) return "Sepolia";
        if (chainId == 84532) return "Base Sepolia";
        if (chainId == 421614) return "Arbitrum Sepolia";
        return "Unknown";
    }
} 