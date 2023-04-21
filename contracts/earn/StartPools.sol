// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "../library/token/ERC20/IERC20.sol";
import "../library/token/ERC20/utils/SafeERC20.sol";
import "../library/utils/structs/EnumerableSet.sol";

interface ILionDEXRewardVault{
    function withdrawEth(uint256 amount) external;
    function withdrawToken(IERC20 token,uint256 amount) external;
}



contract StartPools is OwnableUpgradeable {
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 totalAmount; //deposit token's total amount
        uint256[] rewardDebt; //reward token's,0 for esLion;1 for eth
    }

    // Info of each pool.
    struct PoolInfo {
        uint32 startTime;
        uint32 lastRewardTime;
        uint256[] rewardTokenPerSecond; //0 for esLion;1 for eth
        uint256[] accRewardTokenPerShare; //0 for esLion;1 for eth
        uint256 totalStaked; //sum user's deposit token amount
    }

    uint256 public BasePoint = 1e4;
    uint256 public constant precise = 1e18;
    PoolInfo[] public poolInfo;
    //poolId=>user=>user info
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    uint32 public startTime;
    uint32 public duration = 60 days; //60 days
    uint32 public levelRatio;
    IERC20 public LP;

    IERC20 public esLion;
    ILionDEXRewardVault public rewardVault;
    uint32 public bonusEndTime;

    uint256[] public level;

    mapping(address => bool) private keeperMap;

    modifier onlyKeeper() {
        require(isKeeper(msg.sender), "StartPools: not keeper");
        _;
    }

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);

    function initialize(IERC20 _LP, IERC20 _esLion, ILionDEXRewardVault _rewardVault,uint32 _startTime) initializer public {
        __Ownable_init();
        keeperMap[msg.sender] = true;
        BasePoint = 10000;
        LP = _LP;
        esLion = _esLion;
        rewardVault = _rewardVault;
        startTime = _startTime;
        levelRatio = 9900;

        duration = 60 days;
        level.push(2000000e18);
        level.push(3000000e18);

        bonusEndTime = startTime + duration;
        //add pool
        poolInfo.push(
            PoolInfo(
                startTime,
                uint32(startTime), //lastRewardTime
                new uint256[](2),
                new uint256[](2), //accRewardTokenPerShare
                0 //totalStaked
            )
        );
        poolInfo.push(
            PoolInfo(
                0,
                uint32(startTime), //lastRewardTime
                new uint256[](2),
                new uint256[](2), //accRewardTokenPerShare
                0 //totalStaked
            )
        );
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function setRewardTokenPerSecond(
        uint256 _pid,
        uint256[] memory rewardTokenPerSecond
    ) public onlyKeeper {
        require(_pid < 2, "StartPools: pid invalid");
        updatePool(_pid);
        require(rewardTokenPerSecond.length == 2, "StartPools: rewardTokenPerSecond length wrong");
        poolInfo[_pid].rewardTokenPerSecond = rewardTokenPerSecond;
    }

    function pendingReward(
        uint256 _pid,
        address _user
    ) external view returns (uint256[] memory rewards) {
        require(_pid < poolInfo.length, "StartPools: pid not exists");

        PoolInfo memory pool = poolInfo[_pid];
        UserInfo memory user = userInfo[_pid][_user];
        if (pool.totalStaked == 0 || user.totalAmount == 0) {
            return rewards;
        }
        uint256 tokenLength = pool.rewardTokenPerSecond.length;
        rewards = new uint256[](tokenLength);

        for (uint i; i < tokenLength; i++) {
            uint256 multipier = getMultiplier(
                pool.lastRewardTime,
                uint32(block.timestamp)
            );
            uint256 reward = multipier * pool.rewardTokenPerSecond[i];
            uint256 accRewardPerShare = pool.accRewardTokenPerShare[i] +
                (reward * precise) /
                pool.totalStaked;
            rewards[i] =
                (user.totalAmount * accRewardPerShare) /
                precise -
                user.rewardDebt[i];
        }
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if(pool.startTime == 0){
            return;
        }
        if (block.timestamp <= pool.lastRewardTime) {
            return;
        }
        if (pool.totalStaked == 0) {
            pool.lastRewardTime = uint32(block.timestamp);
            return;
        }
        uint256 tokenLength = pool.rewardTokenPerSecond.length;
        for (uint i; i < tokenLength; i++) {
            uint256 multiplier = getMultiplier(
                pool.lastRewardTime,
                uint32(block.timestamp)
            );
            uint256 reward = multiplier * pool.rewardTokenPerSecond[i];

            pool.accRewardTokenPerShare[i] +=
                (reward * precise) /
                pool.totalStaked;
        }
        pool.lastRewardTime = uint32(block.timestamp);
    }

    // Deposit tokens to specific pool for reward
    function deposit(uint256 _pid, uint256 _amount) public {
        require(
            startTime <= uint32(block.timestamp),
            "StartPools: deposit not start yet"
        );

        checkPoolToken(_pid, _amount);
        PoolInfo storage pool = poolInfo[_pid];

        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);

        if (user.rewardDebt.length == 0) {
            user.rewardDebt = new uint256[](pool.rewardTokenPerSecond.length);
        }

        //transfer pending reward
        transferRewards(pool, user);

        if (_amount > 0) {
            require(pool.totalStaked + _amount <= level[_pid],"StartPools: exceed max cap");
            LP.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.totalAmount += _amount;
            pool.totalStaked += _amount;
        }
        for (uint i; i < pool.rewardTokenPerSecond.length; i++) {
            user.rewardDebt[i] =
                (user.totalAmount * pool.accRewardTokenPerShare[i]) /
                precise;
        }
        checkAndOpenNextPool(_pid);
        emit Deposit(msg.sender, _pid, _amount);
    }

    function withdraw(uint256 _pid, uint256 _amount) public {
        require(
            bonusEndTime <= uint32(block.timestamp),
            "StartPools: withdraw not start yet"
        );
        PoolInfo storage pool = poolInfo[_pid];
        require(pool.startTime > 0, "StartPools: pool not start yet");

        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);

        //transfer pending reward
        transferRewards(pool, user);

        require(
            _amount > 0 && user.totalAmount >= _amount,
            "StartPools: _amount invalid"
        );
        user.totalAmount -= _amount;
        pool.totalStaked -= _amount;
        LP.safeTransfer(address(msg.sender), _amount);

        for (uint i; i < pool.accRewardTokenPerShare.length; i++) {
            //if user's total amount is 0,rewardDebt will be set to 0
            user.rewardDebt[i] =
                (user.totalAmount * pool.accRewardTokenPerShare[i]) /
                precise;
        }

        emit Withdraw(msg.sender, _pid, _amount);
    }

    function transferRewards(
        PoolInfo storage pool,
        UserInfo storage user
    ) private {
        if (user.totalAmount == 0) {
            return;
        }
        uint256 pending = (user.totalAmount * pool.accRewardTokenPerShare[0]) /
            precise -
            user.rewardDebt[0];
        if (pending > 0) {
            rewardVault.withdrawToken(esLion,pending);
            esLion.safeTransfer(msg.sender, pending);
        }

        pending =
            (user.totalAmount * pool.accRewardTokenPerShare[1]) /
            precise -
            user.rewardDebt[1];
        if (pending > 0) {
            rewardVault.withdrawEth(pending);
            require(
                payable(msg.sender).send(pending),
                "StartPools: send eth false"
            );
        }
    }

    function checkPoolToken(uint256 pid, uint256 _amount) private view {
        PoolInfo storage currentPool = poolInfo[pid];
        require(currentPool.startTime > 0, "StartPools: pool not open");

        //only check if pool start when _amount is 0
        if (_amount == 0) {
            return;
        }

        require(
            bonusEndTime >= uint32(block.timestamp),
            "StartPools: deposit ended"
        );

        PoolInfo storage pool0 = poolInfo[0];
        if (pid == 0) {
            require(
                currentPool.totalStaked <= level[0],
                "StartPools: pool 0 is full"
            );
        } else if (pid == 1) {
            require(
                pool0.totalStaked >=
                    ((level[0] * uint256(levelRatio)) / uint256(BasePoint)),
                "StartPools: pool 0 not full"
            );
            require(
                currentPool.totalStaked <= level[1],
                "StartPools: pool 1 is full"
            );
        } else {
            revert("StartPools: pid invalid");
        }
    }

    function checkAndOpenNextPool(uint256 pid) private {
        //no need to open any pool when pid is 1
        if (pid > 0) {
            return;
        }
        PoolInfo storage pool1 = poolInfo[1];
        PoolInfo storage currentPool = poolInfo[pid];

        require(currentPool.startTime > 0, "StartPools: pool not open");

        if (currentPool.totalStaked >= (level[0]* uint256(levelRatio) / uint256(BasePoint))) {
            //open pool 1
            pool1.startTime = startTime;
            pool1.lastRewardTime = uint32(block.timestamp);
        }
    }

    //0 not open;1 normal;2 full;3 ended
    function getStatus() public view returns (uint256[] memory ret) {
        PoolInfo memory pool0 = poolInfo[0];
        PoolInfo memory pool1 = poolInfo[1];

        ret = new uint256[](2);
        if (pool0.startTime > block.timestamp) {
            ret[0] = 0;
        } else if ((block.timestamp < bonusEndTime)) {
            if (pool0.totalStaked < level[0]) {
                ret[0] = 1;
            } else {
                ret[0] = 2;
            }
        } else {
            ret[0] = 3;
        }

        if (pool1.startTime == 0 || pool1.startTime > block.timestamp) {
            ret[1] = 0;
        } else if ((block.timestamp < bonusEndTime)) {
            if (pool1.totalStaked < level[1]) {
                ret[1] = 1;
            } else {
                ret[1] = 2;
            }
        } else {
            ret[1] = 3;
        }
    }

    function getApr(
        uint256 pid,
        uint256 LPPrice,
        uint256 esLionPrice,
        uint256 ethPrice
    ) public view returns (uint256[2] memory ret) {
        require(pid < 2, "StartPools: pid invalid");
        require(
            LPPrice > 0 && esLionPrice > 0 && ethPrice > 0,
            "StartPools: price invalid"
        );
        // rewardTokenPerSecond*second per year *reward token usd price/total staked token usd value
        PoolInfo memory pool = poolInfo[pid];
        uint256 totalStaked = pool.totalStaked;
        if (totalStaked == 0) {
            return ret;
        }

        ret[0] =
            ((pool.rewardTokenPerSecond[0] * 365 days * esLionPrice) *
                1e12 *
                1e8) /
            totalStaked /
            LPPrice;

        ret[1] =
            ((pool.rewardTokenPerSecond[1] * 365 days * ethPrice) *
                1e12 *
                1e8) /
            totalStaked /
            LPPrice;
    }

    function getMultiplier(
        uint32 _from,
        uint32 _to
    ) public view returns (uint256) {
        if (_to <= bonusEndTime) {
            return _to - _from;
        } else if (_from >= bonusEndTime) {
            return 0;
        } else {
            return bonusEndTime - _from;
        }
    }

    function getPoolInfo(
        uint256 pid
    )
        public
        view
        returns (
            uint32 _startTime,
            uint32 lastRewardTime,
            uint256[] memory rewardTokenPerSecond,
            uint256[] memory accRewardTokenPerShare,
            uint256 totalStaked
        )
    {
        require(pid < poolInfo.length, "StartPools: invalid pid");
        _startTime = poolInfo[pid].startTime;
        rewardTokenPerSecond = poolInfo[pid].rewardTokenPerSecond;
        lastRewardTime = poolInfo[pid].lastRewardTime;
        accRewardTokenPerShare = poolInfo[pid].accRewardTokenPerShare;
        totalStaked = poolInfo[pid].totalStaked; //sum deposit token's staked amount
    }

    function getUserInfo(
        uint256 pid,
        address user
    ) public view returns (uint256 totalAmount, uint256[] memory rewardDebt) {
        require(pid < poolInfo.length, "StartPools: invalid pid");
        totalAmount = userInfo[pid][user].totalAmount;
        rewardDebt = userInfo[pid][user].rewardDebt;
    }

    function getTotalStakedLP() public view returns (uint256){
        if(poolInfo.length >1){
            return poolInfo[0].totalStaked + poolInfo[1].totalStaked;
        }else{
            return 0;
        }
    }

    function setLevel(uint256[2] calldata _level) public onlyOwner {
        require(level[0] >0 && level[1]>0,"level value wrong");
        level = _level;
    }

    function setDuration(uint32 _duration) public onlyOwner {
        duration = _duration;
        bonusEndTime = startTime + _duration;
    }

    function setLevelRatio(uint32 _levelRatio) public onlyOwner {
        levelRatio = _levelRatio;
    }

    function setKeeper(address addr, bool active) public onlyOwner {
        keeperMap[addr] = active;
    }

    function isKeeper(address addr) public view returns (bool) {
        return keeperMap[addr];
    }

    function recoverTokens(address _token, uint256 _amount) external onlyOwner {
        require(bonusEndTime < block.timestamp, "StartPools: not end yet");
        IERC20(_token).safeTransfer(msg.sender, _amount);
    }

    function recoverEth(uint256 _amount) external onlyOwner {
        require(bonusEndTime < block.timestamp, "StartPools: not end yet");
        require(
            payable(msg.sender).send(_amount),
            "StartPools: send eth false"
        );
    }

    receive() external payable {}
}
