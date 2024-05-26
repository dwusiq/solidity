// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.7.5;

library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    function sub(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
    }

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }

    function div(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        uint256 c = a / b;
        return c;
    }
}

library Address {
    function isContract(address account) internal view returns (bool) {
        // This method relies in extcodesize, which returns 0 for contracts in
        // construction, since the code is only stored at the end of the
        // constructor execution.

        uint256 size;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    function functionCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        return _functionCallWithValue(target, data, 0, errorMessage);
    }

    function _functionCallWithValue(
        address target,
        bytes memory data,
        uint256 weiValue,
        string memory errorMessage
    ) private returns (bytes memory) {
        require(isContract(target), "Address: call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.call{value: weiValue}(
            data
        );
        if (success) {
            return returndata;
        } else {
            if (returndata.length > 0) {
                // solhint-disable-next-line no-inline-assembly
                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert(errorMessage);
            }
        }
    }

    function _verifyCallResult(
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) private pure returns (bytes memory) {
        if (success) {
            return returndata;
        } else {
            if (returndata.length > 0) {
                // solhint-disable-next-line no-inline-assembly
                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert(errorMessage);
            }
        }
    }
}

interface IOwnable {
    function manager() external view returns (address);

    function renounceManagement() external;

    function pushManagement(address newOwner_) external;

    function pullManagement() external;
}

contract Ownable is IOwnable {
    address internal _owner;
    address internal _newOwner;

    event OwnershipPushed(
        address indexed previousOwner,
        address indexed newOwner
    );
    event OwnershipPulled(
        address indexed previousOwner,
        address indexed newOwner
    );

    constructor() {
        _owner = msg.sender;
        emit OwnershipPushed(address(0), _owner);
    }

    function manager() public view override returns (address) {
        return _owner;
    }

    modifier onlyManager() {
        require(_owner == msg.sender, "Ownable: caller is not the owner");
        _;
    }

    function renounceManagement() public virtual override onlyManager {
        emit OwnershipPushed(_owner, address(0));
        _owner = address(0);
    }

    function pushManagement(address newOwner_)
        public
        virtual
        override
        onlyManager
    {
        require(
            newOwner_ != address(0),
            "Ownable: new owner is the zero address"
        );
        emit OwnershipPushed(_owner, newOwner_);
        _newOwner = newOwner_;
    }

    function pullManagement() public virtual override {
        require(msg.sender == _newOwner, "Ownable: must be new owner to pull");
        emit OwnershipPulled(_owner, _newOwner);
        _owner = _newOwner;
    }
}

interface IERC20 {
    function decimals() external view returns (uint8);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address recipient, uint256 amount)
        external
        returns (bool);

    function approve(address spender, uint256 amount) external returns (bool);

    function totalSupply() external view returns (uint256);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);

    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}

library SafeERC20 {
    using SafeMath for uint256;
    using Address for address;

    function safeTransfer(
        IERC20 token,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(
            token,
            abi.encodeWithSelector(token.transfer.selector, to, value)
        );
    }

    function safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(
            token,
            abi.encodeWithSelector(token.transferFrom.selector, from, to, value)
        );
    }

    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        bytes memory returndata = address(token).functionCall(
            data,
            "SafeERC20: low-level call failed"
        );
        if (returndata.length > 0) {
            // Return data is optional
            // solhint-disable-next-line max-line-length
            require(
                abi.decode(returndata, (bool)),
                "SafeERC20: ERC20 operation did not succeed"
            );
        }
    }
}

interface IERC20Mintable {
    function mint(uint256 amount_) external;

    function mint(address account_, uint256 ammount_) external;
}

interface IOHMERC20 {
    function burnFrom(address account_, uint256 amount_) external;
}

interface IBondCalculator {
    function valuation(address pair_, uint256 amount_)
        external
        view
        returns (uint256 _value);
}

