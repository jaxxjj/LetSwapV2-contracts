# LetSwap V2: Modern Implementation of Uniswap V3

## Overview

LetSwap V2 is a modernized implementation of Uniswap V3's groundbreaking concentrated liquidity AMM design, upgraded to Solidity 0.8.20. This implementation maintains the core innovations of Uniswap V3 while leveraging newer language features for enhanced security and efficiency.

### Key Improvements

1. **Solidity 0.8 Upgrade**
   - Built-in overflow/underflow checks
   - Custom error messages for gas optimization
   - More precise error handling
   - Enhanced compiler optimizations

2. **Concentrated Liquidity**
   - Capital efficiency through focused liquidity provision
   - LPs can concentrate capital in active price ranges
   - Up to 4000x capital efficiency vs traditional AMMs
   - Customizable price ranges for different strategies

3. **Tick-Based System**
   - Precise price increments (0.01% per tick)
   - Efficient price range tracking
   - Optimized gas usage through bitmap structure
   - Flexible tick spacing for different pools

### Technical Architecture

The system maintains Uniswap V3's core features while modernizing the implementation:
- Tick-based price management
- Square root price representation (sqrtPriceX96)
- Position-based liquidity tracking
- Fee growth accumulation per position
- Flash loan capabilities

### Implementation Benefits

1. **Enhanced Security**
   - Automatic arithmetic safety checks
   - Explicit function visibility
   - Modern compiler features
   - Comprehensive testing suite

2. **Gas Optimization**
   - Efficient bitmap operations
   - Optimized math libraries
   - Strategic use of custom errors
   - Minimal storage operations

3. **Developer Experience**
   - Clear code structure
   - Comprehensive documentation
   - Modern testing framework
   - Simplified integration patterns

This implementation serves as both a production-ready AMM and an educational resource for understanding advanced DeFi concepts.

# Understanding Ticks, Prices and Storage

## Basic Price Relationship
x = token 0
y = token 1
p = price of x in terms of y = y/x
p = 1.0001^tick * decimals0/decimals1

## Tick and Price Explanation
Each tick represents a 0.01% (1.0001x) price increase from the previous tick. 
For example:
- Tick 0: Base price (adjusted for token decimals)
- Tick 1: Price is 1.0001x higher than tick 0
- Tick 100: Price is (1.0001)^100 higher than tick 0

tick spacing = number of ticks to skip when the price moves
- Lower tick spacing (e.g., 1): More granular prices, higher gas costs
- Higher tick spacing (e.g., 60): Less granular prices, lower gas costs

Example: In a USDC/ETH pool
- At tick 0: price = 1.0001^0 * (10^6/10^18) = 10^-12
- At tick 202719: price ≈ 2000 USDC per ETH

## sqrtPriceX96
X = token 0
Y = token 1
p = price of X in terms of Y = Y/X
p = (sqrtPriceX96 / 2^96)^2 * (decimalsX / decimalsY)
sqrtPriceX96 = sqrt(p) * 2^96

## Store Tick into Bitmap
The bitmap structure efficiently stores initialized ticks:

1. Word Position (16 bits):
   - Calculated as: tick >> 8 (divide by 256)
   - Maps to storage slot in tick bitmap
   - Each word stores 256 ticks

2. Bit Position (8 bits):
   - Calculated as: tick & 0xFF (remainder of tick/256)
   - Position within the 256-bit word
   - 1 = initialized tick, 0 = uninitialized

Example for tick 12345:
- Word position = 12345 >> 8 = 48
- Bit position = 12345 & 0xFF = 57
- Stored in word 48, bit 57 of bitmap

Benefits:
- Gas-efficient tick tracking
- Compact storage representation
- Fast next tick lookup
- Minimal state updates

## Contract Architecture

### Core Contracts

1. **LetSwapPool.sol**
   - Central pool contract
   - Manages liquidity positions
   - Executes swaps
   - Tracks global state
   ```solidity
   struct Slot0 {
       uint160 sqrtPriceX96;  // Current sqrt price
       int24 tick;            // Current tick
       bool unlocked;         // Reentrancy lock
   }
   ```

2. **Position Management**
   - Tracks individual positions
   - Manages fees per position
   - Handles liquidity updates
   ```solidity
   struct Info {
       uint128 liquidity;
       uint256 feeGrowthInside0LastX128;
       uint256 feeGrowthInside1LastX128;
       uint128 tokensOwed0;
       uint128 tokensOwed1;
   }
   ```

### Math Libraries

1. **SqrtPriceMath.sol**
   - Computes price updates during swaps
   - Calculates token amounts
   - Handles rounding directions

2. **SwapMath.sol**
   - Computes swap steps
   - Calculates fees
   - Determines price impacts

3. **TickMath.sol**
   - Converts between ticks and prices
   - Enforces tick bounds
   - Handles tick spacing

## Key Operations

### Swap Execution
1. Input validation
2. Current price and liquidity check
3. Compute next tick crossing
4. Calculate amounts and fees
5. Update pool state
6. Transfer tokens

### Liquidity Provision
1. Validate tick range
2. Compute required token amounts
3. Transfer tokens to pool
4. Update position
5. Update tick bitmap

### Fee Collection
1. Calculate fees earned
2. Update fee growth trackers
3. Transfer fees to recipient

## Concentrated Liquidity Mechanics

![Liquidity Distribution](/assets/image.png)

Traditional AMM (V2):
- Liquidity spread across entire range
- Capital inefficiency
- Constant product formula: x * y = k

Concentrated Liquidity (V3):
- Liquidity focused in specific ranges
- Higher capital efficiency
- Virtual reserves per tick range

## Implementation Considerations

### Gas Optimization
- Bitmap for tick tracking
- Square root price for calculations
- Efficient fee accounting

### Safety Measures
- Reentrancy protection
- Overflow/underflow checks
- Price bound validation

### Edge Cases
- Zero liquidity handling
- Price range boundaries
- Fee precision

## Technical Insights

1. **Price Representation**
   - Using square root prices reduces multiplication complexity
   - Q64.96 format balances precision and range
   - Tick system provides deterministic price points

2. **Position Management**
   - Each position tracks its own fee growth
   - Liquidity can be added/removed independently
   - Positions can overlap

3. **Swap Routing**
   - Swaps can cross multiple tick boundaries
   - Each crossing requires recalculation
   - Fee computation per step

## References
- [Uniswap V3 Core Whitepaper](https://uniswap.org/whitepaper-v3.pdf)
- [Technical Documentation](https://docs.uniswap.org/protocol/reference/core/UniswapV3Pool)
- [Math Specifications](https://atiselsts.github.io/pdfs/uniswap-v3-liquidity-math.pdf)