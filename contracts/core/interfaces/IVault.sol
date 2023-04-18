// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

interface IVault {
    struct Position {
        uint256 size; //LP
        uint256 collateral; //LP
        uint256 averagePrice;
        uint256 entryFundingRate;
        int256 realisedPnl;
        uint256 lastIncreasedTime;
        uint256 insurance; //max 50%
        uint256 insuranceLevel;
    }

    struct UpdateGlobalDataParams {
        address account;
        address indexToken;
        uint256 sizeDelta;
        uint256 price; //current price
        bool isIncrease;
        bool isLong;
        uint256 insuranceLevel;
        uint256 insurance;
    }

    function getPositionKey(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _insuranceLevel
    ) external pure returns (bytes32);

    function getPositionsOfKey(
        bytes32 key
    ) external view returns (Position memory);

    function getPositions(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _insuranceLevel
    ) external view returns (Position memory);

    function getMaxPrice(address _token) external view returns (uint256);

    function getMinPrice(address _token) external view returns (uint256);

    function tokenBalances(address _token) external view returns (uint256);

    function usdcToken() external view returns (address);

    function LPToken() external view returns (address);

    function feeReserves(address _token) external view returns (uint256);

    function allWhitelistedTokensLength() external view returns (uint256);

    function allWhitelistedTokens(
        uint256 index
    ) external view returns (address);

    function whitelistedTokens(address token) external view returns (bool);

    function getPosition(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _insuranceLevel
    )
        external
        view
        returns (uint256, uint256, uint256, uint256, bool, uint256, uint256);

    function getProfitLP(
        address _indexToken,
        uint256 _size,
        uint256 _averagePrice,
        bool _isLong,
        uint256 _lastIncreasedTime
    ) external view returns (bool, uint256);

    function USDC_DECIMALS() external view returns (uint256);

    function increasePosition(
        address _account,
        address _indexToken,
        uint256 _sizeDelta,
        uint256 _collateralDelta,
        bool _isLong,
        uint256 _insuranceLevel,
        uint256 feeLP
    ) external;

    function decreasePosition(
        address _account,
        address _indexToken,
        uint256 _sizeDelta,
        uint256 _collateralDelta,
        bool _isLong,
        address _receiver,
        uint256 _insuranceLevel,
        uint256 feeLP
    ) external returns (uint256, uint256);

    function insuranceOdds() external view returns (uint256);

    function BASIS_POINTS_DIVISOR() external view returns (uint256);

    function insuranceLevel(uint256 lvl) external view returns (uint256);

    function taxBasisPoints() external view returns (uint256);

    function getPositionFee(uint256 _sizeDelta) external view returns (uint256);
}
