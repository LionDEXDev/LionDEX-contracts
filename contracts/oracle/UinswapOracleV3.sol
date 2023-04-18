// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./interfaces/IOracleV3.sol";
import "./interfaces/IUniswapV3Pool.sol";
import "./interfaces/IUniswapV3Factory.sol";
import "./libraries/TickMath.sol";
import "./libraries/FullMath.sol";

interface IERC20 {
    function decimals() external view returns (uint);
}

contract UinswapOracleV3 is IOracleV3{
    uint256 internal constant DECIMALS = 30;

    address public v3Factory;
    uint24[] public v3Fees;

    address public owner;

    constructor(address _v3Factory){
        owner = msg.sender;
        v3Factory = _v3Factory;
        v3Fees = new uint24[](4);
        v3Fees[0] = 100;
        v3Fees[1] = 500;
        v3Fees[2] = 3000;
        v3Fees[3] = 10000;
    }

    function setV3Fees(uint24[] calldata _v3Fees) external {
        require(msg.sender == owner, 'V3:no authorization');
        v3Fees = _v3Fees;
    }

    function getSqrtTWAP(address uniswapV3Pool, uint32 twapInterval) public view override returns (uint price) {
        IUniswapV3Pool pool = IUniswapV3Pool(uniswapV3Pool);
        (, , uint16 index, uint16 cardinality, , ,) = pool.slot0();
        (uint32 targetElementTime, , , bool initialized) = pool.observations((index + 1) % cardinality);
        if (!initialized) {
            (targetElementTime,,,) = pool.observations(0);
        }
        uint32 delta = uint32(block.timestamp) - targetElementTime;
        uint160 sqrtPriceX96;
        if (delta == 0) {
            (sqrtPriceX96,,,,,,) = pool.slot0();
        } else {
            if (delta < twapInterval) twapInterval = delta;
            uint32[] memory secondsAgos = new uint32[](2);
            secondsAgos[0] = twapInterval;
            // from (before)
            secondsAgos[1] = 0;
            // to (now)
            (int56[] memory tickCumulatives,) = pool.observe(secondsAgos);
            // tick(imprecise as it's an integer) to price
            sqrtPriceX96 = TickMath.getSqrtRatioAtTick(
                int24((tickCumulatives[1] - tickCumulatives[0]) / int56(uint56(twapInterval)))
            );
        }

        address tokenIn = pool.token0();
        address tokenOut = pool.token1();
        uint256 decimalsIn = IERC20(tokenIn).decimals();
        uint256 decimalsOut = IERC20(tokenOut).decimals();

        price = getQuoteAtTick(
            sqrtPriceX96,
            uint128(10 ** decimalsIn),
            tokenIn,
            tokenOut
        );

        if (decimalsOut < DECIMALS) {
            price = price * (10 ** (DECIMALS - decimalsOut));
        }

        if (decimalsOut > DECIMALS) {
            price = price / (10 ** (decimalsOut - DECIMALS));
        }
    }

    function getSqrtTWAPWithMaxLiquidity(address token0, address token1, uint32 twapInterval) external view returns (uint price) {
        address pool = getTargetPool(token0, token1);
        require(pool != address(0), 'pool invalid');
        return getSqrtTWAP(pool, twapInterval);
    }

    function getTargetPool(address token0, address token1) public view returns (address) {
        // find out the pool with best liquidity as target pool
        address pool;
        address tempPool;
        uint256 poolLiquidity;
        uint256 tempLiquidity;
        for (uint256 i = 0; i < v3Fees.length; i++) {
            tempPool = IUniswapV3Factory(v3Factory).getPool(token0, token1, v3Fees[i]);
            if (tempPool == address(0)) continue;
            tempLiquidity = uint256(IUniswapV3Pool(tempPool).liquidity());
            // use the max liquidity pool as index price source
            if (tempLiquidity > poolLiquidity) {
                poolLiquidity = tempLiquidity;
                pool = tempPool;
            }
        }
        return pool;
    }

    function getTargetPoolAddress(address token0, address token1) public view returns (address[] memory poolAddress) {
        address[] memory tempPoolAddress = new address[](v3Fees.length);
        uint cnt = 0;
        for (uint256 i = 0; i < v3Fees.length; i++) {
            address pool = IUniswapV3Factory(v3Factory).getPool(token0, token1, v3Fees[i]);
            if (pool != address(0)) {
                tempPoolAddress[cnt] = pool;
                ++cnt;
            }
        }
        if (cnt == tempPoolAddress.length) {
            return tempPoolAddress;
        }
        poolAddress = new address[](cnt);
        for (uint256 i = 0; i < cnt; i++) {
            poolAddress[i] = tempPoolAddress[i];
        }
    }

    function getQuoteAtTick(
        uint160 sqrtRatioX96,
        uint128 baseAmount,
        address baseToken,
        address quoteToken
    ) internal pure returns (uint256 quoteAmount) {
        // Calculate quoteAmount with better precision if it doesn't overflow when multiplied by itself
        if (sqrtRatioX96 <= type(uint128).max) {
            uint256 ratioX192 = uint256(sqrtRatioX96) * sqrtRatioX96;
            quoteAmount = baseToken < quoteToken
            ? FullMath.mulDiv(ratioX192, baseAmount, 1 << 192)
            : FullMath.mulDiv(1 << 192, baseAmount, ratioX192);
        } else {
            uint256 ratioX128 = FullMath.mulDiv(
                sqrtRatioX96,
                sqrtRatioX96,
                1 << 64
            );
            quoteAmount = baseToken < quoteToken
            ? FullMath.mulDiv(ratioX128, baseAmount, 1 << 128)
            : FullMath.mulDiv(1 << 128, baseAmount, ratioX128);
        }
    }

}