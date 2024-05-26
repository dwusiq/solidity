// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.7.5;

import "./libraries/SafeMath.sol";
import "./libraries/SafeERC20.sol";

import "./interfaces/IOwnable.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IERC20Metadata.sol";
import "./interfaces/IOHM.sol";
import "./interfaces/IsOHM.sol";
import "./interfaces/IBondingCalculator.sol";
import "./interfaces/ITreasury.sol";

import "./types/OlympusAccessControlled.sol";

//财政部合约(管理所有资产)
contract OlympusTreasury is OlympusAccessControlled, ITreasury {
    /* ========== DEPENDENCIES ========== */

    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /* ========== EVENTS ========== */

    event Deposit(address indexed token, uint256 amount, uint256 value);
    event Withdrawal(address indexed token, uint256 amount, uint256 value);
    event CreateDebt(address indexed debtor, address indexed token, uint256 amount, uint256 value);
    event RepayDebt(address indexed debtor, address indexed token, uint256 amount, uint256 value);
    event Managed(address indexed token, uint256 amount);
    event ReservesAudited(uint256 indexed totalReserves);
    event Minted(address indexed caller, address indexed recipient, uint256 amount);
    event PermissionQueued(STATUS indexed status, address queued);
    event Permissioned(address addr, STATUS indexed status, bool result);

    /* ========== DATA STRUCTURES ========== */

    // RESERVEDEPOSITOR:允许存入储备金
    // RESERVESPENDER:允许提现储备金
    // RESERVETOKEN:允许成为合约支持的储备金
    // RESERVEMANAGER:允许管理储备金（有这个权限可以提取当前合约的储备金）
    // LIQUIDITYDEPOSITOR:允许存入LpToken
    // LIQUIDITYTOKEN:允许允许成为合约支持的lpToken
    // LIQUIDITYMANAGER:允许管理lpToken（有这个权限可以提取当前合约的lpToken）
    // RESERVEDEBTOR:允许借用储备金
    // REWARDMANAGER:允许铸造OHM给其它用户
    // SOHM:
    // OHMDEBTOR:允许借用OHM
    enum STATUS {
        RESERVEDEPOSITOR,
        RESERVESPENDER,
        RESERVETOKEN,
        RESERVEMANAGER,
        LIQUIDITYDEPOSITOR,
        LIQUIDITYTOKEN,
        LIQUIDITYMANAGER,
        RESERVEDEBTOR,
        REWARDMANAGER,
        SOHM,
        OHMDEBTOR   
    }

    struct Queue {
        STATUS managing;
        address toPermit;
        address calculator;
        uint256 timelockEnd;
        bool nullify;
        bool executed;
    }

    /* ========== STATE VARIABLES ========== */

    IOHM public immutable OHM;
    IsOHM public sOHM;

    mapping(STATUS => address[]) public registry;
    mapping(STATUS => mapping(address => bool)) public permissions;
    mapping(address => address) public bondCalculator;

    mapping(address => uint256) public debtLimit;

    uint256 public totalReserves;//合约当前储备金总额（折算OHM）
    uint256 public totalDebt; //合约往外借的所有资产总额（折算OHM）
    uint256 public ohmDebt;//合约往外借的OHM总额

    Queue[] public permissionQueue; //许可队列
    uint256 public immutable blocksNeededForQueue; //每个许可队列要等待的区块数

    bool public timelockEnabled; //是否允许时间锁
    bool public initialized;     //是否已初始化

    uint256 public onChainGovernanceTimelock;

    string internal notAccepted = "Treasury: not accepted";
    string internal notApproved = "Treasury: not approved";
    string internal invalidToken = "Treasury: invalid token";
    string internal insufficientReserves = "Treasury: insufficient reserves";

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _ohm,
        uint256 _timelock,
        address _authority
    ) OlympusAccessControlled(IOlympusAuthority(_authority)) {
        require(_ohm != address(0), "Zero address: OHM");
        OHM = IOHM(_ohm);

        timelockEnabled = false;
        initialized = false;
        blocksNeededForQueue = _timelock;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @notice 被授权的地址可以存入Token获取OHM(当前只有升级合约用到该接口)【allow approved address to deposit an asset for OHM】
     * @param _amount uint256   //存入的金额
     * @param _token address    //存入的Token地址
     * @param _profit uint256   //
     * @return send_ uint256
     */
    function deposit(
        uint256 _amount,
        address _token,
        uint256 _profit
    ) external override returns (uint256 send_) {
        if (permissions[STATUS.RESERVETOKEN][_token]) {
             //如果存入的token是储备token,则判断sender是否有RESERVE DEPOSITOR权限
            require(permissions[STATUS.RESERVEDEPOSITOR][msg.sender], notApproved);
        } else if (permissions[STATUS.LIQUIDITYTOKEN][_token]) {
            //如果存入的token是流动性LP,则判断sender是否有LIQUIDITY DEPOSITOR权限
            require(permissions[STATUS.LIQUIDITYDEPOSITOR][msg.sender], notApproved);
        } else {
            revert(invalidToken);
        }

        //将sender需要存储的token转到当前合约
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

        //判断存入的这些token价值多少OHM
        uint256 value = tokenValue(_token, _amount);
        // mint OHM needed and store amount of rewards for distribution
        send_ = value.sub(_profit);
        OHM.mint(msg.sender, send_);

        //累加储备中所有token总共价值多少OHM
        totalReserves = totalReserves.add(value);

        emit Deposit(_token, _amount, value);
    }

    /**
     * @notice 允许用户销毁OHM换回储备中的其它Token【allow approved address to burn OHM for reserves】
     * @param _amount uint256  赎回的目标token份额
     * @param _token address   赎回的目标token地址
     */
    function withdraw(uint256 _amount, address _token) external override {
        // 判断目标token是否被允许作为储备Token【Only reserves can be used for redemptions】
        require(permissions[STATUS.RESERVETOKEN][_token], notAccepted); 
        //判断发送者是否允许提现
        require(permissions[STATUS.RESERVESPENDER][msg.sender], notApproved); 
        //需要提现目标token的份额折算回OHM的份额，并销毁
        uint256 value = tokenValue(_token, _amount);
        OHM.burnFrom(msg.sender, value);
        //金库所有token总价值OHM减去本次提取的份额
        totalReserves = totalReserves.sub(value);
        //目标token转给发送者
        IERC20(_token).safeTransfer(msg.sender, _amount);

        emit Withdrawal(_token, _amount, value);
    }

    /**
     * @notice 被授权的地址允许提取token（不会销毁OHM）（目前只有升级合约调用）【allow approved address to withdraw assets】
     * @param _token address
     * @param _amount uint256
     */
    function manage(address _token, uint256 _amount) external override {
        //确定用户有lp管理或token的管理权限
        if (permissions[STATUS.LIQUIDITYTOKEN][_token]) {
            require(permissions[STATUS.LIQUIDITYMANAGER][msg.sender], notApproved);
        } else {
            require(permissions[STATUS.RESERVEMANAGER][msg.sender], notApproved);
        }
        //确定目标token是被支持的token或lp
        if (permissions[STATUS.RESERVETOKEN][_token] || permissions[STATUS.LIQUIDITYTOKEN][_token]) {
            uint256 value = tokenValue(_token, _amount);
            require(value <= excessReserves(), insufficientReserves);
            totalReserves = totalReserves.sub(value);
        }
        //token转给调用者
        IERC20(_token).safeTransfer(msg.sender, _amount);
        emit Managed(_token, _amount);
    }

    /**
     * @notice 铸造OHM给指定用户【mint new OHM using excess reserves】
     * @param _recipient address
     * @param _amount uint256
     */
    function mint(address _recipient, uint256 _amount) external override {
        //确定调用者有权发放奖励
        require(permissions[STATUS.REWARDMANAGER][msg.sender], notApproved);
        require(_amount <= excessReserves(), insufficientReserves);
        OHM.mint(_recipient, _amount);
        emit Minted(msg.sender, _recipient, _amount);
    }

    /**
     * DEBT: The debt functions allow approved addresses to borrow treasury assets
     * or OHM from the treasury, using sOHM as collateral. This might allow an
     * sOHM holder to provide OHM liquidity without taking on the opportunity cost
     * of unstaking, or alter their backing without imposing risk onto the treasury.
     * Many of these use cases are yet to be defined, but they appear promising.
     * However, we urge the community to think critically and move slowly upon
     * proposals to acquire these permissions.
     */

    /**
     * @notice 被批准的地址可以借用储备金【allow approved address to borrow reserves】
     * @param _amount uint256
     * @param _token address
     */
    function incurDebt(uint256 _amount, address _token) external override {
        uint256 value;

        //判断用户是否允许借贷、判断token是否允许作为储备金
        if (_token == address(OHM)) {
            require(permissions[STATUS.OHMDEBTOR][msg.sender], notApproved);
            value = _amount;
        } else {
            require(permissions[STATUS.RESERVEDEBTOR][msg.sender], notApproved);
            require(permissions[STATUS.RESERVETOKEN][_token], notAccepted);
            value = tokenValue(_token, _amount);
        }
        require(value != 0, invalidToken);

        //不管借什么token,都登记为sOHM
        sOHM.changeDebt(value, msg.sender, true);
        //不许超过个人的最大允许借贷额度
        require(sOHM.debtBalances(msg.sender) <= debtLimit[msg.sender], "Treasury: exceeds limit");
        //累加合约总共往外借了多少份额
        totalDebt = totalDebt.add(value);

        if (_token == address(OHM)) {
            //如果是OHM,直接mint
            OHM.mint(msg.sender, value);
            //合约往外借的OHM总额增加
            ohmDebt = ohmDebt.add(value);
        } else {
            //如果是其它token，减少储备金就直接转给用户
            totalReserves = totalReserves.sub(value);
            IERC20(_token).safeTransfer(msg.sender, _amount);
        }
        emit CreateDebt(msg.sender, _token, _amount, value);
    }

    /**
     * @notice 允许授权用户偿还之前的借款（不是OHM,而是其它token）【allow approved address to repay borrowed reserves with reserves】
     * @param _amount uint256
     * @param _token address
     */
    function repayDebtWithReserve(uint256 _amount, address _token) external override {
        //判断用户是否允许借款
        require(permissions[STATUS.RESERVEDEBTOR][msg.sender], notApproved);
        //判断用户是否被支持作为储备金
        require(permissions[STATUS.RESERVETOKEN][_token], notAccepted);
        //从用户的账户中将token转到当前合约
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        //将用户还款token的份额折算回OHM的份额
        uint256 value = tokenValue(_token, _amount);
        //减少用户的当前欠款值
        sOHM.changeDebt(value, msg.sender, false);
        //协议往外借款总额减少
        totalDebt = totalDebt.sub(value);
        //合约储备金总额增加
        totalReserves = totalReserves.add(value);
        emit RepayDebt(msg.sender, _token, _amount, value);
    }

    /**
     * @notice 允许授权用户偿还之前的OHM借款【allow approved address to repay borrowed reserves with OHM】
     * @param _amount uint256
     */
    function repayDebtWithOHM(uint256 _amount) external {
        //判断用户可以借储备金或者用户可以借OHM
        require(permissions[STATUS.RESERVEDEBTOR][msg.sender] || permissions[STATUS.OHMDEBTOR][msg.sender], notApproved);
       //直接销毁用户帐下的OHM
        OHM.burnFrom(msg.sender, _amount);
        //减少用户当前的欠款额
        sOHM.changeDebt(_amount, msg.sender, false);
        //协议往外借款总额减少
        totalDebt = totalDebt.sub(_amount);
        //合约往外借的OHM总额减少
        ohmDebt = ohmDebt.sub(_amount);
        emit RepayDebt(msg.sender, address(OHM), _amount, _amount);
    }

    /* ========== MANAGERIAL FUNCTIONS ========== */

    /**
     * 重新盘点当前合约支持的所有token的总价值（总共价值多少OHM）
     * @notice 对所有跟踪的资产进行盘存【takes inventory of all tracked assets】
     * @notice 在审计前，总是合并到已确认的储备 【always consolidate to recognized reserves before audit】
     */
    function auditReserves() external onlyGovernor {
        uint256 reserves;
        address[] memory reserveToken = registry[STATUS.RESERVETOKEN];
        for (uint256 i = 0; i < reserveToken.length; i++) {
            if (permissions[STATUS.RESERVETOKEN][reserveToken[i]]) {
                reserves = reserves.add(tokenValue(reserveToken[i], IERC20(reserveToken[i]).balanceOf(address(this))));
            }
        }
        address[] memory liquidityToken = registry[STATUS.LIQUIDITYTOKEN];
        for (uint256 i = 0; i < liquidityToken.length; i++) {
            if (permissions[STATUS.LIQUIDITYTOKEN][liquidityToken[i]]) {
                reserves = reserves.add(tokenValue(liquidityToken[i], IERC20(liquidityToken[i]).balanceOf(address(this))));
            }
        }
        totalReserves = reserves;
        emit ReservesAudited(reserves);
    }

    /**
     * @notice 设置某个地址允许的最大债务值【set max debt for address】
     * @param _address address
     * @param _limit uint256
     */
    function setDebtLimit(address _address, uint256 _limit) external onlyGovernor {
        debtLimit[_address] = _limit;
    }

    /**
     * @notice 给指定地址设置某个权限【enable permission from queue】
     * @param _status 状态【STATUS】
     * @param _address address
     * @param _calculator StandardBondingCalculator合约地址
     */
    function enable(
        STATUS _status,
        address _address,
        address _calculator
    ) external onlyGovernor {
        require(timelockEnabled == false, "Use queueTimelock");
        if (_status == STATUS.SOHM) {
            //允许指定的_address作为sOHM合约地址
            sOHM = IsOHM(_address);
        } else {
            //其它授权
            permissions[_status][_address] = true;

            if (_status == STATUS.LIQUIDITYTOKEN) {
                bondCalculator[_address] = _calculator;
            }

            //判断status中注册的地址是否包含该_address
            (bool registered, ) = indexInRegistry(_address, _status);
            if (!registered) {
                //如果不包含，则添加
                registry[_status].push(_address);

                //该方法不允许注册lp和reserveToken两个状态 TODO 不知为何
                if (_status == STATUS.LIQUIDITYTOKEN || _status == STATUS.RESERVETOKEN) {
                    (bool reg, uint256 index) = indexInRegistry(_address, _status);
                    if (reg) {
                        delete registry[_status][index];
                    }
                }
            }
        }
        emit Permissioned(_address, _status, true);
    }

    /**
     *  @notice 取消某个地址相对于某个角色的权限【disable permission from address】
     *  @param _status STATUS
     *  @param _toDisable address
     */
    function disable(STATUS _status, address _toDisable) external {
        require(msg.sender == authority.governor() || msg.sender == authority.guardian(), "Only governor or guardian");
        permissions[_status][_toDisable] = false;
        emit Permissioned(_toDisable, _status, false);
    }

    /**
     * @notice 判断指定状态中是否包含某个地址【check if registry contains address】
     * @return (bool, uint256)
     */
    function indexInRegistry(address _address, STATUS _status) public view returns (bool, uint256) {
        address[] memory entries = registry[_status];
        for (uint256 i = 0; i < entries.length; i++) {
            if (_address == entries[i]) {
                return (true, i);
            }
        }
        return (false, 0);
    }

    /* ========== TIMELOCKED FUNCTIONS ========== */

    // functions are used prior to enabling on-chain governance

    /**
     * @notice queue address to receive permission
     * @param _status STATUS
     * @param _address address
     * @param _calculator address
     */
    function queueTimelock(
        STATUS _status,
        address _address,
        address _calculator
    ) external onlyGovernor {
        require(_address != address(0));
        require(timelockEnabled == true, "Timelock is disabled, use enable");

        uint256 timelock = block.number.add(blocksNeededForQueue);
        if (_status == STATUS.RESERVEMANAGER || _status == STATUS.LIQUIDITYMANAGER) {
            timelock = block.number.add(blocksNeededForQueue.mul(2));
        }
        permissionQueue.push(
            Queue({managing: _status, toPermit: _address, calculator: _calculator, timelockEnd: timelock, nullify: false, executed: false})
        );
        emit PermissionQueued(_status, _address);
    }

    /**
     *  @notice enable queued permission
     *  @param _index uint256
     */
    function execute(uint256 _index) external {
        require(timelockEnabled == true, "Timelock is disabled, use enable");

        Queue memory info = permissionQueue[_index];

        require(!info.nullify, "Action has been nullified");
        require(!info.executed, "Action has already been executed");
        require(block.number >= info.timelockEnd, "Timelock not complete");

        if (info.managing == STATUS.SOHM) {
            // 9
            sOHM = IsOHM(info.toPermit);
        } else {
            permissions[info.managing][info.toPermit] = true;

            if (info.managing == STATUS.LIQUIDITYTOKEN) {
                bondCalculator[info.toPermit] = info.calculator;
            }
            (bool registered, ) = indexInRegistry(info.toPermit, info.managing);
            if (!registered) {
                registry[info.managing].push(info.toPermit);

                if (info.managing == STATUS.LIQUIDITYTOKEN) {
                    (bool reg, uint256 index) = indexInRegistry(info.toPermit, STATUS.RESERVETOKEN);
                    if (reg) {
                        delete registry[STATUS.RESERVETOKEN][index];
                    }
                } else if (info.managing == STATUS.RESERVETOKEN) {
                    (bool reg, uint256 index) = indexInRegistry(info.toPermit, STATUS.LIQUIDITYTOKEN);
                    if (reg) {
                        delete registry[STATUS.LIQUIDITYTOKEN][index];
                    }
                }
            }
        }
        permissionQueue[_index].executed = true;
        emit Permissioned(info.toPermit, info.managing, true);
    }

    /**
     * @notice 取消指定index的时间锁【cancel timelocked action】
     * @param _index uint256
     */
    function nullify(uint256 _index) external onlyGovernor {
        permissionQueue[_index].nullify = true;
    }

    /**
     * @notice 取消所有的时间锁【disables timelocked functions】
     */
    function disableTimelock() external onlyGovernor {
        require(timelockEnabled == true, "timelock already disabled");
        if (onChainGovernanceTimelock != 0 && onChainGovernanceTimelock <= block.number) {
            //如果之前设置的时间锁小于当前块，直接关闭锁
            timelockEnabled = false;
        } else {
            //如果没设置时间锁或者时间锁区块值大于当前块，则在当前块的基础上+blocksNeededForQueue的7倍  TODO 为什么
            onChainGovernanceTimelock = block.number.add(blocksNeededForQueue.mul(7)); // 7-day timelock
        }
    }

    /**
     * @notice 初始化【 timelocks after initilization】
     */
    function initialize() external onlyGovernor {
        require(initialized == false, "Already initialized");
        timelockEnabled = true;
        initialized = true;
    }

    /* ========== VIEW FUNCTIONS ========== */

    /**
     * @notice returns excess reserves not backing tokens
     * @return uint
     */
    function excessReserves() public view override returns (uint256) {
        //储备总OHM价值-（OHM总供应量-总债务）
        return totalReserves.sub(OHM.totalSupply().sub(totalDebt));
    }

    /**
     * @notice 指定token地址和amount 估算价值多少的OHM【returns OHM valuation of asset】
     * @param _token address  指定token资产合约地址
     * @param _amount uint256 token
     * @return value_ uint256
     */
    function tokenValue(address _token, uint256 _amount) public view override returns (uint256 value_) {
        value_ = _amount.mul(10**IERC20Metadata(address(OHM)).decimals()).div(10**IERC20Metadata(_token).decimals());

        if (permissions[STATUS.LIQUIDITYTOKEN][_token]) {
            value_ = IBondingCalculator(bondCalculator[_token]).valuation(_token, _amount);
        }
    }

    /**
     * @notice returns supply metric that cannot be manipulated by debt
     * @dev 在任何需要查询OHM供应的时候使用这个【use this any time you need to query supply】
     * @return uint256
     */
    function baseSupply() external view override returns (uint256) {
        //OHM总供应量=omm总流动性-合约已往外借出去的份额（因为往外借的份额都是借的时候直接mint出来的，还的时候需要销毁，所以不算上总供应量）
        return OHM.totalSupply() - ohmDebt;
    }
}
