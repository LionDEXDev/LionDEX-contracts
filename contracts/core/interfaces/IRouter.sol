// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

interface IRouter {
    function createIncreasePosition(
        address _inToken,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _minOut,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _acceptablePrice,
        uint256 _insuranceLevel,
        uint256 _executionFee
    ) external payable returns (bytes32);

    function createDecreasePosition(
        address _inToken,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _acceptablePrice,
        uint256 _insuranceLevel,
        uint256 _minOut,
        uint256 _executionFee,
        bool _withdrawETH
    ) external payable returns (bytes32);

    function increasePositionRequestKeysStart() external returns (uint256);

    function decreasePositionRequestKeysStart() external returns (uint256);

    function executeIncreasePositions(
        uint256 _count,
        address payable _executionFeeReceiver
    ) external;

    function executeDecreasePositions(
        uint256 _count,
        address payable _executionFeeReceiver
    ) external;
}
