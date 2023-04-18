// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "../library/utils/math/SafeMath.sol";
import "../library/token/ERC20/IERC20.sol";
import "../library/token/ERC20/extensions/IERC20Metadata.sol";
import "../library/token/ERC20/utils/SafeERC20.sol";
import "../library/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./interfaces/ILPToken.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IWETH.sol";

interface IGmxVault {
    function getFeeBasisPoints(
        address _token,
        uint256 _usdgDelta,
        uint256 _feeBasisPoints,
        uint256 _taxBasisPoints,
        bool _increment
    ) external view returns (uint256);

    function taxBasisPoints() external view returns (uint256);

    function mintBurnFeeBasisPoints() external view returns (uint256);

    function getMinPrice(address _token) external view returns (uint256);
    function getMaxPrice(address _token) external view returns (uint256);
    function tokenDecimals(address _token) external view returns (uint256);
}
interface ILionDexPool {
    function getTotalStakedLP() external view returns (uint256);
}


interface GLPRewardRouter {
    function unstakeAndRedeemGlp(
        address _tokenOut,
        uint256 _glpAmount,
        uint256 _minOut,
        address _receiver
    ) external returns (uint256);

    function mintAndStakeGlp(
        address _token,
        uint256 _amount,
        uint256 _minUsdg,
        uint256 _minGlp
    ) external returns (uint256);
}

interface RewardRouter {
    function claimFees() external;

    function claimEsGmx() external;

    function stakeEsGmx(uint256 _amount) external;

    function compound() external;
}

interface GLPmanager {
    function getAumInUsdg(bool maximise) external view returns (uint256);
    function getPrice(bool _maximise) external view returns (uint256);
}

