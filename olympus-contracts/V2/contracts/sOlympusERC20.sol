// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.7.5;

import "./libraries/Address.sol";
import "./libraries/SafeMath.sol";

import "./types/ERC20Permit.sol";

import "./interfaces/IgOHM.sol";
import "./interfaces/IsOHM.sol";
import "./interfaces/IStaking.sol";

//每质押一个OHM都对应分配一个sOHM，随时可以1:1兑换回OHM
contract sOlympus is IsOHM, ERC20Permit {
    /* ========== DEPENDENCIES ========== */

    using SafeMath for uint256;

    /* ========== EVENTS ========== */

    event LogSupply(uint256 indexed epoch, uint256 totalSupply);
    event LogRebase(uint256 indexed epoch, uint256 rebase, uint256 index);
    event LogStakingContractUpdated(address stakingContract);

    /* ========== MODIFIERS ========== */

   //只允许Staking.sol合约调用
    modifier onlyStakingContract() {
        require(msg.sender == stakingContract, "StakingContract:  call is not staking contract");
        _;
    }

    /* ========== DATA STRUCTURES ========== */
    //【Rebase是指在一定周期内，当市场价格偏离基准价格或偏离基准价格一定范围时，智能合约会直接或间接
    //增加或减少代币供应量以促使市场价格回归基准价格，通过某种设定的机制控制代币供应量以调节价格稳定】
    struct Rebase {
        uint256 epoch;
        uint256 rebase; // 18 decimals
        uint256 totalStakedBefore;
        uint256 totalStakedAfter;
        uint256 amountRebased;
        uint256 index;
        uint256 blockNumberOccured;
    }

    /* ========== STATE VARIABLES ========== */
   //初始化用户
    address internal initializer;

    uint256 internal INDEX; // Index Gons - tracks rebase growth

    address public stakingContract; // balance used to calc rebase
    IgOHM public gOHM; // additional staked supply (governance token)

    Rebase[] public rebases; // 历史变基记录【past rebase data】

    uint256 private constant MAX_UINT256 = type(uint256).max;
    uint256 private constant INITIAL_FRAGMENTS_SUPPLY = 5_000_000 * 10**9;

    // TOTAL_GONS is a multiple of INITIAL_FRAGMENTS_SUPPLY so that _gonsPerFragment is an integer.
    // Use the highest value that fits in a uint256 for max granularity.
    //gons总份额
    uint256 private constant TOTAL_GONS = MAX_UINT256 - (MAX_UINT256 % INITIAL_FRAGMENTS_SUPPLY); 

    // MAX_SUPPLY = maximum integer < (sqrt(4*TOTAL_GONS + 1) - 1) / 2
    //sOHM最大供应量
    uint256 private constant MAX_SUPPLY = ~uint128(0); // (2^128) - 1
    //每份sOHM价值多少gons
    uint256 private _gonsPerFragment;
    //用户的gons份额
    mapping(address => uint256) private _gonBalances;
    //用户授权额度
    mapping(address => mapping(address => uint256)) private _allowedValue;

    address public treasury;
    //用户当前欠款额度
    mapping(address => uint256) public override debtBalances;

    /* ========== CONSTRUCTOR ========== */

    constructor() ERC20("Staked OHM", "sOHM", 9) ERC20Permit("Staked OHM") {
        initializer = msg.sender;
        //sOHM的总供应量  TODO  没有找到定义的地方？
        _totalSupply = INITIAL_FRAGMENTS_SUPPLY;
        //计算每单位sOHM价值多少gons
        _gonsPerFragment = TOTAL_GONS.div(_totalSupply);
    }

    /* ========== INITIALIZATION ========== */

    function setIndex(uint256 _index) external {
        require(msg.sender == initializer, "Initializer:  caller is not initializer");
        require(INDEX == 0, "Cannot set INDEX again");
        INDEX = gonsForBalance(_index);
    }

    function setgOHM(address _gOHM) external {
        require(msg.sender == initializer, "Initializer:  caller is not initializer");
        require(address(gOHM) == address(0), "gOHM:  gOHM already set");
        require(_gOHM != address(0), "gOHM:  gOHM is not a valid contract");
        gOHM = IgOHM(_gOHM);
    }

    // do this last
    function initialize(address _stakingContract, address _treasury) external {
        require(msg.sender == initializer, "Initializer:  caller is not initializer");

        require(_stakingContract != address(0), "Staking");
        stakingContract = _stakingContract;
        _gonBalances[stakingContract] = TOTAL_GONS;

        require(_treasury != address(0), "Zero address: Treasury");
        treasury = _treasury;

        emit Transfer(address(0x0), stakingContract, _totalSupply);
        emit LogStakingContractUpdated(stakingContract);

        initializer = address(0);
    }

    /* ========== REBASE ========== */

    /**
        TODO 目前先不清楚变基的具体细节，只知道目的是让质押者能得到OHM增产的收益
        @notice increases rOHM supply to increase staking balances relative to profit_
        @param profit_ uint256
        @return uint256
     */
     //参考：https://docs.olympusdao.finance/main/basics/basics#what-is-a-rebase
    function rebase(uint256 profit_, uint256 epoch_) public override onlyStakingContract returns (uint256) {
        uint256 rebaseAmount;
        //获取流通中的sOHM（流动资金=总sOHM供应量-staking合约的sOHM总份额()+gOHM总流动性折算OHM的总价值+质押合约中处于质押热身阶段的OHM）
        uint256 circulatingSupply_ = circulatingSupply();//
        if (profit_ == 0) {
            //返回sOHM当前供应总额
            emit LogSupply(epoch_, _totalSupply);
            emit LogRebase(epoch_, 0, index());
            return _totalSupply;
        } else if (circulatingSupply_ > 0) {
            rebaseAmount = profit_.mul(_totalSupply).div(circulatingSupply_); //TODO 不知道这个算法的目的
        } else {
            rebaseAmount = profit_;
        }

        _totalSupply = _totalSupply.add(rebaseAmount);
        //不得超过sOHM最大供应量
        if (_totalSupply > MAX_SUPPLY) {
            _totalSupply = MAX_SUPPLY;
        }

        _gonsPerFragment = TOTAL_GONS.div(_totalSupply);

        _storeRebase(circulatingSupply_, profit_, epoch_);

        return _totalSupply;
    }

    /**
        @notice emits event with data about rebase
        @param previousCirculating_ uint
        @param profit_ uint
        @param epoch_ uint
     */
    function _storeRebase(
        uint256 previousCirculating_,
        uint256 profit_,
        uint256 epoch_
    ) internal {
        uint256 rebasePercent = profit_.mul(1e18).div(previousCirculating_);
        rebases.push(
            Rebase({
                epoch: epoch_,                             //当前阶段的起始区块
                rebase: rebasePercent, // 18 decimals      //
                totalStakedBefore: previousCirculating_,   //变基前总流通中的sOHM
                totalStakedAfter: circulatingSupply(),      //变基后总流通中的sOHM
                amountRebased: profit_,                     //变基的份额
                index: index(),                             //索引
                blockNumberOccured: block.number            //当前区块（即结束区块）
            })
        );

        emit LogSupply(epoch_, _totalSupply);
        emit LogRebase(epoch_, rebasePercent, index());
    }

    /* ========== MUTATIVE FUNCTIONS =========== */

    function transfer(address to, uint256 value) public override(IERC20, ERC20) returns (bool) {
        uint256 gonValue = value.mul(_gonsPerFragment);

        _gonBalances[msg.sender] = _gonBalances[msg.sender].sub(gonValue);
        _gonBalances[to] = _gonBalances[to].add(gonValue);

        require(balanceOf(msg.sender) >= debtBalances[msg.sender], "Debt: cannot transfer amount");
        emit Transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) public override(IERC20, ERC20) returns (bool) {
        _allowedValue[from][msg.sender] = _allowedValue[from][msg.sender].sub(value);
        emit Approval(from, msg.sender, _allowedValue[from][msg.sender]);

        uint256 gonValue = gonsForBalance(value);
        _gonBalances[from] = _gonBalances[from].sub(gonValue);
        _gonBalances[to] = _gonBalances[to].add(gonValue);

        require(balanceOf(from) >= debtBalances[from], "Debt: cannot transfer amount");
        emit Transfer(from, to, value);
        return true;
    }

    function approve(address spender, uint256 value) public override(IERC20, ERC20) returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public override returns (bool) {
        _approve(msg.sender, spender, _allowedValue[msg.sender][spender].add(addedValue));
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public override returns (bool) {
        uint256 oldValue = _allowedValue[msg.sender][spender];
        if (subtractedValue >= oldValue) {
            _approve(msg.sender, spender, 0);
        } else {
            _approve(msg.sender, spender, oldValue.sub(subtractedValue));
        }
        return true;
    }

    // 变更借款者当前欠款份额 this function is called by the treasury, and informs sOHM of changes to debt.
    // note that addresses with debt balances cannot transfer collateralized sOHM
    // until the debt has been repaid.
    function changeDebt(
        uint256 amount,  //变化的额度
        address debtor,  //欠款者
        bool add         //是否接增加已欠款额度  true: 已欠款额度增加  false:已欠款额度减少
    ) external override {
        require(msg.sender == treasury, "Only treasury");
        if (add) {
            debtBalances[debtor] = debtBalances[debtor].add(amount);
        } else {
            debtBalances[debtor] = debtBalances[debtor].sub(amount);
        }
        require(debtBalances[debtor] <= balanceOf(debtor), "sOHM: insufficient balance");
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function _approve(
        address owner,
        address spender,
        uint256 value
    ) internal virtual override {
        _allowedValue[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    /* ========== VIEW FUNCTIONS ========== */

    function balanceOf(address who) public view override(IERC20, ERC20) returns (uint256) {
        return _gonBalances[who].div(_gonsPerFragment);
    }

    //计算gons份额这算回sOHM份额
    function gonsForBalance(uint256 amount) public view override returns (uint256) {
        return amount.mul(_gonsPerFragment);
    }

    // 计算sOHM的份额这算会gons的份额
    function balanceForGons(uint256 gons) public view override returns (uint256) {
        return gons.div(_gonsPerFragment);
    }

    // 计算sOHM折算回gOHM【toG converts an sOHM balance to gOHM terms. gOHM is an 18 decimal token. balance given is in 18 decimal format.】
    function toG(uint256 amount) external view override returns (uint256) {
        return gOHM.balanceTo(amount);
    }

    // 计算gOHM的份额折算回sOHM有多少【fromG converts a gOHM balance to sOHM terms. sOHM is a 9 decimal token. balance given is in 9 decimal format.】
    function fromG(uint256 amount) external view override returns (uint256) {
        return gOHM.balanceFrom(amount);
    }

    //获取当前sOHM的流动份额（Staking contract holds excess sOHM）
    //在市场上流通并掌握在公众手中的硬币数量。它类似于股票市场中流动的股票
    function circulatingSupply() public view override returns (uint256) {
        //流动资金=总sOHM供应量-staking合约的sOHM总份额+gOHM总流动性折算OHM的总价值+质押合约中处于质押热身阶段的OHM
        return
            _totalSupply.sub(balanceOf(stakingContract)).add(gOHM.balanceFrom(IERC20(address(gOHM)).totalSupply())).add(
                IStaking(stakingContract).supplyInWarmup()
            );
    }

    function index() public view override returns (uint256) {
        return balanceForGons(INDEX);
    }

    function allowance(address owner_, address spender) public view override(IERC20, ERC20) returns (uint256) {
        return _allowedValue[owner_][spender];
    }
}
