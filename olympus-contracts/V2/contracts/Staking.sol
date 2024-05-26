// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.7.5;

import "./libraries/SafeMath.sol";
import "./libraries/SafeERC20.sol";

import "./interfaces/IERC20.sol";
import "./interfaces/IsOHM.sol";
import "./interfaces/IgOHM.sol";
import "./interfaces/IDistributor.sol";

import "./types/OlympusAccessControlled.sol";

//质押合约，每个纪元（一个时间段）触发一次价格调整（Rebase的代币都有一个目标价格，当价格高于目标价时，就会自动增发；反之会进行通缩）
contract OlympusStaking is OlympusAccessControlled {
    /* ========== DEPENDENCIES ========== */

    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using SafeERC20 for IsOHM;
    using SafeERC20 for IgOHM;

    /* ========== EVENTS ========== */

    event DistributorSet(address distributor);
    event WarmupSet(uint256 warmup);

    /* ========== DATA STRUCTURES ========== */
    //纪元信息
    struct Epoch {
        uint256 length; // 时间长度（秒）【in seconds】
        uint256 number; // 指定当前纪元的起始区块【since inception】
        uint256 end; // 结束的时间戳【timestamp】
        uint256 distribute; // amount
    }

    struct Claim {
        uint256 deposit; // if forfeiting
        uint256 gons; // 质押的gons份额【staked balance】
        uint256 expiry; // 热身结束【end of warmup period】
        bool lock; // 防止恶意延迟赎回【prevents malicious delays for claim】
    }

    /* ========== STATE VARIABLES ========== */

    IERC20 public immutable OHM;
    IsOHM public immutable sOHM;
    IgOHM public immutable gOHM;

    Epoch public epoch;

    IDistributor public distributor;

    mapping(address => Claim) public warmupInfo;
    uint256 public warmupPeriod;//参与者的热身时长，如果用户从质押到取出的时间没超过这个值，则智能赎回本金而没有收益（由于Governor设置，单位：区块），参考：https://forum.olympusdao.finance/d/47-introduce-warm-up-for-staking
    uint256 private gonsInWarmup;//当前在热身中的gons总额

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _ohm,
        address _sOHM,
        address _gOHM,
        uint256 _epochLength,
        uint256 _firstEpochNumber,
        uint256 _firstEpochTime,
        address _authority
    ) OlympusAccessControlled(IOlympusAuthority(_authority)) {
        require(_ohm != address(0), "Zero address: OHM");
        OHM = IERC20(_ohm);
        require(_sOHM != address(0), "Zero address: sOHM");
        sOHM = IsOHM(_sOHM);
        require(_gOHM != address(0), "Zero address: gOHM");
        gOHM = IgOHM(_gOHM);

        epoch = Epoch({
            length: _epochLength,
            number: _firstEpochNumber,
            end: _firstEpochTime,
            distribute: 0
        });
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @notice 质押OHM【stake OHM to enter warmup】
     * @param _to address  //质押的份额归属地址（当前只能是sender）
     * @param _amount uint //质押OHM的份额
     * @param _claim bool  // 是否索赔
     * @param _rebasing bool    true: 直接从当前合约转sOHM给指定地址。 false: amount转成gOHM的份额后，给指定地址铸造等额的gOHM
     * @return uint
     */
    function stake(
        address _to,
        uint256 _amount,
        bool _rebasing,
        bool _claim
    ) external returns (uint256) {
        OHM.safeTransferFrom(msg.sender, address(this), _amount);
        _amount = _amount.add(rebase()); // 变基，增加赏金【add bounty if rebase occurred】
        if (_claim && warmupPeriod == 0) {
            //不需要热身等待，直接根据stake的OHM份额转sOHM/gOHM给用户
            //_rebasing=true:转sOHM, _rebasing=false:铸造gOHM
            return _send(_to, _amount, _rebasing);
        } else {
            //需要热身等待，添加到热身等待
            // Claim memory info = warmupInfo[_to];
            if (!info.lock) {
                require(
                    _to == msg.sender,
                    "External deposits for account are locked"
                );
            }

            warmupInfo[_to] = Claim({
                deposit: info.deposit.add(_amount),//金额累加
                gons: info.gons.add(sOHM.gonsForBalance(_amount)), //到期后可提取的收益
                expiry: epoch.number.add(warmupPeriod),
                lock: info.lock
            });

            gonsInWarmup = gonsInWarmup.add(sOHM.gonsForBalance(_amount));

            return _amount;
        }
    }

    /**
     * @notice 锁仓期到了之后，从热身中赎回自己质押的所有份额（得到sOHM或gOHM）【retrieve stake from warmup】
     * @param _to address
     * @param _rebasing bool
     * @return uint
     */
    function claim(address _to, bool _rebasing) public returns (uint256) {
        Claim memory info = warmupInfo[_to];

        if (!info.lock) {
            require(
                _to == msg.sender,
                "External claims for accoun t are locked"
            );
        }
        //要求用户质押时的那个阶段(epoch)已结束（即已开启第二个阶段）
        if (epoch.number >= info.expiry && info.expiry != 0) {
            delete warmupInfo[_to];

            gonsInWarmup = gonsInWarmup.sub(info.gons);

            // _rebasing  true:从当前合约转sOHM份额给用户  false: 直接调用gOHM合约给用户铸造相应份额
            return _send(_to, sOHM.balanceForGons(info.gons), _rebasing);
        }
        return 0;
    }

    /**
     * @notice 从热身中赎回自己质押的所有份额（得到OHM）【forfeit stake and retrieve OHM】
     * @return uint
     */
    function forfeit() external returns (uint256) {
        Claim memory info = warmupInfo[msg.sender];
        delete warmupInfo[msg.sender];

        gonsInWarmup = gonsInWarmup.sub(info.gons);

        OHM.safeTransfer(msg.sender, info.deposit);

        return info.deposit;
    }

    /**
     * @notice 切换锁的状态（影响提取收益的用户地址）  TODO 任何用户都可以调用？  prevent new deposits or claims from ext. address (protection from malicious activity)
     */
    function toggleLock() external {
        warmupInfo[msg.sender].lock = !warmupInfo[msg.sender].lock;
    }

    /**
     * @notice 用sOHM或gOHM赎回指定份额的OHM【redeem sOHM for OHMs】
     * @param _to address     //接收地址
     * @param _amount uint    //赎回份额
     * @param _trigger bool   //赎回之前是否需要变基
     * @param _rebasing bool  // true:从用户钱包中扣除相应sOHM  false: 从用户钱包销毁gOHM
     * @return amount_ uint
     */
    function unstake(
        address _to,   
        uint256 _amount, 
        bool _trigger,   
        bool _rebasing
    ) external returns (uint256 amount_) {
        amount_ = _amount;
        uint256 bounty;
        if (_trigger) {
            bounty = rebase();
        }

        //判断是扣sOHM还是gOHM
        if (_rebasing) {
            sOHM.safeTransferFrom(msg.sender, address(this), _amount);
            amount_ = amount_.add(bounty);
        } else {
            gOHM.burn(msg.sender, _amount); // amount was given in gOHM terms
            amount_ = gOHM.balanceFrom(amount_).add(bounty); // convert amount to OHM terms & add bounty
        }

        require(
            amount_ <= OHM.balanceOf(address(this)),
            "Insufficient OHM balance in contract"
        );
        OHM.safeTransfer(_to, amount_);//转OHM给用户
    }

    /**
     * @notice 将sOHM兑换成gOHM【convert _amount sOHM into gBalance_ gOHM】
     * @param _to address
     * @param _amount uint
     * @return gBalance_ uint
     */
    function wrap(address _to, uint256 _amount)
        external
        returns (uint256 gBalance_)
    {
        sOHM.safeTransferFrom(msg.sender, address(this), _amount);
        gBalance_ = gOHM.balanceTo(_amount);
        gOHM.mint(_to, gBalance_);//铸造gOHM
    }

    /**
     * @notice 将gOHM的份额兑换回sOHM的【convert _amount gOHM into sBalance_ sOHM】
     * @param _to address
     * @param _amount uint
     * @return sBalance_ uint
     */
    function unwrap(address _to, uint256 _amount)
        external
        returns (uint256 sBalance_)
    {
        gOHM.burn(msg.sender, _amount);//销毁gOHM
        sBalance_ = gOHM.balanceFrom(_amount);
        sOHM.safeTransfer(_to, sBalance_);
    }

    /**
     * @notice 判断当前epoch是否已结束，如果epoch已结束，触发rebase【trigger rebase if epoch over】
     * @return uint256
     */
    function rebase() public returns (uint256) {
        uint256 bounty;
        //当前期的epoch已结束才触发变基
        if (epoch.end <= block.timestamp) {
            sOHM.rebase(epoch.distribute, epoch.number);

           //开启下一个纪元
            epoch.end = epoch.end.add(epoch.length);
            epoch.number++;

            //如果配置了distributor合约地址，则mint分红奖
            if (address(distributor) != address(0)) {
                distributor.distribute();//给事先配置的分红地址mint发OHm
                //最终通过Treasury调用OHM给当前staking合约mint分红奖【Will mint ohm for this contract if there exists a bounty】
                bounty = distributor.retrieveBounty(); 
            }
            uint256 balance = OHM.balanceOf(address(this));
            uint256 staked = sOHM.circulatingSupply();//获取sOHM除了在staking合约之外的总份额
            if (balance <= staked.add(bounty)) {
                epoch.distribute = 0;
            } else {
                epoch.distribute = balance.sub(staked).sub(bounty);
            }
        }
        return bounty;
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /**
     * @notice 从当前合约将（sOHM/gOHM）转给指定用户【send staker their amount as sOHM or gOHM】
     * @param _to address         接收者地址
     * @param _amount uint        转移的份额
     * @param _rebasing bool      true: 直接从当前合约转sOHM给指定地址。 false: amount转成gOHM的份额后，给指定地址铸造等额的gOHM
     */
    function _send(
        address _to,
        uint256 _amount,
        bool _rebasing
    ) internal returns (uint256) {
        if (_rebasing) {
            sOHM.safeTransfer(_to, _amount); // 转换sOHM【send as sOHM (equal unit as OHM)】
            return _amount;
        } else {
            gOHM.mint(_to, gOHM.balanceTo(_amount)); // 将OHM的份额转成gOHM的份额后，铸造相应份额的gOHM【send as gOHM (convert units from OHM)】
            return gOHM.balanceTo(_amount);
        }
    }

    /* ========== VIEW FUNCTIONS ========== */

    /**
     * @notice returns the sOHM index, which tracks rebase growth
     * @return uint
     */
    function index() public view returns (uint256) {
        return sOHM.index();
    }

    /**
     * @notice 当前在热身中的sOHM，由gonsInWarmup折算sOHM【total supply in warmup】
     */
    function supplyInWarmup() public view returns (uint256) {
        return sOHM.balanceForGons(gonsInWarmup);
    }

    /**
     * @notice 还有多久到下一轮纪元（即本轮纪元还有多久结束）【seconds until the next epoch begins】
     */
    function secondsToNextEpoch() external view returns (uint256) {
        return epoch.end.sub(block.timestamp);
    }

    /* ========== MANAGERIAL FUNCTIONS ========== */

    /**
     * @notice 变更`StakingDistributor`合约地址。【sets the contract address for LP staking】
     * @param _distributor address
     */
    function setDistributor(address _distributor) external onlyGovernor {
        distributor = IDistributor(_distributor);
        emit DistributorSet(_distributor);
    }

    /**
     * @notice 为新参与者设置热身时间，从存入到取出之间的时间如果不超过该值，则只能取回本金而没有受益【set warmup period for new stakers】
     * @param _warmupPeriod uint
     */
    function setWarmupLength(uint256 _warmupPeriod) external onlyGovernor {
        warmupPeriod = _warmupPeriod;
        emit WarmupSet(_warmupPeriod);
    }
}