contract LionDEXVault is OwnableUpgradeable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    ILPToken public LP = ILPToken(0x489ee077994B6658eAfA855C308275EAd8097C4A);

    IWETH public WETH = IWETH(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    IERC20 public USDC = IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    IERC20 public WBTC = IERC20(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f);
    IERC20 public EsGMX = IERC20(0xf42Ae1D54fd613C9bb14810b0588FaAa09a426cA);
    IERC20 public fsGLP = IERC20(0x1aDDD80E6039594eE970E5872D247bf0414C8903);
    IERC20 public GLP = IERC20(0x4277f8F2c384827B5273592FF7CeBd9f2C1ac258);

    GLPRewardRouter public GLPRouter =
        GLPRewardRouter(0xB95DB5B167D75e6d04227CfFFA61069348d271F5);
    RewardRouter public rewardRouter =
        RewardRouter(0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1);
    GLPmanager public GLPManager = GLPmanager(0x3963FfC9dff443c2A94f21b129D429891E32ec18);
    IGmxVault public gmxVault = IGmxVault(0x489ee077994B6658eAfA855C308275EAd8097C4A);

    uint256 public slippage = 5e15; //0.5%
    uint256 public totalGLP; //user staked token's and profit convert
    uint256 public basePoints = 1e18;
    mapping(address => bool) private keeperMap;
    uint256 public constant PRICE_PRECISION = 10 ** 30;
    uint256 public  constant USDG_DECIMALS = 18;
    address public teamAddress;
    address public earnAddress;
    address public startPool;
    address public otherPool;

    IVault public vault;
    bool public GMXNotEntryFlag;
    event BuyLP(
        address account,
        address receiver,
        address token,
        uint256 tokenAmount,
        uint256 LPAmount
    );

    event SellLP(
        address account,
        address receiver,
        address token,
        uint256 LPAmount,
        uint256 tokenAmount
    );
    event SplitReward(uint256 amount,uint256 toRewardRation,uint256 toTeamAmount,uint256 toRewardAmount);
    modifier onlyKeeper() {
        require(isKeeper(msg.sender), "LionDEXVault: not keeper");
        _;
    }

    function initialize(
        ILPToken _LP,
        address _teamAddress,
        address _earnAddress,
        address _startPool,
        address _otherPool
    ) initializer public {
        __Ownable_init();
        keeperMap[msg.sender] = true;
        LP = _LP;
        teamAddress = _teamAddress;
        earnAddress = _earnAddress;
        startPool = _startPool;
        otherPool  =_otherPool;

        WETH = IWETH(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
        USDC = IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
        WBTC = IERC20(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f);
        EsGMX = IERC20(0xf42Ae1D54fd613C9bb14810b0588FaAa09a426cA);
        fsGLP = IERC20(0x1aDDD80E6039594eE970E5872D247bf0414C8903);
        GLP = IERC20(0x4277f8F2c384827B5273592FF7CeBd9f2C1ac258);
        GLPRouter = GLPRewardRouter(0xB95DB5B167D75e6d04227CfFFA61069348d271F5);
        rewardRouter = RewardRouter(0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1);
        GLPManager = GLPmanager(0x3963FfC9dff443c2A94f21b129D429891E32ec18);
        gmxVault = IGmxVault(0x489ee077994B6658eAfA855C308275EAd8097C4A);

        slippage = 5e15; //0.5%

        basePoints = 1e18;
    }

    function enterETH() external payable nonReentrant {
        uint256 _amount = msg.value;
        require(_amount > 0, "LionDEXVault: invalid msg.value");
        require(!GMXNotEntryFlag,"LionDEXVault: GMX not allow entry");
        //stake to gmxf
        WETH.deposit{value: _amount}();
        uint256 GLPAmount = stakeGLP(_amount, address(WETH));
        uint256 canMint = GLPToLPAmount(GLPAmount);

        LP.mintTo(msg.sender, canMint);

        //update global data
        totalGLP = totalGLP.add(GLPAmount);

        emit BuyLP(msg.sender, msg.sender, address(WETH), _amount, canMint);
    }

    function leaveETH(uint256 _lpAmount) external payable nonReentrant {
        require(
            _lpAmount <= LP.balanceOf(msg.sender) && _lpAmount > 0,
            "LionDEXVault: balance too low"
        );
        uint256 originalLPAmount = _lpAmount;
        uint256 amountOutGLP = LPToGLPAmount(_lpAmount);

        totalGLP = totalGLP.sub(amountOutGLP);
        LP.burn(msg.sender, _lpAmount);

        uint256 amountSendOut = unstakeGLP(amountOutGLP, address(WETH));

        WETH.withdraw(amountSendOut);

        (bool success, ) = payable(msg.sender).call{value: amountSendOut}("");
        require(success, "LionDEXVault: Failed to send Ether");

        emit SellLP(
            msg.sender,
            msg.sender,
            address(WETH),
            originalLPAmount,
            amountSendOut
        );
    }

    function enter(uint256 _amount, address _token) public nonReentrant {
        require(
            _token == address(USDC) || _token == address(WBTC),
            "LionDEXVault: param invalid"
        );
        require(!GMXNotEntryFlag,"LionDEXVault: GMX not allow entry");
        IERC20 stakedToken = IERC20(_token);
        require(
            _amount <= stakedToken.balanceOf(msg.sender) && _amount > 0,
            "LionDEXVault: balance too low"
        );
        require(
            _amount <= stakedToken.allowance(msg.sender, address(this)),
            "LionDEXVault: allowance too low"
        );
        stakedToken.safeTransferFrom(msg.sender, address(this), _amount);

        uint256 GLPAmount = stakeGLP(_amount, address(stakedToken));
        uint256 canMint = GLPToLPAmount(GLPAmount);

        LP.mintTo(msg.sender, canMint);

        totalGLP = totalGLP.add(GLPAmount);

        emit BuyLP(msg.sender, msg.sender, _token, _amount, canMint);
    }

    function leave(uint256 _lpAmount, address _token) public nonReentrant {
        require(
            _token == address(USDC) || _token == address(WBTC),
            "LionDEXVault: param invalid"
        );
        require(
            _lpAmount <= LP.balanceOf(msg.sender) && _lpAmount > 0,
            "LionDEXVault: balance too low"
        );
        require(
            _lpAmount <= LP.allowance(msg.sender, address(this)),
            "LionDEXVault: allowance too low"
        );

        IERC20 stakedToken = IERC20(_token);
        uint256 originalLPAmount = _lpAmount;
        uint256 amountOutGLP = LPToGLPAmount(_lpAmount);

        totalGLP = totalGLP.sub(amountOutGLP);
        LP.burn(msg.sender, _lpAmount);

        uint256 amountSendOut = unstakeGLP(amountOutGLP, address(stakedToken));
        stakedToken.safeTransfer(msg.sender, amountSendOut);

        emit SellLP(
            msg.sender,
            msg.sender,
            _token,
            originalLPAmount,
            amountSendOut
        );
    }

    function cycleRewardsEsGMX() external onlyKeeper {
        rewardRouter.compound(); //this should all rewards recycle
    }

    function claimRewardsETH() external onlyKeeper {
        _claimRewardsETH();
    }

    function _claimRewardsETH() private {
        rewardRouter.claimFees();
        uint256 rewards = WETH.balanceOf(address(this));
        splitReward(rewards);
    }

    //owner stake token left to gmx
    function stakeToGmx(uint256 _amount, address _token) public onlyOwner {
        require(IERC20(_token).balanceOf(address(this)) >= _amount);
        totalGLP = totalGLP.add(stakeGLP(_amount, _token));
    }

    function GLPToLPAmount(
        uint256 _glpAmount
    ) public view returns (uint256 ret) {
        uint256 glpPrice = getGLPprice();
        uint256 LPPrice = getLPPrice();
        ret = _glpAmount.mul(glpPrice).div(LPPrice);
    }

    function LPToGLPAmount(
        uint256 _lpAmount
    ) public view returns (uint256 ret) {
        uint256 glpPrice = getGLPprice();
        uint256 LPPrice = getLPPrice();
        ret = _lpAmount.mul(LPPrice).div(glpPrice);
    }


    function recoverTokens(address _token, uint256 _amount) external onlyOwner {
        if(_token != address(fsGLP)){
            IERC20(_token).safeTransfer(msg.sender, _amount);
        }
    }

    function stakeGLP(
        uint256 _amount,
        address token
    ) private returns (uint256 ret) {
        IERC20(token).safeApprove(address(GLPManager), _amount);
        ret = GLPRouter.mintAndStakeGlp(token, _amount, 0, 0);
    }

    function unstakeGLP(
        uint256 _amount,
        address token
    ) private returns (uint256) {
        //caculate slippage
        uint256 tokenDecimal = IERC20Metadata(token).decimals();
        uint256 tokenAmount = _amount
        .mul(getGLPprice())
        .mul(1e12)
        .mul(10 ** tokenDecimal)
        .div(getPrice(token))
        .div(1e18);

        uint256 percentage = basePoints.sub(slippage);
        uint256 min_receive = tokenAmount.mul(percentage).div(basePoints);

        return
            GLPRouter.unstakeAndRedeemGlp(
                token,
                _amount,
                min_receive,
                address(this)
            );
    }


    function setLP(ILPToken _LP) external onlyOwner {
        LP = _LP;
    }
    function setVault(IVault _vault) external onlyOwner {
        vault = _vault;
    }

    function setSlippage(uint256 _slippage) external onlyOwner {
        require(_slippage <= basePoints, "LionDEXVault: not in range");
        slippage = _slippage;
    }

    function setKeeper(address addr, bool active) public onlyOwner {
        keeperMap[addr] = active;
    }

    function isKeeper(address addr) public view returns (bool) {
        return keeperMap[addr];
    }
    function setSplitFeeParams(
        address _teamAddress,
        address _earnAddress,
        address _startPool,
        address _otherPool
    ) external onlyOwner {
        teamAddress = _teamAddress;
        earnAddress = _earnAddress;
        startPool = _startPool;
        otherPool  =_otherPool;
    }
    //if GMX is not allowed to stake to gmx, should use Liondex exchange swap LP
    function setGMXNotEntryFlag(bool  _GMXNotEntryFlag) external onlyOwner {
        GMXNotEntryFlag = _GMXNotEntryFlag;
    }

    function splitReward(uint256 amount) private {
        if (amount == 0) {
            return;
        }
        WETH.withdraw(amount);
        uint256 toRewardRation = ILionDexPool(startPool).getTotalStakedLP().add(ILionDexPool(otherPool).getTotalStakedLP()).mul(basePoints).div(ILPToken(LP).totalSupply());
        uint256 toRewardAmount = amount.mul(toRewardRation).div(basePoints);
        uint256 toTeamAmount = amount.sub(toRewardAmount);

        (bool success, ) = payable(teamAddress).call{value: toTeamAmount}("");
        require(success, "LionDEXVault: Failed to send team Ether");
        (success, ) = payable(earnAddress).call{value: toRewardAmount}("");
        require(success, "LionDEXVault: Failed to send RewardVault Ether");
        emit SplitReward(amount,toRewardRation,toTeamAmount,toRewardAmount);
    }
    function updateGLPManager(GLPmanager newManager) external onlyOwner{
        GLPManager = newManager;
    }

    function updateGMXVault(IGmxVault _gmxVault) external onlyOwner{
        gmxVault = _gmxVault;
    }

    function getGLPprice() public view returns (uint256){
        return  GLPManager.getPrice(true).div(1e12); // GLP  price decision 10**18;
    }

    function getPrice(address _token) public view returns (uint256){
        return gmxVault.getMinPrice(_token); //decimal 10**30
    }

    function getLPPrice() public view returns (uint256) {
        if (address(vault) == address(0) || IERC20(address(LP)).totalSupply() == 0) {
            return getGLPprice(); // GLP  price decision 10**18
        }
        return vault.getMaxPrice(address(LP)).div(1e12);// price decision 10**18
    }

   function getBuyFeeBasisPoints(address _tokenIn, uint256 _amountIn) public view returns (uint256) {
       uint256 priceIn = gmxVault.getMinPrice(_tokenIn);
       uint256 tokenInDecimals = gmxVault.tokenDecimals(_tokenIn);

       uint256 _usdgAmount = _amountIn.mul(priceIn).div(PRICE_PRECISION);
       _usdgAmount = _usdgAmount.mul(10 ** USDG_DECIMALS).div(10 ** tokenInDecimals);
       return gmxVault.getFeeBasisPoints(_tokenIn, _usdgAmount, gmxVault.mintBurnFeeBasisPoints(), gmxVault.taxBasisPoints(), true);
   }

    function getSellFeeBasisPoints(address _tokenOut, uint256 _glpAmountIn) public view returns (uint256) {
        // calculate aum before sellUSDG
        uint256 aumInUsdg = GLPManager.getAumInUsdg(false);
        uint256 glpSupply = IERC20(GLP).totalSupply();

        uint256 _usdgAmount = _glpAmountIn.mul(aumInUsdg).div(glpSupply);
        return gmxVault.getFeeBasisPoints(_tokenOut, _usdgAmount, gmxVault.mintBurnFeeBasisPoints(), gmxVault.taxBasisPoints(), false);
    }

    receive() external payable {}
}