contract OlympusTreasury is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    event Deposit(address indexed token, uint256 amount, uint256 value);
    event Withdrawal(address indexed token, uint256 amount, uint256 value);
    event CreateDebt(
        address indexed debtor,
        address indexed token,
        uint256 amount,
        uint256 value
    );
    event RepayDebt(
        address indexed debtor,
        address indexed token,
        uint256 amount,
        uint256 value
    );
    event ReservesManaged(address indexed token, uint256 amount);
    event ReservesUpdated(uint256 indexed totalReserves);
    event ReservesAudited(uint256 indexed totalReserves);
    event RewardsMinted(
        address indexed caller,
        address indexed recipient,
        uint256 amount
    );
    event ChangeQueued(MANAGING indexed managing, address queued);
    event ChangeActivated(
        MANAGING indexed managing,
        address activated,
        bool result
    );

    // RESERVEDEPOSITOR:0-允许存入储备金
    // RESERVESPENDER:1-允许提现储备金
    // RESERVETOKEN:2-允许成为合约支持的储备金
    // RESERVEMANAGER:3-允许管理储备金（有这个权限可以提取当前合约的储备金）
    // LIQUIDITYDEPOSITOR:4-允许存入LpToken
    // LIQUIDITYTOKEN:5-允许允许成为合约支持的lpToken
    // LIQUIDITYMANAGER:6-允许管理lpToken（有这个权限可以提取当前合约的lpToken）
    // DEBTOR:7-允许借用储备金
    // REWARDMANAGER:8-允许铸造OHM给其它用户
    // SOHM:9-sohm代币
    enum MANAGING {
        RESERVEDEPOSITOR,
        RESERVESPENDER,
        RESERVETOKEN,
        RESERVEMANAGER,
        LIQUIDITYDEPOSITOR,
        LIQUIDITYTOKEN,
        LIQUIDITYMANAGER,
        DEBTOR,
        REWARDMANAGER,
        SOHM
    }

    address public immutable OHM;
    //用户被添加地址到变更授权的队列后，要等待几个区块之后才能进行实际操作
    uint256 public immutable blocksNeededForQueue;

    address[] public reserveTokens; //这类型的数组都智能添加，不能删除，有误报的可能，（不知道干嘛用，如果可以尽量不用）【 Push only, beware false-positives.】
    mapping(address => bool) public isReserveToken;
    mapping(address => uint256) public reserveTokenQueue; // Delays changes to mapping.

    address[] public reserveDepositors; // Push only, beware false-positives. Only for viewing.
    mapping(address => bool) public isReserveDepositor;
    mapping(address => uint256) public reserveDepositorQueue; // Delays changes to mapping.

    address[] public reserveSpenders; // Push only, beware false-positives. Only for viewing.
    mapping(address => bool) public isReserveSpender;
    mapping(address => uint256) public reserveSpenderQueue; // Delays changes to mapping.

    address[] public liquidityTokens; // Push only, beware false-positives.
    mapping(address => bool) public isLiquidityToken;
    mapping(address => uint256) public LiquidityTokenQueue; // Delays changes to mapping.

    address[] public liquidityDepositors; // Push only, beware false-positives. Only for viewing.
    mapping(address => bool) public isLiquidityDepositor;
    mapping(address => uint256) public LiquidityDepositorQueue; // Delays changes to mapping.

    mapping(address => address) public bondCalculator; // bond calculator for liquidity token

    address[] public reserveManagers; // Push only, beware false-positives. Only for viewing.
    mapping(address => bool) public isReserveManager;
    mapping(address => uint256) public ReserveManagerQueue; // Delays changes to mapping.

    address[] public liquidityManagers; // Push only, beware false-positives. Only for viewing.
    mapping(address => bool) public isLiquidityManager;
    mapping(address => uint256) public LiquidityManagerQueue; // Delays changes to mapping.

    address[] public debtors; // Push only, beware false-positives. Only for viewing.
    mapping(address => bool) public isDebtor;
    mapping(address => uint256) public debtorQueue; // Delays changes to mapping.
    mapping(address => uint256) public debtorBalance;

    address[] public rewardManagers; // Push only, beware false-positives. Only for viewing.
    mapping(address => bool) public isRewardManager;
    mapping(address => uint256) public rewardManagerQueue; // Delays changes to mapping.

    address public sOHM;
    uint256 public sOHMQueue; // Delays change to sOHM address

    uint256 public totalReserves; // Risk-free value of all assets
    uint256 public totalDebt;

    constructor(
        address _OHM,
        address _DAI,
        address _Frax,
        address _OHMDAI,
        uint256 _blocksNeededForQueue
    ) {
        require(_OHM != address(0));
        OHM = _OHM;

        isReserveToken[_DAI] = true;
        reserveTokens.push(_DAI);

        isReserveToken[_Frax] = true;
        reserveTokens.push(_Frax);

        isLiquidityToken[_OHMDAI] = true;
        liquidityTokens.push(_OHMDAI);

        blocksNeededForQueue = _blocksNeededForQueue;
    }

    /**
        @notice 允许授权地址存储指定资产来获取OHM【allow approved address to deposit an asset for OHM】
        @param _amount uint    //质押资产的份额（资产份额）
        @param _token address  //质押资产的地址
        @param _profit uint    //这个份额留在Treasury合约用作多余的储备金（如果Treasury合约没有多余的储备金，则不能质押ohm,因为触发rebase会调用mintRewards函数，该函数要求每个新铸造的OHM要有储备金支撑）
        @return send_ uint
     */
    function deposit(
        uint256 _amount,
        address _token,
        uint256 _profit
    ) external returns (uint256 send_) {
        require(
            isReserveToken[_token] || isLiquidityToken[_token],
            "Not accepted"
        );
        //将请求者的地资产转入当前合约
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

        if (isReserveToken[_token]) {
            require(isReserveDepositor[msg.sender], "Not approved");
        } else {
            require(isLiquidityDepositor[msg.sender], "Not approved");
        }

        //计算指定资产的份额价值多少OHM(无风险价值)
        uint256 value = valueOf(_token, _amount);
        // 给请求者的份额(即给用户的支付份额+手续费份额))=存入资产总价值-给rebase分红的份额【mint OHM needed and store amount of rewards for distribution】
        send_ = value.sub(_profit);
        IERC20Mintable(OHM).mint(msg.sender, send_);
        //总储备金增加
        totalReserves = totalReserves.add(value);
        emit ReservesUpdated(totalReserves);

        emit Deposit(_token, _amount, value);
    }

    /**
        @notice 有权限的用户用OHM兑换储备中的指定资产(会销毁OHM)【allow approved address to burn OHM for reserves】
        @param _amount uint  计划获取的目标token份额
        @param _token address  计划获取的目标token地址
     */
    function withdraw(uint256 _amount, address _token) external {
        require(isReserveToken[_token], "Not accepted"); // Only reserves can be used for redemptions
        require(isReserveSpender[msg.sender] == true, "Not approved");

        uint256 value = valueOf(_token, _amount);
        IOHMERC20(OHM).burnFrom(msg.sender, value);

        totalReserves = totalReserves.sub(value);
        emit ReservesUpdated(totalReserves);

        IERC20(_token).safeTransfer(msg.sender, _amount);

        emit Withdrawal(_token, _amount, value);
    }

    /**
        @notice 用户借用储备金【allow approved address to borrow reserves】
        @param _amount uint
        @param _token address
     */
    function incurDebt(uint256 _amount, address _token) external {
        require(isDebtor[msg.sender], "Not approved");
        require(isReserveToken[_token], "Not accepted");

        uint256 value = valueOf(_token, _amount);

        uint256 maximumDebt = IERC20(sOHM).balanceOf(msg.sender); // Can only borrow against sOHM held
        uint256 availableDebt = maximumDebt.sub(debtorBalance[msg.sender]);
        require(value <= availableDebt, "Exceeds debt limit");

        debtorBalance[msg.sender] = debtorBalance[msg.sender].add(value);
        totalDebt = totalDebt.add(value);

        totalReserves = totalReserves.sub(value);
        emit ReservesUpdated(totalReserves);

        IERC20(_token).transfer(msg.sender, _amount);

        emit CreateDebt(msg.sender, _token, _amount, value);
    }

    /**
        @notice 用户返还借用的储备金【allow approved address to repay borrowed reserves with reserves】
        @param _amount uint
        @param _token address
     */
    function repayDebtWithReserve(uint256 _amount, address _token) external {
        require(isDebtor[msg.sender], "Not approved");
        require(isReserveToken[_token], "Not accepted");

        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

        uint256 value = valueOf(_token, _amount);
        debtorBalance[msg.sender] = debtorBalance[msg.sender].sub(value);
        totalDebt = totalDebt.sub(value);

        totalReserves = totalReserves.add(value);
        emit ReservesUpdated(totalReserves);

        emit RepayDebt(msg.sender, _token, _amount, value);
    }

    /**
        @notice 用户返还借用的OHM【allow approved address to repay borrowed reserves with OHM】
        @param _amount uint
     */
    function repayDebtWithOHM(uint256 _amount) external {
        require(isDebtor[msg.sender], "Not approved");

        IOHMERC20(OHM).burnFrom(msg.sender, _amount);

        debtorBalance[msg.sender] = debtorBalance[msg.sender].sub(_amount);
        totalDebt = totalDebt.sub(_amount);

        emit RepayDebt(msg.sender, OHM, _amount, _amount);
    }

    /**
        @notice 有权限的用户可以提取合约中的储备资产【allow approved address to withdraw assets】
        @param _token address
        @param _amount uint
     */
    function manage(address _token, uint256 _amount) external {
        if (isLiquidityToken[_token]) {
            require(isLiquidityManager[msg.sender], "Not approved");
        } else {
            require(isReserveManager[msg.sender], "Not approved");
        }

        uint256 value = valueOf(_token, _amount);
        require(value <= excessReserves(), "Insufficient reserves");

        totalReserves = totalReserves.sub(value);
        emit ReservesUpdated(totalReserves);

        IERC20(_token).safeTransfer(msg.sender, _amount);

        emit ReservesManaged(_token, _amount);
    }

    /**
     * @notice 每个rebase周期都给staking合约铸造用于质押分红的OHM【send epoch reward to staking contract】
     */
    function mintRewards(address _recipient, uint256 _amount) external {
        require(isRewardManager[msg.sender], "Not approved");
        //限制：铸造的OHM,都必须有储备金支撑（即铸造的OHM总价值不能多余储备金的总价值）
        require(_amount <= excessReserves(), "Insufficient reserves");

        IERC20Mintable(OHM).mint(_recipient, _amount);

        emit RewardsMinted(msg.sender, _recipient, _amount);
    }

    /**
     * @notice 查询还有多少储备金没有用来支撑OHM的（即还能铸造多少OHM）【returns excess reserves not backing tokens】
     * @return uint
     */
    function excessReserves() public view returns (uint256) {
        return totalReserves.sub(IERC20(OHM).totalSupply().sub(totalDebt));
    }

    /**
        @notice 重新盘点当前合约储备的所有`Token`的总价值【takes inventory of all tracked assets】
        @notice always consolidate to recognized reserves before audit
     */
    function auditReserves() external onlyManager {
        uint256 reserves;
        for (uint256 i = 0; i < reserveTokens.length; i++) {
            reserves = reserves.add(
                valueOf(
                    reserveTokens[i],
                    IERC20(reserveTokens[i]).balanceOf(address(this))
                )
            );
        }
        for (uint256 i = 0; i < liquidityTokens.length; i++) {
            reserves = reserves.add(
                valueOf(
                    liquidityTokens[i],
                    IERC20(liquidityTokens[i]).balanceOf(address(this))
                )
            );
        }
        totalReserves = reserves;
        emit ReservesUpdated(reserves);
        emit ReservesAudited(reserves);
    }

    /**
        @notice 计算指定资产的份额价值多少OHM(无风险价值RFV)【returns OHM valuation of asset】
        @param _token address  指定资产地址
        @param _amount uint   指定资产的份额
        @return value_ uint
     */
    function valueOf(address _token, uint256 _amount)
        public
        view
        returns (uint256 value_)
    {
        if (isReserveToken[_token]) {
            // convert amount to match OHM decimals
            //1单位OHM字面数值/1单位目标token字面数值 = OHM精度/指定token精度 = 10**IERC20(OHM).decimals()/10**IERC20(_token).decimals()
            //例如，OHM精度9，DAI精度18，则1单位OHM字面数值/1单位Dai字面数值=1e9/1e18=1/1e9, 如果DAI的amount是10*1e18,则相对应OHM的份额=10*1e18 * 1/1e9=10*1e9;
            value_ = _amount.mul(10**IERC20(OHM).decimals()).div(
                10**IERC20(_token).decimals()
            );
        } else if (isLiquidityToken[_token]) {
            value_ = IBondCalculator(bondCalculator[_token]).valuation(
                _token,
                _amount
            );
        }
    }

    /**
     * @notice 添加地址到变更授权的队列(调toggle前要先调这个接口添加地址，并且有等待期)【queue address to change boolean in mapping】
     * @param _managing MANAGING   授权类型的
     * @param _address address     被授权的地址
     * @return bool
     */
    function queue(MANAGING _managing, address _address)
        external
        onlyManager
        returns (bool)
    {
        require(_address != address(0));
        if (_managing == MANAGING.RESERVEDEPOSITOR) {
            // 0
            reserveDepositorQueue[_address] = block.number.add(
                blocksNeededForQueue
            );
        } else if (_managing == MANAGING.RESERVESPENDER) {
            // 1
            reserveSpenderQueue[_address] = block.number.add(
                blocksNeededForQueue
            );
        } else if (_managing == MANAGING.RESERVETOKEN) {
            // 2
            reserveTokenQueue[_address] = block.number.add(
                blocksNeededForQueue
            );
        } else if (_managing == MANAGING.RESERVEMANAGER) {
            // 3
            ReserveManagerQueue[_address] = block.number.add(
                blocksNeededForQueue.mul(2)
            );
        } else if (_managing == MANAGING.LIQUIDITYDEPOSITOR) {
            // 4
            LiquidityDepositorQueue[_address] = block.number.add(
                blocksNeededForQueue
            );
        } else if (_managing == MANAGING.LIQUIDITYTOKEN) {
            // 5
            LiquidityTokenQueue[_address] = block.number.add(
                blocksNeededForQueue
            );
        } else if (_managing == MANAGING.LIQUIDITYMANAGER) {
            // 6
            LiquidityManagerQueue[_address] = block.number.add(
                blocksNeededForQueue.mul(2)
            );
        } else if (_managing == MANAGING.DEBTOR) {
            // 7
            debtorQueue[_address] = block.number.add(blocksNeededForQueue);
        } else if (_managing == MANAGING.REWARDMANAGER) {
            // 8
            rewardManagerQueue[_address] = block.number.add(
                blocksNeededForQueue
            );
        } else if (_managing == MANAGING.SOHM) {
            // 9
            sOHMQueue = block.number.add(blocksNeededForQueue);
        } else return false;

        emit ChangeQueued(_managing, _address);
        return true;
    }

    /**
        @notice （事先添加到queue，并且过了等待期后，可以调这个接口）检查队列，并且切换用户的授权状态。【verify queue then set boolean in mapping】
        @param _managing MANAGING
        @param _address address
        @param _calculator address
        @return bool
     */
    function toggle(
        MANAGING _managing,
        address _address,
        address _calculator
    ) external onlyManager returns (bool) {
        require(_address != address(0));
        bool result;
        if (_managing == MANAGING.RESERVEDEPOSITOR) {
            // 0
            if (
                requirements(
                    reserveDepositorQueue,
                    isReserveDepositor,
                    _address
                )
            ) {
                reserveDepositorQueue[_address] = 0;
                if (!listContains(reserveDepositors, _address)) {
                    reserveDepositors.push(_address);
                }
            }
            result = !isReserveDepositor[_address];
            isReserveDepositor[_address] = result;
        } else if (_managing == MANAGING.RESERVESPENDER) {
            // 判断地址是否未授权，并且未授权的是否过了队列等待期
            // false:已授权    true：未授权，且在队列中，且队列等待期已到
            if (requirements(reserveSpenderQueue, isReserveSpender, _address)) {
                //队列中移除该地址
                reserveSpenderQueue[_address] = 0;
                //添加到数组中(由此可见，如果重复操作，数组可能有重复的数据)
                if (!listContains(reserveSpenders, _address)) {
                    reserveSpenders.push(_address);
                }
            }
            //切换用户的授权状态
            result = !isReserveSpender[_address];
            isReserveSpender[_address] = result;
        } else if (_managing == MANAGING.RESERVETOKEN) {
            // 2
            if (requirements(reserveTokenQueue, isReserveToken, _address)) {
                reserveTokenQueue[_address] = 0;
                if (!listContains(reserveTokens, _address)) {
                    reserveTokens.push(_address);
                }
            }
            result = !isReserveToken[_address];
            isReserveToken[_address] = result;
        } else if (_managing == MANAGING.RESERVEMANAGER) {
            // 3
            if (requirements(ReserveManagerQueue, isReserveManager, _address)) {
                reserveManagers.push(_address);
                ReserveManagerQueue[_address] = 0;
                if (!listContains(reserveManagers, _address)) {
                    reserveManagers.push(_address);
                }
            }
            result = !isReserveManager[_address];
            isReserveManager[_address] = result;
        } else if (_managing == MANAGING.LIQUIDITYDEPOSITOR) {
            // 4
            if (
                requirements(
                    LiquidityDepositorQueue,
                    isLiquidityDepositor,
                    _address
                )
            ) {
                liquidityDepositors.push(_address);
                LiquidityDepositorQueue[_address] = 0;
                if (!listContains(liquidityDepositors, _address)) {
                    liquidityDepositors.push(_address);
                }
            }
            result = !isLiquidityDepositor[_address];
            isLiquidityDepositor[_address] = result;
        } else if (_managing == MANAGING.LIQUIDITYTOKEN) {
            // 5
            if (requirements(LiquidityTokenQueue, isLiquidityToken, _address)) {
                LiquidityTokenQueue[_address] = 0;
                if (!listContains(liquidityTokens, _address)) {
                    liquidityTokens.push(_address);
                }
            }
            result = !isLiquidityToken[_address];
            isLiquidityToken[_address] = result;
            bondCalculator[_address] = _calculator;
        } else if (_managing == MANAGING.LIQUIDITYMANAGER) {
            // 6
            if (
                requirements(
                    LiquidityManagerQueue,
                    isLiquidityManager,
                    _address
                )
            ) {
                LiquidityManagerQueue[_address] = 0;
                if (!listContains(liquidityManagers, _address)) {
                    liquidityManagers.push(_address);
                }
            }
            result = !isLiquidityManager[_address];
            isLiquidityManager[_address] = result;
        } else if (_managing == MANAGING.DEBTOR) {
            // 7
            if (requirements(debtorQueue, isDebtor, _address)) {
                debtorQueue[_address] = 0;
                if (!listContains(debtors, _address)) {
                    debtors.push(_address);
                }
            }
            result = !isDebtor[_address];
            isDebtor[_address] = result;
        } else if (_managing == MANAGING.REWARDMANAGER) {
            // 8
            if (requirements(rewardManagerQueue, isRewardManager, _address)) {
                rewardManagerQueue[_address] = 0;
                if (!listContains(rewardManagers, _address)) {
                    rewardManagers.push(_address);
                }
            }
            result = !isRewardManager[_address];
            isRewardManager[_address] = result;
        } else if (_managing == MANAGING.SOHM) {
            // 9
            sOHMQueue = 0;
            sOHM = _address;
            result = true;
        } else return false;

        emit ChangeActivated(_managing, _address, result);
        return true;
    }

    /**
        @notice 判断地址是否未授权，并且未授权的是否过了队列等待期【checks requirements and returns altered structs】
        @param queue_ mapping( address => uint )    队列<地址=>等待结束区块>
        @param status_ mapping( address => bool )   授权状态<地址=>是否授权>
        @param _address address   被检查的地址
        @return bool     false:已授权    true：未授权，且在队列中，且队列等待期已到，
     */
    function requirements(
        mapping(address => uint256) storage queue_,
        mapping(address => bool) storage status_,
        address _address
    ) internal view returns (bool) {
        //判断地址是否已授权， false:已授权    true：未授权，且在队列中，且队列等待期已到，
        if (!status_[_address]) {
            //检验该地址是否已添加到队列中
            require(queue_[_address] != 0, "Must queue");
            //检验该地址添加到队列后，是否过了需要等待的区块个数
            require(queue_[_address] <= block.number, "Queue not expired");
            return true;
        }
        return false;
    }

    /**
        @notice checks array to ensure against duplicate
        @param _list address[]
        @param _token address
        @return bool
     */
    function listContains(address[] storage _list, address _token)
        internal
        view
        returns (bool)
    {
        for (uint256 i = 0; i < _list.length; i++) {
            if (_list[i] == _token) {
                return true;
            }
        }
        return false;
    }
}
