// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.20;

interface IPool {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function flash(
        address recipient,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external;
}