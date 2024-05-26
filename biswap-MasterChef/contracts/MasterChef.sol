pragma solidity 0.6.12;

library SafeBEP20 {
    using SafeMath for uint256;
    using Address for address;

    function safeTransfer(
        IBEP20 token,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(
            token,
            abi.encodeWithSelector(token.transfer.selector, to, value)
        );
    }

    function safeTransferFrom(
        IBEP20 token,
        address from,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(
            token,
            abi.encodeWithSelector(token.transferFrom.selector, from, to, value)
        );
    }

    /**
     * @dev Deprecated. This function has issues similar to the ones found in
     * {IBEP20-approve}, and its usage is discouraged.
     *
     * Whenever possible, use {safeIncreaseAllowance} and
     * {safeDecreaseAllowance} instead.
     */
    function safeApprove(
        IBEP20 token,
        address spender,
        uint256 value
    ) internal {
        // safeApprove should only be called when setting an initial allowance,
        // or when resetting it to zero. To increase and decrease it, use
        // 'safeIncreaseAllowance' and 'safeDecreaseAllowance'
        // solhint-disable-next-line max-line-length
        require(
            (value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeBEP20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(
            token,
            abi.encodeWithSelector(token.approve.selector, spender, value)
        );
    }

    function safeIncreaseAllowance(
        IBEP20 token,
        address spender,
        uint256 value
    ) internal {
        uint256 newAllowance = token.allowance(address(this), spender).add(
            value
        );
        _callOptionalReturn(
            token,
            abi.encodeWithSelector(
                token.approve.selector,
                spender,
                newAllowance
            )
        );
    }

    function safeDecreaseAllowance(
        IBEP20 token,
        address spender,
        uint256 value
    ) internal {
        uint256 newAllowance = token.allowance(address(this), spender).sub(
            value,
            "SafeBEP20: decreased allowance below zero"
        );
        _callOptionalReturn(
            token,
            abi.encodeWithSelector(
                token.approve.selector,
                spender,
                newAllowance
            )
        );
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     */
    function _callOptionalReturn(IBEP20 token, bytes memory data) private {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves. We use {Address.functionCall} to perform this call, which verifies that
        // the target address contains contract code and also asserts for success in the low-level call.

        bytes memory returndata = address(token).functionCall(
            data,
            "SafeBEP20: low-level call failed"
        );
        if (returndata.length > 0) {
            // Return data is optional
            // solhint-disable-next-line max-line-length
            require(
                abi.decode(returndata, (bool)),
                "SafeBEP20: BEP20 operation did not succeed"
            );
        }
    }
}
import "./BSWToken.sol";

interface IMigratorChef {
    function migrate(IBEP20 token) external returns (IBEP20);
}

// MasterChef is the master of BSW. He can make BSW and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once BSW is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract MasterChef is Ownable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;
    // Info of each user.
    struct UserInfo {
        uint256 amount; //【用户提供的lp份额】 How many LP tokens the user has provided.
        uint256 rewardDebt; //【用户已领取的收益（BSW）总数】 Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of BSWs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accBSWPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accBSWPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }
    // 【流动池的信息】Info of each pool.
    struct PoolInfo {
        IBEP20 lpToken; // 【LP token的合约地址】Address of LP token contract.
        uint256 allocPoint; // 【有多少分配点分配给这个池。 每个块分配bsw】How many allocation points assigned to this pool. BSWs to distribute per block.
        uint256 lastRewardBlock; // 【bsw分发发生的最新一个区块 】Last block number that BSWs distribution occurs.
        uint256 accBSWPerShare; //【该池子每份lp累计的分红累总额，乘以 1e12？？？】 Accumulated BSWs per share, times 1e12. See below.
    }
    // The BSW TOKEN!
    BSWToken public BSW;
    //【计算分红占比的分母，比如】Pools, Farms, Dev, Refs percent decimals
    uint256 public percentDec = 1000000;
    //【每个区块的产出总额中，质押lpToken分红占有的百分比】Pools and Farms percent from token per block
    uint256 public stakingPercent;
    //【合约收益地址一收益占总分红的百分比】Developers percent from token per block
    uint256 public devPercent;
    //【合约收益地址二收益占总分红的百分比】Referrals percent from token per block
    uint256 public refPercent;
    //【合约收益地址三收益占总分红的百分比】Safu fund percent from token per block
    uint256 public safuPercent;
    // 【合约收益地址一】Dev address.
    address public devaddr;
    // 【合约收益地址二】Safu fund.
    address public safuaddr;
    // 【合约收益地址三】Refferals commision address.
    address public refAddr;
    // 【合约收益地址最近一次领取收益的区块】 Last block then develeper withdraw dev and ref fee
    uint256 public lastBlockDevWithdraw;
    // 【每个区块产生的BSW数量，用于奖励lp质押分红】 BSW tokens created per block.
    uint256 public BSWPerBlock;
    // 【分红的乘数，用于挖矿时计算分红收益】Bonus muliplier for early BSW makers.
    uint256 public BONUS_MULTIPLIER = 1;
    // 【迁移合约--用于迁移lp合约】The migrator contract. It has a lot of power. Can only be set through governance (owner).
    IMigratorChef public migrator;
    // 【已添加的所有流动池】Info of each pool.
    PoolInfo[] public poolInfo;
    // 【每个用户添加的lp token信息】 of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // 【开始挖矿的起始区块】The block number when BSW mining starts.
    uint256 public startBlock;
    // 【存入的BSW总量】Deposited amount BSW in MasterChef  TODO
    uint256 public depositedBsw;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );

    //@brief 构造函数
    //@param _BSW BSW合约,这个token作为第0个lp池。
    //@param _devaddr 收益地址
    //@param _refAddr 收益地址
    //@param _safuaddr 收益地址
    //@param _BSWPerBlock 每个区块产出BSW数量
    //@param _startBlock 产出计算起始区块
    //@param _stakingPercent 质押lpToken分红占有的百分比
    //@param _devPercent 收益地址分红占有的百分比
    //@param _refPercent 收益地址分红占有的百分比
    //@param _safuPercent 收益地址分红占有的百分比
    constructor(
        BSWToken _BSW,
        address _devaddr,
        address _refAddr,
        address _safuaddr,
        uint256 _BSWPerBlock,
        uint256 _startBlock,
        uint256 _stakingPercent,
        uint256 _devPercent,
        uint256 _refPercent,
        uint256 _safuPercent
    ) public {
        BSW = _BSW;
        devaddr = _devaddr;
        refAddr = _refAddr;
        safuaddr = _safuaddr;
        BSWPerBlock = _BSWPerBlock;
        startBlock = _startBlock;
        stakingPercent = _stakingPercent;
        devPercent = _devPercent;
        refPercent = _refPercent;
        safuPercent = _safuPercent;
        lastBlockDevWithdraw = _startBlock;

        // staking pool
        poolInfo.push(
            PoolInfo({
                lpToken: _BSW,
                allocPoint: 1000, //质押BSW挖矿分红占总分红的股份数默认未1000
                lastRewardBlock: startBlock,
                accBSWPerShare: 0
            })
        );

        totalAllocPoint = 1000; //所有池子挖矿的总股份数=每个池子股份数的累加值
    }

    //变更乘数（倍数），可以通过这个值间接变更每个区块的BSW产量
    function updateMultiplier(uint256 multiplierNumber) public onlyOwner {
        BONUS_MULTIPLIER = multiplierNumber;
    }

    //@brief 获取已上架的lpToken总数
    //@return lp总数
    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    //@brief 该合约的收益地址提取收益（收益地址可更改）
    function withdrawDevAndRefFee() public {
        require(lastBlockDevWithdraw < block.number, "wait for new block");
        uint256 multiplier = getMultiplier(lastBlockDevWithdraw, block.number);
        uint256 BSWReward = multiplier.mul(BSWPerBlock);
        BSW.mint(devaddr, BSWReward.mul(devPercent).div(percentDec));
        BSW.mint(safuaddr, BSWReward.mul(safuPercent).div(percentDec));
        BSW.mint(refAddr, BSWReward.mul(refPercent).div(percentDec));
        lastBlockDevWithdraw = block.number;
    }

    //@brief 【上架一个新的lptoken，只有管理员能调用该接口。并且千万不要重复新增lptoken】
    //@param _allocPoint 这个lp池子占有的股份数，在分配分红时，根据每个lp池子的股份数除以总股份数得到的比例分配，计算该池子产生多少分红（所有池子的累加值必须等于总值）。
    //@param _lpToken lpToken的合约地址
    //@param _withUpdate TODO
    function add(
        uint256 _allocPoint,
        IBEP20 _lpToken,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock
            ? block.number
            : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                accBSWPerShare: 0
            })
        );
    }

    // Update the given pool's BSW allocation point. Can only be called by the owner.
    //@brief 【变更一个lpToken占有的股份数，只有管理员能调用该接口】
    //@param _pid lpToken初次添加时分配的id
    //@param _allocPoint 这个lp池子占有的股份数，在分配分红时，根据每个lp池子的股份数除以总股份数得到的比例分配，计算该池子产生多少分红（所有池子的累加值必须等于总值）。
    //@param _withUpdate  TODO
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(
            _allocPoint
        );
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    //@brief 变更migrator合约地址(1、只允许管理员调用。2、migrator合约允许将池子lpToken从原合约迁移到新的合约)
    //@param _migrator 新的migrator
    function setMigrator(IMigratorChef _migrator) public onlyOwner {
        migrator = _migrator;
    }

    //@brief 变更migrator合约地址(1、只允许管理员调用。2、任何人可以调用该接口。3、前提是管理员添加了可信的migrator合约)
    //@param _migrator 新的migrator
    function migrate(uint256 _pid) public {
        require(address(migrator) != address(0), "migrate: no migrator");
        PoolInfo storage pool = poolInfo[_pid];
        IBEP20 lpToken = pool.lpToken;
        uint256 bal = lpToken.balanceOf(address(this));
        lpToken.safeApprove(address(migrator), bal);
        IBEP20 newLpToken = migrator.migrate(lpToken);
        require(bal == newLpToken.balanceOf(address(this)), "migrate: bad");
        pool.lpToken = newLpToken;
    }

    //@brief 根据始末区块计算分红收益的乘数
    //@param 分红收益乘数（默认是始末俩区块差）
    function getMultiplier(uint256 _from, uint256 _to)
        public
        view
        returns (uint256)
    {
        return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

    //@brief 查询用户待领取分红份额
    //@param _pid 需要查询的池子的编号
    //@param _user 需要查询的用户地址
    //@return 该用户待领取的分红份额
    function pendingBSW(uint256 _pid, address _user)
        external
        view
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accBSWPerShare = pool.accBSWPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (_pid == 0) {
            lpSupply = depositedBsw;
        }

        //如果有新区块，重新计算每份lp的分红总累加值
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(
                pool.lastRewardBlock,
                block.number
            );
            uint256 BSWReward = multiplier
                .mul(BSWPerBlock)
                .mul(pool.allocPoint)
                .div(totalAllocPoint)
                .mul(stakingPercent)
                .div(percentDec);
            accBSWPerShare = accBSWPerShare.add(
                BSWReward.mul(1e12).div(lpSupply)
            );
        }
        //个人待领取分红总额=(个人质押lp总份额*单位lp分红累加值/指定的巨大数)-已领取的分红总额
        return user.amount.mul(accBSWPerShare).div(1e12).sub(user.rewardDebt);
    }

    //@brief 更新所有池子的可分红信息
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    //@brief 更新指定池子的可分红信息
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        //获取当前合约拥有指定lp的总份额
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (_pid == 0) {
            lpSupply = depositedBsw;
        }
        if (lpSupply <= 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        //根据始末区块获取这些区块分红的乘数
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        //lp质押分红=分红乘数（默认是区块差）* 每个区块的BSW产量 * lp质押占有股份比例 * lp质押的分红占比
        // =分红乘数（默认是区块差）
        //（乘）每个区块的BSW产量 lp质押股份占比=pool.allocPoint/totalAllocPoint
        //（乘）这个池子占股份数 lp质押股份占比=pool.allocPoint/totalAllocPoint
        //（除）总共的股份数
        //（乘）每个区块的产出总额中，质押lpToken分红占的百分比 lp质押分红占比=stakingPercent/percentDec
        // (除) 分红占比的分母  stakingPercent/percentDec lp质押分红占比=stakingPercent/percentDec
        uint256 BSWReward = multiplier
            .mul(BSWPerBlock)
            .mul(pool.allocPoint)
            .div(totalAllocPoint)
            .mul(stakingPercent)
            .div(percentDec);
        //铸币，将本次BSW先铸造出来，并先存放于当前合约中
        BSW.mint(address(this), BSWReward);
        pool.accBSWPerShare = pool.accBSWPerShare.add(
            BSWReward.mul(1e12).div(lpSupply)
        );
        pool.lastRewardBlock = block.number;
    }

    //@brief 用户将lp token转入当前合约参与挖矿
    //@param _pid 指定池子的编号
    //@param _amount 本次存入lp份额
    function deposit(uint256 _pid, uint256 _amount) public {
        require(_pid != 0, "deposit BSW by staking");

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        //每次存入份额前，先把之前的分红结算给该用户
        if (user.amount > 0) {
            uint256 pending = user
                .amount
                .mul(pool.accBSWPerShare)
                .div(1e12)
                .sub(user.rewardDebt);
            safeBSWTransfer(msg.sender, pending);
        }

        //将该用户指定的lp份额转进本合约
        pool.lpToken.safeTransferFrom(
            address(msg.sender),
            address(this),
            _amount
        );
        //用户份额加
        user.amount = user.amount.add(_amount);
        //根据当前份额，记录该用户已领取的总收益，下次有收益时，可领收益=用户可令总收益-本次记录的已领收益数  （由此可以推断出rewardDebt并不等于用户实际领取的分红总额，只是用来辅助计算带领取分红份额）
        user.rewardDebt = user.amount.mul(pool.accBSWPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    //@brief 用户提取收益，并取回自己的lpToken
    //@param _pid 指定池子的编号
    //@param _amount 本次提取的lpToken份额
    function withdraw(uint256 _pid, uint256 _amount) public {
        require(_pid != 0, "withdraw BSW by unstaking");

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        //更新池子的每份lp累加收益
        updatePool(_pid);
        //获取用户可领取的收益
        uint256 pending = user.amount.mul(pool.accBSWPerShare).div(1e12).sub(
            user.rewardDebt
        );
        //收益转给用户，并记录本次领取后的标志位值
        safeBSWTransfer(msg.sender, pending);
        user.amount = user.amount.sub(_amount);
        user.rewardDebt = user.amount.mul(pool.accBSWPerShare).div(1e12);
        //将将lp转回给用户
        pool.lpToken.safeTransfer(address(msg.sender), _amount);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    //@brief 用户质押BSW用于挖矿，（本质上跟其它的lp挖矿一样，这里将BSW当作lpToken）
    //@param _amount 本次质押的BSW份额
    function enterStaking(uint256 _amount) public {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[0][msg.sender];
        updatePool(0);
        if (user.amount > 0) {
            uint256 pending = user
                .amount
                .mul(pool.accBSWPerShare)
                .div(1e12)
                .sub(user.rewardDebt);
            if (pending > 0) {
                safeBSWTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(
                address(msg.sender),
                address(this),
                _amount
            );
            user.amount = user.amount.add(_amount);
            depositedBsw = depositedBsw.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accBSWPerShare).div(1e12);
        emit Deposit(msg.sender, 0, _amount);
    }

    //@brief 提出之前质押的BSW
    //@param _amount 本次提取BSW的份额
    function leaveStaking(uint256 _amount) public {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[0][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(0);
        uint256 pending = user.amount.mul(pool.accBSWPerShare).div(1e12).sub(
            user.rewardDebt
        );
        if (pending > 0) {
            safeBSWTransfer(msg.sender, pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
            depositedBsw = depositedBsw.sub(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accBSWPerShare).div(1e12);
        emit Withdraw(msg.sender, 0, _amount);
    }

    //@brief 紧急提走指定池中自己质押的lp所有份额。这种提现是没有收益的
    //@param _pid 指定池子编号
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    //@brief 转出BSW，最多只能转本合约当前拥有的份额
    //@param _to 接收者
    //@param _amount 转出份额
    function safeBSWTransfer(address _to, uint256 _amount) internal {
        uint256 BSWBal = BSW.balanceOf(address(this));
        if (_amount > BSWBal) {
            BSW.transfer(_to, BSWBal);
        } else {
            BSW.transfer(_to, _amount);
        }
    }

    //@brief 设置收益地址
    function setDevAddress(address _devaddr) public onlyOwner {
        devaddr = _devaddr;
    }

    //@brief 设置收益地址
    function setRefAddress(address _refaddr) public onlyOwner {
        refAddr = _refaddr;
    }

    //@brief 设置收益地址
    function setSafuAddress(address _safuaddr) public onlyOwner {
        safuaddr = _safuaddr;
    }

    //@brief 设置每个区块产出BSW的份额
    //@param newAmount 新的值
    function updateBswPerBlock(uint256 newAmount) public onlyOwner {
        require(newAmount <= 30 * 1e18, "Max per block 30 BSW");
        require(newAmount >= 1 * 1e18, "Min per block 1 BSW");
        BSWPerBlock = newAmount;
    }
}
