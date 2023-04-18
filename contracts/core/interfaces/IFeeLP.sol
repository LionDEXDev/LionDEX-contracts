// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

interface IFeeLP {
    function balanceOf(address account) external view returns (uint256);

    function unlock(
        address user,
        address lockTo,
        uint256 amount,
        bool isIncrease
    ) external;

    function burnLocked(
        address user,
        address lockTo,
        uint256 amount,
        bool isIncrease
    ) external;

    function lock(
        address user,
        address lockTo,
        uint256 amount,
        bool isIncrease
    ) external;

    function locked(
        address user,
        address lockTo,
        bool isIncrease
    ) external view returns (uint256);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external;

    function transfer(address recipient, uint256 amount) external;

    function isKeeper(address addr) external view returns (bool);

    function decimals() external pure returns (uint8);

    function mintTo(address user, uint256 amount) external;

    function burn(address user, uint256 amount) external;
}
