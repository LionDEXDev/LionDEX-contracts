// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;
import "./IVault.sol";

interface IVaultUtil {
    //keep it in case in the first start vault cannot afford loss
    function isGlobalShortDataReady() external view returns (bool);

    function isGlobalLongDataReady() external view returns (bool);

    function globalShortAveragePrices(address _token)
        external
        view
        returns (uint256);

    function globalLongAveragePrices(address _token)
        external
        view
        returns (uint256);

    function getNextGlobalShortData(
        address _account,
        address _indexToken,
        uint256 _nextPrice,
        uint256 _sizeDelta,
        bool _isIncrease
    ) external view returns (uint256, uint256);

    function getNextGlobalLongData(
        address _account,
        address _indexToken,
        uint256 _nextPrice,
        uint256 _sizeDelta,
        bool _isIncrease
    ) external view returns (uint256, uint256);

    function updateGlobalData(IVault.UpdateGlobalDataParams memory p) external;

    function updateGlobal(
        address _indexToken,
        uint256 price,
        uint256 _sizeDelta,
        bool _isLong,
        bool _isIncrease
    ) external;

    function getLPPrice() external view returns (uint256);

    function getGlobalShortProfitLP(address _token)
        external
        view
        returns (bool, uint256);

    function getGlobalLongProfitLP(address _token)
        external
        view
        returns (bool, uint256);
}
