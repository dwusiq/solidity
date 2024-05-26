// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.7.5;

import "./libraries/SafeERC20.sol";
import "./libraries/SafeMath.sol";

import "./interfaces/IERC20.sol";
import "./interfaces/ITreasury.sol";
import "./interfaces/IDistributor.sol";

import "./types/OlympusAccessControlled.sol";

//Distributor：分配者（1、可以配置收益者的收益占总OHM供应的比例，2、给staking合约铸币用户质押分红）
contract Distributor is IDistributor, OlympusAccessControlled {
    /* ========== DEPENDENCIES ========== */

    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /* ====== VARIABLES ====== */

    IERC20 private immutable ohm;
    ITreasury private immutable treasury;
    address private immutable staking;

    mapping(uint256 => Adjust) public adjustments;
    uint256 public override bounty;

    uint256 private immutable rateDenominator = 1_000_000;//分红比例的分母是1000000

    /* ====== STRUCTS ====== */

   //有分红的用户地址
    struct Info {
        uint256 rate; // 分红占比【in ten-thousandths ( 5000 = 0.5% )】
        address recipient; //分红接收地址
    }
    Info[] public info;

   //收益调整信息
    struct Adjust {
        bool add;        //是否新增
        uint256 rate;    //本次调整波动比率
        uint256 target;  //当减少收益率时的调整后最小值，当增加收益率时的调整后最大值
    }

    /* ====== CONSTRUCTOR ====== */

    constructor(
        address _treasury,
        address _ohm,
        address _staking,
        address _authority
    ) OlympusAccessControlled(IOlympusAuthority(_authority)) {
        require(_treasury != address(0), "Zero address: Treasury");
        treasury = ITreasury(_treasury);
        require(_ohm != address(0), "Zero address: OHM");
        ohm = IERC20(_ohm);
        require(_staking != address(0), "Zero address: Staking");
        staking = _staking;
    }

    /* ====== PUBLIC FUNCTIONS ====== */

    /**
        @notice 分配分红【send epoch reward to staking contract】
     */
    function distribute() external override {
        require(msg.sender == staking, "Only staking");
        // distribute rewards to each recipient
        for (uint256 i = 0; i < info.length; i++) {
            if (info[i].rate > 0) {
                treasury.mint(info[i].recipient, nextRewardAt(info[i].rate)); // 按比例给每个收益用户铸币【mint and send tokens】
                adjust(i); //  调整收集者的分红收益率【check for adjustment】
            }
        }
    }


    //  @notice 给staking合约铸币，用于给质押者的分红分红
    function retrieveBounty() external override returns (uint256) {
        require(msg.sender == staking, "Only staking");
        // If the distributor bounty is > 0, mint it for the staking contract.
        if (bounty > 0) {
            treasury.mint(address(staking), bounty);
        }

        return bounty;
    }

    /* ====== INTERNAL FUNCTIONS ====== */

    /**
        @notice 调整收集者的分红收益率【ncrement reward rate for collector】
     */
    function adjust(uint256 _index) internal {
        Adjust memory adjustment = adjustments[_index];
        if (adjustment.rate != 0) {
            if (adjustment.add) {
                // 调整“增加收益率”的配置【if rate should increase】
                info[_index].rate = info[_index].rate.add(adjustment.rate); // raise rate
                if (info[_index].rate >= adjustment.target) {  //如果是add，则调整后的rate不能大于target
                    // if target met
                    adjustments[_index].rate = 0; // turn off adjustment
                    info[_index].rate = adjustment.target; // set to target
                }
            } else {
                // 调整“减少收益率”的配置 【if rate should decrease】
                if (info[_index].rate > adjustment.rate) {
                    // protect from underflow
                    info[_index].rate = info[_index].rate.sub(adjustment.rate); // lower rate
                } else {
                    info[_index].rate = 0;
                }

                if (info[_index].rate <= adjustment.target) { //如果是减少，则调整后的rate不能小于target
                    // if target met
                    adjustments[_index].rate = 0; // turn off adjustment
                    info[_index].rate = adjustment.target; // set to target
                }
            }
        }
    }

    /* ====== VIEW FUNCTIONS ====== */

    /**
        @notice 查看指定比率的下一个奖励金额是多少【view function for next reward at given rate】
        @param _rate uint
        @return uint
     */
    function nextRewardAt(uint256 _rate) public view override returns (uint256) {
        return ohm.totalSupply().mul(_rate).div(rateDenominator);
    }

    /**
        @notice 查看指定地址的下一个奖励金额是多少【view function for next reward for specified address】
        @param _recipient address
        @return uint
     */
    function nextRewardFor(address _recipient) public view override returns (uint256) {
        uint256 reward;
        for (uint256 i = 0; i < info.length; i++) {
            if (info[i].recipient == _recipient) {
                reward = reward.add(nextRewardAt(info[i].rate));
            }
        }
        return reward;
    }

    /* ====== POLICY FUNCTIONS ====== */

    /**
     * @notice 设置每次给`OHM`的质押者分配的总分红【set bounty to incentivize keepers】
     * @param _bounty uint256
     */
    function setBounty(uint256 _bounty) external override onlyGovernor {
        require(_bounty <= 2e9, "Too much");
        bounty = _bounty;
    }

    /**
        @notice 添加分配OHM的接收地址【adds recipient for distributions】
        @param _recipient address  接收地址
        @param _rewardRate uint   收益比例
     */
    function addRecipient(address _recipient, uint256 _rewardRate) external override onlyGovernor {
        require(_recipient != address(0), "Zero address: Recipient");
        require(_rewardRate <= rateDenominator, "Rate cannot exceed denominator");
        info.push(Info({recipient: _recipient, rate: _rewardRate}));
    }

    /**
        notice 将用户从分红用户列表中移除【removes recipient for distributions】
        @param _index uint
     */
    function removeRecipient(uint256 _index) external override {
        require(
            msg.sender == authority.governor() || msg.sender == authority.guardian(),
            "Caller is not governor or guardian"
        );
        require(info[_index].recipient != address(0), "Recipient does not exist");
        info[_index].recipient = address(0);
        info[_index].rate = 0;
    }

    /**
        @notice 调整用户的分红比率的下次变更参数（在distribute分配分红后，会按这里设置的ajust参数调整下一次分红比率）【set adjustment info for a collector's reward rate】
        @param _index uint   info数组中的索引id
        @param _add bool     是增加分红收益还是减少  true:增加分红收益  false:减少分红收益
        @param _rate uint    本次调整的比率（新增或减少）
        @param _target uint  如果是新增，则新增后的rate不能大于_target,如果是减少，则减少后的rate不能小于_target
     */
    function setAdjustment(
        uint256 _index,
        bool _add,        
        uint256 _rate,
        uint256 _target
    ) external override {
        require(
            msg.sender == authority.governor() || msg.sender == authority.guardian(),
            "Caller is not governor or guardian"
        );
        require(info[_index].recipient != address(0), "Recipient does not exist");

        if (msg.sender == authority.guardian()) {
            require(_rate <= info[_index].rate.mul(25).div(1000), "Limiter: cannot adjust by >2.5%");
        }

        //如果是减少收益率，则减少的幅度不能大于当前的比率。
        if (!_add) {
            require(_rate <= info[_index].rate, "Cannot decrease rate by more than it already is");
        }

        adjustments[_index] = Adjust({add: _add, rate: _rate, target: _target});
    }
}
