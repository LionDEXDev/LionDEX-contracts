// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

interface IOracleV3 {

    function getSqrtTWAP(address uniswapV3Pool, uint32 twapInterval) external view returns (uint price);

}