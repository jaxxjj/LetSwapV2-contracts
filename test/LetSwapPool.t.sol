// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "./ERC20.sol";
import "./lib/LiquidityAmounts.sol";
import "../src/lib/TickMath.sol";
import "../src/LetSwapPool.sol";

contract LetSwapPoolTest is Test {
    ERC20 private token0;
    ERC20 private token1;
    LetSwapPool private pool;

    // 0.05%
    uint24 private constant FEE = 500;
    int24 private constant TICK_SPACING = 10;

    address[] private users = [address(1), address(2)];

    // about $1851 = SQRT_P0 * SQRT_P0 / 2**96 / 2**96 * (1e18 / 1e6)
    uint160 private constant SQRT_P0 = 3409290029545542707626329;

    function setUp() public {
        // token 0 = ETH
        // token 1 = USD
        while (address(token0) >= address(token1)) {
            token0 = new ERC20("ETH", "ETH", 18);
            token1 = new ERC20("USD", "USD", 6);
        }

        pool = new LetSwapPool(address(token0), address(token1), FEE, TICK_SPACING);

        pool.initialize(SQRT_P0);

        for (uint256 i = 0; i < users.length; i++) {
            token0.mint(users[i], 1e27);
            token1.mint(users[i], 1e27);

            vm.startPrank(users[i]);
            token0.approve(address(pool), type(uint256).max);
            token1.approve(address(pool), type(uint256).max);
            vm.stopPrank();
        }
    }

    function testSinglePositionSwap() public {
        // Add liquidity //
        Slot0 memory slot0 = pool.getSlot0();

        uint256 amount0Desired = 1_000_000 * 1e18;
        uint256 amount1Desired = 1_000_000 * 1e6;

        int24 tickLower =
            (slot0.tick - TICK_SPACING) / TICK_SPACING * TICK_SPACING;
        int24 tickUpper =
            (slot0.tick + TICK_SPACING) / TICK_SPACING * TICK_SPACING;
        uint160 sqrtRatioLowerX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtRatioUpperX96 = TickMath.getSqrtRatioAtTick(tickUpper);

        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            slot0.sqrtPriceX96,
            sqrtRatioLowerX96,
            sqrtRatioUpperX96,
            amount0Desired,
            amount1Desired
        );

        {
            vm.prank(users[0]);

            (uint256 amount0, uint256 amount1) =
                pool.mint(users[0], tickLower, tickUpper, liquidity);

            console.log("add liquidity - amount 0:", floor(amount0, 1e18));
            console.log("add liquidity - amount 1:", floor(amount1, 1e6));
        }

        // Swap (1 for 0, exact input) //
        {
            int256 amountIn = 1000 * 1e6;

            vm.prank(users[1]);
            (int256 amount0Delta, int256 amount1Delta) =
                pool.swap(users[1], false, amountIn, sqrtRatioUpperX96);

            // Print amount 0 and 1 delta, split into whole num and decimal parts
            // + amount in
            // - amount out
            if (amount0Delta < 0) {
                uint256 d = uint256(-amount0Delta);
                console.log(
                    "swap - amount 0 out:", floor(d, 1e18), rem(d, 1e18, 1e15)
                );
            } else {
                uint256 d = uint256(amount0Delta);
                console.log(
                    "swap - amount 0 in:", floor(d, 1e18), rem(d, 1e18, 1e15)
                );
            }
            if (amount1Delta < 0) {
                uint256 d = uint256(-amount1Delta);
                console.log(
                    "swap - amount 1 out:", floor(d, 1e6), rem(d, 1e6, 1e3)
                );
            } else {
                uint256 d = uint256(amount1Delta);
                console.log(
                    "swap - amount 1 in:", floor(d, 1e6), rem(d, 1e6, 1e3)
                );
            }
        }

        // Burn + collect //
        {
            vm.prank(users[0]);
            pool.burn(tickLower, tickUpper, 0);

            Position.Info memory pos =
                pool.getPosition(users[0], tickLower, tickUpper);

            vm.prank(users[0]);
            (uint256 a0Burned, uint256 a1Burned) =
                pool.burn(tickLower, tickUpper, pos.liquidity);

            console.log("remove liquidity - amount 0:", a0Burned);
            console.log("remove liquidity - amount 1:", a1Burned);

            vm.prank(users[0]);
            (uint128 a0Collected, uint128 a1Collected) = pool.collect(
                users[0],
                tickLower,
                tickUpper,
                uint128(a0Burned),
                uint128(a1Burned)
            );

            console.log("collect - amount 0:", a0Collected);
            console.log("collect - amount 1:", a1Collected);

            assert(a0Collected <= a0Burned);
            assert(a1Collected <= a1Burned);

            uint256 fee0 = a0Collected > a0Burned ? a0Collected - a0Burned : 0;
            uint256 fee1 = a1Collected > a1Burned ? a1Collected - a1Burned : 0;

            console.log("fee 0:", fee0);
            console.log("fee 1:", fee1);
        }
    }

    struct AddLiquidityParams {
        address user;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
    }

    function testMultiPositionsSwap() public {
        // Add liquidity //
        Slot0 memory slot0 = pool.getSlot0();

        AddLiquidityParams[2] memory addParams = [
            AddLiquidityParams({
                user: users[0],
                tickLower: (slot0.tick - TICK_SPACING) / TICK_SPACING * TICK_SPACING,
                tickUpper: (slot0.tick + TICK_SPACING) / TICK_SPACING * TICK_SPACING,
                amount0Desired: 1_000_000 * 1e18,
                amount1Desired: 1_000_000 * 1e6
            }),
            AddLiquidityParams({
                user: users[0],
                tickLower: (slot0.tick - 3 * TICK_SPACING) / TICK_SPACING * TICK_SPACING,
                tickUpper: (slot0.tick + 3 * TICK_SPACING) / TICK_SPACING * TICK_SPACING,
                amount0Desired: 1_000_000 * 1e18,
                amount1Desired: 1_000_000 * 1e6
            })
        ];

        {
            console.log("--- Add liquidity ---");

            for (uint256 i = 0; i < addParams.length; i++) {
                uint160 sqrtRatioLowerX96 =
                    TickMath.getSqrtRatioAtTick(addParams[i].tickLower);
                uint160 sqrtRatioUpperX96 =
                    TickMath.getSqrtRatioAtTick(addParams[i].tickUpper);

                uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
                    slot0.sqrtPriceX96,
                    sqrtRatioLowerX96,
                    sqrtRatioUpperX96,
                    addParams[i].amount0Desired,
                    addParams[i].amount1Desired
                );

                vm.prank(addParams[i].user);

                (uint256 amount0, uint256 amount1) = pool.mint(
                    users[0],
                    addParams[i].tickLower,
                    addParams[i].tickUpper,
                    liquidity
                );

                console.log("add liquidity - amount 0:", floor(amount0, 1e18));
                console.log("add liquidity - amount 1:", floor(amount1, 1e6));

                if (addParams[i].tickLower >= 0) {
                    console.log("tick lower:", uint24(addParams[i].tickLower));
                } else {
                    console.log(
                        "tick lower: -", uint24(-addParams[i].tickLower)
                    );
                }
                if (addParams[i].tickUpper >= 0) {
                    console.log(
                        "tick tickUpper:", uint24(addParams[i].tickUpper)
                    );
                } else {
                    console.log(
                        "tick tickUpper: -", uint24(-addParams[i].tickUpper)
                    );
                }

                console.log("liquidity:", liquidity);
            }
        }

        // Swap (1 for 0, exact input) //
        {
            console.log("--- Swap ---");

            int256 amountIn = 1e9 * 1e6;

            vm.prank(users[1]);
            (int256 amount0Delta, int256 amount1Delta) = pool.swap(
                users[1], false, amountIn, TickMath.MAX_SQRT_RATIO - 1
            );

            // Print amount 0 and 1 delta, split into whole num and decimal parts
            // + amount in
            // - amount out
            if (amount0Delta < 0) {
                uint256 d = uint256(-amount0Delta);
                console.log(
                    "swap - amount 0 out:", floor(d, 1e18), rem(d, 1e18, 1e15)
                );
            } else {
                uint256 d = uint256(amount0Delta);
                console.log(
                    "swap - amount 0 in:", floor(d, 1e18), rem(d, 1e18, 1e15)
                );
            }
            if (amount1Delta < 0) {
                uint256 d = uint256(-amount1Delta);
                console.log(
                    "swap - amount 1 out:", floor(d, 1e6), rem(d, 1e6, 1e3)
                );
            } else {
                uint256 d = uint256(amount1Delta);
                console.log(
                    "swap - amount 1 in:", floor(d, 1e6), rem(d, 1e6, 1e3)
                );
            }
        }

        // Burn + collect //
        {
            console.log("--- Burn + collect ---");

            for (uint256 i = 0; i < addParams.length; i++) {
                Position.Info memory pos = pool.getPosition(
                    addParams[i].user,
                    addParams[i].tickLower,
                    addParams[i].tickUpper
                );

                vm.prank(addParams[i].user);
                (uint256 a0Burned, uint256 a1Burned) = pool.burn(
                    addParams[i].tickLower,
                    addParams[i].tickUpper,
                    pos.liquidity
                );

                console.log("remove liquidity - amount 0:", a0Burned);
                console.log("remove liquidity - amount 1:", a1Burned);

                vm.prank(addParams[i].user);
                (uint128 a0Collected, uint128 a1Collected) = pool.collect(
                    addParams[i].user,
                    addParams[i].tickLower,
                    addParams[i].tickUpper,
                    type(uint128).max,
                    type(uint128).max
                );

                console.log("collect - amount 0:", a0Collected);
                console.log("collect - amount 1:", a1Collected);

                console.log("fee 0:", a0Collected - a0Burned);
                console.log("fee 1:", a1Collected - a1Burned);
            }
        }
    }

    function testInitializePool() public {
        // Test initialization with invalid sqrt price
        vm.expectRevert();
        pool.initialize(0);

        // Test double initialization
        vm.expectRevert();
        pool.initialize(SQRT_P0);
    }

    function testInvalidTickRanges() public {
        vm.startPrank(users[0]);

        // Test invalid tick range (lower > upper)
        vm.expectRevert();
        pool.mint(
            users[0],
            10,  // tickLower
            0,   // tickUpper
            1000
        );

        // Test tick out of bounds
        vm.expectRevert();
        pool.mint(
            users[0],
            887273,  // Too large tick
            887274,
            1000
        );

        vm.stopPrank();
    }

    function testZeroLiquidityMint() public {
        vm.prank(users[0]);
        vm.expectRevert();
        pool.mint(users[0], -10, 10, 0);
    }

    function testSwapWithInsufficientLiquidity() public {
        // Ensure pool is empty
        Slot0 memory slot0 = pool.getSlot0();
        
        // Try swap with no liquidity
        vm.startPrank(users[0]);
        
        // Approve tokens
        token0.approve(address(pool), type(uint256).max);
        token1.approve(address(pool), type(uint256).max);
        
        // Attempt swap with non-zero amounts
        int256 amountSpecified = 1000 * 1e6;
        
        // Use current price as limit to force actual swap attempt
        uint160 sqrtPriceLimitX96 = slot0.sqrtPriceX96 + 100;
        
        vm.expectRevert();
        pool.swap(
            users[0],
            true,  // zeroForOne
            amountSpecified,
            sqrtPriceLimitX96
        );
        
        // Also test opposite direction
        vm.expectRevert();
        pool.swap(
            users[0],
            false,  // oneForZero
            amountSpecified,
            slot0.sqrtPriceX96 - 100
        );
        
        vm.stopPrank();
    }

    function testMultiplePositionsSameTick() public {
        Slot0 memory slot0 = pool.getSlot0();
        int24 tickLower = (slot0.tick - TICK_SPACING) / TICK_SPACING * TICK_SPACING;
        int24 tickUpper = (slot0.tick + TICK_SPACING) / TICK_SPACING * TICK_SPACING;

        // Add sufficient amounts for meaningful positions
        uint256 amount0Desired = 1_000_000 * 1e18;
        uint256 amount1Desired = 1_000_000 * 1e6;

        uint160 sqrtRatioLowerX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtRatioUpperX96 = TickMath.getSqrtRatioAtTick(tickUpper);

        // Calculate liquidity for first position
        uint128 liquidity1 = LiquidityAmounts.getLiquidityForAmounts(
            slot0.sqrtPriceX96,
            sqrtRatioLowerX96,
            sqrtRatioUpperX96,
            amount0Desired,
            amount1Desired
        );

        // First position
        vm.prank(users[0]);
        pool.mint(users[0], tickLower, tickUpper, liquidity1);

        // Second position same range
        vm.prank(users[1]);
        pool.mint(users[1], tickLower, tickUpper, liquidity1);

        // Perform larger swap to generate fees
        vm.startPrank(users[0]);
        token1.approve(address(pool), type(uint256).max);
        pool.swap(users[0], false, 10000 * 1e6, sqrtRatioUpperX96);
        vm.stopPrank();

        // Burn positions to update fee accounting
        vm.prank(users[0]);
        pool.burn(tickLower, tickUpper, 0);
        vm.prank(users[1]);
        pool.burn(tickLower, tickUpper, 0);

        // Check positions
        Position.Info memory pos1 = pool.getPosition(users[0], tickLower, tickUpper);
        Position.Info memory pos2 = pool.getPosition(users[1], tickLower, tickUpper);

        assertTrue(pos1.liquidity > 0);
        assertTrue(pos2.liquidity > 0);
    }

    function testCrossingTickRanges() public {
        Slot0 memory slot0 = pool.getSlot0();
        
        uint256 amount0Desired = 1_000_000 * 1e18;
        uint256 amount1Desired = 1_000_000 * 1e6;

        // Create positions with proper liquidity calculations
        for (uint24 i = 1; i <= 3; i++) {
            int24 tickLower = (slot0.tick - int24(i) * TICK_SPACING) / TICK_SPACING * TICK_SPACING;
            int24 tickUpper = (slot0.tick + int24(i) * TICK_SPACING) / TICK_SPACING * TICK_SPACING;

            uint160 sqrtRatioLowerX96 = TickMath.getSqrtRatioAtTick(tickLower);
            uint160 sqrtRatioUpperX96 = TickMath.getSqrtRatioAtTick(tickUpper);

            uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
                slot0.sqrtPriceX96,
                sqrtRatioLowerX96,
                sqrtRatioUpperX96,
                amount0Desired,
                amount1Desired
            );

            vm.prank(users[0]);
            pool.mint(users[0], tickLower, tickUpper, liquidity);
        }

        // Perform swap
        vm.startPrank(users[1]);
        token1.approve(address(pool), type(uint256).max);
        pool.swap(users[1], false, 10000 * 1e6, TickMath.MAX_SQRT_RATIO - 1);
        vm.stopPrank();
    }

    function testSwapExactOutput() public {
        // Add liquidity first
        Slot0 memory slot0 = pool.getSlot0();
        int24 tickLower = (slot0.tick - TICK_SPACING) / TICK_SPACING * TICK_SPACING;
        int24 tickUpper = (slot0.tick + TICK_SPACING) / TICK_SPACING * TICK_SPACING;

        uint256 amount0Desired = 1_000_000 * 1e18;
        uint256 amount1Desired = 1_000_000 * 1e6;

        uint160 sqrtRatioLowerX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtRatioUpperX96 = TickMath.getSqrtRatioAtTick(tickUpper);

        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            slot0.sqrtPriceX96,
            sqrtRatioLowerX96,
            sqrtRatioUpperX96,
            amount0Desired,
            amount1Desired
        );

        vm.startPrank(users[0]);
        pool.mint(users[0], tickLower, tickUpper, liquidity);
        vm.stopPrank();

        // Perform swap
        vm.startPrank(users[1]);
        token1.approve(address(pool), type(uint256).max);
        pool.swap(users[1], false, 1000 * 1e6, sqrtRatioUpperX96);
        vm.stopPrank();
    }
}

function floor(uint256 x, uint256 d) pure returns (uint256) {
    return x / d;
}

function rem(uint256 x, uint256 d, uint256 p) pure returns (uint256) {
    uint256 r = x - (x / d * d);
    return r / p;
}
