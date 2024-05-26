// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.7.5;

import "./libraries/SafeMath.sol";
import "./libraries/SafeERC20.sol";

import "./interfaces/IERC20.sol";
import "./interfaces/ITreasury.sol";
import "./interfaces/IStaking.sol";
import "./interfaces/IOwnable.sol";
import "./interfaces/IsOHM.sol";
import "./interfaces/ITeller.sol";

import "./types/OlympusAccessControlled.sol";

//债券出纳员
contract BondTeller is ITeller, OlympusAccessControlled {
    /* ========== DEPENDENCIES ========== */

    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using SafeERC20 for IsOHM;

    /* ========== EVENTS =========== */

    event BondCreated(address indexed bonder, uint256 payout, uint256 expires);
    event Redeemed(address indexed bonder, uint256 payout);

    /* ========== MODIFIERS ========== */

    modifier onlyDepository() {
        require(msg.sender == depository, "Only depository");
        _;
    }

    /* ========== STRUCTS ========== */

    // 用户持有的债券信息【Info for bond holder】
    struct Bond {
        address principal; // token used to pay for bond
        uint256 principalPaid; // amount of principal token paid for bond
        uint256 payout; // sOHM remaining to be paid. agnostic balance
        uint256 vested; // Block when bond is vested
        uint256 created; // time bond was created
        uint256 redeemed; // time bond was redeemed
    }

    /* ========== STATE VARIABLES ========== */

    address internal immutable depository; // contract where users deposit bonds
    IStaking internal immutable staking; // contract to stake payout
    ITreasury internal immutable treasury;
    IERC20 internal immutable OHM;
    IsOHM internal immutable sOHM; // payment token

    mapping(address => Bond[]) public bonderInfo; // 用户购买的债券列表【user data】
    mapping(address => uint256[]) public indexesFor; // 用户购买债券的索引【user bond indexes】

    mapping(address => uint256) public FERs; // 用户可领取奖励的份额【front end operator rewards】
    uint256 public feReward;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _depository,
        address _staking,
        address _treasury,
        address _ohm,
        address _sOHM,
        address _authority
    ) OlympusAccessControlled(IOlympusAuthority(_authority)) {
        require(_depository != address(0), "Zero address: Depository");
        depository = _depository;
        require(_staking != address(0), "Zero address: Staking");
        staking = IStaking(_staking);
        require(_treasury != address(0), "Zero address: Treasury");
        treasury = ITreasury(_treasury);
        require(_ohm != address(0), "Zero address: OHM");
        OHM = IERC20(_ohm);
        require(_sOHM != address(0), "Zero address: sOHM");
        sOHM = IsOHM(_sOHM);
    }

    /* ========== DEPOSITORY FUNCTIONS ========== */

    /**
     * @notice 保存用户持有债券的信息【add new bond payout to user data】
     * @param _bonder address            //债券购买者
     * @param _principal address         //合约收到的资产地址
     * @param _principalPaid uint256     //合约收到的资产份额
     * @param _payout uint256            //合约需支付的OHM份额
     * @param _expires uint256           //到期时间，到期后可取回benjin
     * @param _feo address               //这个地址由合约调用方传入（将接受额外部分奖励分配）
     * @return index_ uint256
     */
    function newBond(
        address _bonder,
        address _principal,
        uint256 _principalPaid,
        uint256 _payout,
        uint256 _expires,
        address _feo
    ) external override onlyDepository returns (uint256 index_) {
        //额外奖励奖励=需支付的债券报酬*奖励分配
        uint256 reward = _payout.mul(feReward).div(10_000);
        //协议给当前合约铸造OHM
        treasury.mint(address(this), _payout.add(reward));
        //这些债券报酬先用于质押得到sOHM(用户提取的报酬将是sOHM)-------在用户领取这些报酬之前，如果协议有给质押用户分发报酬的话，那当前合约也能分一份
        OHM.approve(address(staking), _payout);
        staking.stake(address(this), _payout, true, true);
        //记录可额外领取的报酬
        FERs[_feo] = FERs[_feo].add(reward); // front end operator reward

        index_ = bonderInfo[_bonder].length;

        // 存储债券报酬信息【store bond & stake payout】
        bonderInfo[_bonder].push(
            Bond({
                principal: _principal,
                principalPaid: _principalPaid,
                payout: sOHM.toG(_payout),
                vested: _expires,
                created: block.timestamp,
                redeemed: 0
            })
        );
    }

    /* ========== INTERACTABLE FUNCTIONS ========== */

    /**
     *  @notice 提取指定地址的所有债券报酬【redeems all redeemable bonds】
     *  @param _bonder address  
     *  @return uint256
     */
    function redeemAll(address _bonder) external override returns (uint256) {
        updateIndexesFor(_bonder);
        return redeem(_bonder, indexesFor[_bonder]);
    }

    /**
     *  @notice 根据用户地址和索引支付债券报酬给用户（sOHM）【redeem bond for user】
     *  @param _bonder address
     *  @param _indexes calldata uint256[]
     *  @return uint256
     */
    function redeem(address _bonder, uint256[] memory _indexes) public override returns (uint256) {
        uint256 dues;
        for (uint256 i = 0; i < _indexes.length; i++) {
            Bond memory info = bonderInfo[_bonder][_indexes[i]];

            //如果可以领取债券报酬，就领取并且记录当前时间戳
            if (pendingFor(_bonder, _indexes[i]) != 0) {
                bonderInfo[_bonder][_indexes[i]].redeemed = block.timestamp; // mark as redeemed

                dues = dues.add(info.payout);
            }
        }

        //份额转换成sOHM，并提取给用户
        dues = sOHM.fromG(dues);
        emit Redeemed(_bonder, dues);
        pay(_bonder, dues);
        return dues;
    }

    // 领取自己的奖励（OHM）【pay reward to front end operator】
    function getReward() external override {
        uint256 reward = FERs[msg.sender];
        FERs[msg.sender] = 0;
        OHM.safeTransfer(msg.sender, reward);
    }

    /* ========== OWNABLE FUNCTIONS ========== */

    // 设置奖励的比值（用户购买债券时会传入收益地址，将按用户的报酬乘于这个比值，给收益地址额外分配奖励）【set reward for front end operator (4 decimals. 100 = 1%)】
    function setFEReward(uint256 reward) external override onlyPolicy {
        feReward = reward;
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /**
     *  @notice （本合约调用该接口）发送支出的份额给用户(sOHM)【send payout】
     *  @param _amount uint256
     */
    function pay(address _bonder, uint256 _amount) internal {
        sOHM.safeTransfer(_bonder, _amount);
    }

    /* ========== VIEW FUNCTIONS ========== */

    /**
     *  @notice 更新用户购买的债券的索引列表（只保留未领取债券报酬的索引）【returns indexes of live bonds】
     *  @param _bonder address
     */
    function updateIndexesFor(address _bonder) public override {
        Bond[] memory info = bonderInfo[_bonder];
        delete indexesFor[_bonder];
        for (uint256 i = 0; i < info.length; i++) {
            if (info[i].redeemed == 0) {
                indexesFor[_bonder].push(i);
            }
        }
    }

    // PAYOUT

    /**
     * @notice 根据用户地址和债券索引查询待兑现的债券报酬（OHM）【calculate amount of OHM available for claim for single bond】
     * @param _bonder address
     * @param _index uint256
     * @return uint256
     */
    function pendingFor(address _bonder, uint256 _index) public view override returns (uint256) {
        //redeemed==0: 用户未领取报酬   
        //vested <= block.number：债券已解锁，可提取报酬
        if (bonderInfo[_bonder][_index].redeemed == 0 && bonderInfo[_bonder][_index].vested <= block.number) {
            return bonderInfo[_bonder][_index].payout;
        }
        return 0;
    }

    /**
     * @notice 根据用户地址和债券索引数组查询带发放的奖励总数（OHM）【calculate amount of OHM available for claim for array of bonds】
     * @param _bonder address
     * @param _indexes uint256[]
     * @return pending_ uint256
     */
    function pendingForIndexes(address _bonder, uint256[] memory _indexes) public view override returns (uint256 pending_) {
        for (uint256 i = 0; i < _indexes.length; i++) {
            pending_ = pending_.add(pendingFor(_bonder, i));
        }
        pending_ = sOHM.fromG(pending_);
    }

    /**
     *  @notice 根据用户地址查询该用户的所有购买的债券中待发放的奖励总数（OHM）【total pending on all bonds for bonder】
     *  @param _bonder address
     *  @return pending_ uint256
     */
    function totalPendingFor(address _bonder) public view override returns (uint256 pending_) {
        Bond[] memory info = bonderInfo[_bonder];
        for (uint256 i = 0; i < info.length; i++) {
            pending_ = pending_.add(pendingFor(_bonder, i));
        }
        pending_ = sOHM.fromG(pending_);
    }

    // VESTING

    /**
     * @notice calculate how far into vesting a depositor is
     * @param _bonder address
     * @param _index uint256
     * @return percentVested_ uint256
     */
    function percentVestedFor(address _bonder, uint256 _index) public view override returns (uint256 percentVested_) {
        Bond memory bond = bonderInfo[_bonder][_index];

        //从购买债券到当前经历的时长
        uint256 timeSince = block.timestamp.sub(bond.created);
        uint256 term = bond.vested.sub(bond.created);

        percentVested_ = timeSince.mul(1e9).div(term);
    }
}
