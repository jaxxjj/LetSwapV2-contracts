// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/mock/USDC.sol";
import "../src/mock/USDT.sol";
import "../src/mock/DAI.sol";
import "../src/mock/WETH.sol";

contract DeployMocks is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        // Deploy mock tokens
        MockWETH weth = new MockWETH();
        USDC usdc = new USDC();
        USDT usdt = new USDT();
        DAI dai = new DAI();

        // Log addresses
        console.log("Mock tokens deployed:");
        console.log("WETH:", address(weth));
        console.log("USDC:", address(usdc));
        console.log("USDT:", address(usdt));
        console.log("DAI:", address(dai));

        // Verify decimals
        console.log("\nToken decimals:");
        console.log("WETH: 18");
        console.log("USDC:", usdc.decimals());
        console.log("USDT:", usdt.decimals());
        console.log("DAI:", dai.decimals());

        // Log initial supplies
        console.log("\nInitial supplies:");
        console.log("WETH: 0 (mintable via deposit)");
        console.log("USDC:", usdc.totalSupply() / 10**usdc.decimals());
        console.log("USDT:", usdt.totalSupply() / 10**usdt.decimals());
        console.log("DAI:", dai.totalSupply() / 10**dai.decimals());

        // Save deployment addresses to a file
        string memory deploymentData = vm.toString(address(weth));
        deploymentData = string.concat(deploymentData, "\n", vm.toString(address(usdc)));
        deploymentData = string.concat(deploymentData, "\n", vm.toString(address(usdt)));
        deploymentData = string.concat(deploymentData, "\n", vm.toString(address(dai)));
        vm.writeFile("deployed-mocks.txt", deploymentData);

        vm.stopBroadcast();
    }
}