// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.7.5;
pragma abicoder v2;

import "./libraries/SafeMath.sol";
import "./libraries/FixedPoint.sol";
import "./libraries/Address.sol";
import "./libraries/SafeERC20.sol";

import "./types/OlympusAccessControlled.sol";

import "./interfaces/ITreasury.sol";
import "./interfaces/IBondingCalculator.sol";
import "./interfaces/ITeller.sol";
import "./interfaces/IERC20Metadata.sol";

contract OlympusBondDepository is OlympusAccessControlled {
  using FixedPoint for *;
  using SafeERC20 for IERC20;
  using SafeMath for uint256;

  /* ======== EVENTS ======== */

  event beforeBond(uint256 index, uint256 price, uint256 internalPrice, uint256 debtRatio);
  event CreateBond(uint256 index, uint256 amount, uint256 payout, uint256 expires);
  event afterBond(uint256 index, uint256 price, uint256 internalPrice, uint256 debtRatio);

  /* ======== STRUCTS ======== */

  // 记录不同类型的债券信息【Info about each type of bond】
  struct Bond {
    IERC20 principal; // 指定购买债券需支付的币种（lp）【token to accept as payment】
    IBondingCalculator calculator; // 债券计算合约【contract to value principal】
    Terms terms; // 债券周期信息【terms of bond】
    bool termsSet; // 是否已设置债券周期【have terms been set】
    uint256 capacity; // 剩余的用量【capacity remaining】
    bool capacityIsPayout; // 指明限制的是什么类型的容量（true:本债券剩余最大支出。 false: 本债券剩余最大买进金额）capacity limit is for payout vs principal
    uint256 totalDebt; // 已销售债券总额【total debt from bond】
    uint256 lastDecay; // 上次待兑现债券衰减时的区块【last block when debt was decayed】
  }

  // 新创建的债券的发行周期信息【Info for creating new bonds】
  struct Terms {
    uint256 controlVariable; // 价格缩放变量【scaling variable for price（BCV）】
    bool fixedTerm; // 是否限定用户购买债券的锁定期限（true:则用户购买债券后等待vestingTerm个块可取回本金。 false:用户质押后要等到expiration指定的区块才能取回）  fixed term or fixed expiration
    uint256 vestingTerm; // 用户购买债券需要锁定的期限（OlympusDao在以太坊主网是33110个块，约5天）【term in blocks (fixed-term)】
    uint256 expiration; // 用户购买债券后要等区块升到这个值时才可取回本金【block number bond matures (fixed-expiration)】
    uint256 conclusion; // 债券出售截止区块（到这个区块就不能deposit了）【block number bond no longer offered】
    uint256 minimumPrice; // 债券最低价格【vs principal value】
    uint256 maxPayout; // 用户购买债券时，合约单笔最大支付的OHM份额【in thousandths of a %. i.e. 500 = 0.5%】
    uint256 maxDebt; // 本次债券周期允许出售债券最大额【9 decimal debt ratio, max % total supply created as debt】
  }

  /* ======== STATE VARIABLES ======== */

  mapping(uint256 => Bond) public bonds;
  address[] public IDs; // bond IDs

  ITeller public teller; // handles payment

  ITreasury immutable treasury;
  IERC20 immutable OHM;

  /* ======== CONSTRUCTOR ======== */

  constructor(
    address _OHM, 
    address _treasury, 
    address _authority
  ) OlympusAccessControlled(IOlympusAuthority(_authority)) {
    require(_OHM != address(0));
    OHM = IERC20(_OHM);
    require(_treasury != address(0));
    treasury = ITreasury(_treasury);
  }

  /* ======== POLICY FUNCTIONS ======== */

  /**
   * @notice 新增一个平台支持的债券类型【creates a new bond type】
   * @param _principal address     质押的资产地址
   * @param _calculator address    StandardBondingCalculator合约地址
   * @param _capacity uint         
   * @param _capacityIsPayout bool
   */
  function addBond(
    address _principal,
    address _calculator,
    uint256 _capacity,
    bool _capacityIsPayout
  ) external onlyGuardian returns (uint256 id_) {
    Terms memory terms = Terms({
      controlVariable: 0, 
      fixedTerm: false, 
      vestingTerm: 0, 
      expiration: 0, 
      conclusion: 0, 
      minimumPrice: 0, 
      maxPayout: 0, 
      maxDebt: 0
    });

    bonds[IDs.length] = Bond({
      principal: IERC20(_principal), 
      calculator: IBondingCalculator(_calculator), 
      terms: terms, 
      termsSet: false, 
      totalDebt: 0, 
      lastDecay: block.number, 
      capacity: _capacity, 
      capacityIsPayout: _capacityIsPayout
    });

    id_ = IDs.length;
    IDs.push(_principal);
  }

  /**
   * @notice 设置债券的售卖期信息【set minimum price for new bond】
   * @param _id uint                 //债券Id
   * @param _controlVariable uint    // 价格缩放变量
   * @param _fixedTerm bool          //
   * @param _vestingTerm uint
   * @param _expiration uint
   * @param _conclusion uint
   * @param _minimumPrice uint
   * @param _maxPayout uint
   * @param _maxDebt uint
   * @param _initialDebt uint
   */
  function setTerms(
    uint256 _id,
    uint256 _controlVariable,
    bool _fixedTerm,
    uint256 _vestingTerm,
    uint256 _expiration,
    uint256 _conclusion,
    uint256 _minimumPrice,
    uint256 _maxPayout,
    uint256 _maxDebt,
    uint256 _initialDebt
  ) external onlyGuardian {
    require(!bonds[_id].termsSet, "Already set");

    Terms memory terms = Terms({
      controlVariable: _controlVariable, 
      fixedTerm: _fixedTerm, 
      vestingTerm: _vestingTerm, 
      expiration: _expiration, 
      conclusion: _conclusion, 
      minimumPrice: _minimumPrice, 
      maxPayout: _maxPayout, 
      maxDebt: _maxDebt
    });

    bonds[_id].terms = terms;
    bonds[_id].totalDebt = _initialDebt;
    bonds[_id].termsSet = true;
  }

  /**
   * @notice 禁用现有债券【disable existing bond】
   * @param _id uint
   */
  function deprecateBond(uint256 _id) external onlyGuardian {
    bonds[_id].capacity = 0;
  }

  /**
   * @notice 设置teller合约地址【set teller contract】
   * @param _teller address
   */
  function setTeller(address _teller) external onlyGovernor {
    require(address(teller) == address(0));
    require(_teller != address(0));
    teller = ITeller(_teller);
  }

  /* ======== MUTABLE FUNCTIONS ======== */

  /**
   * @notice 购买债券【deposit bond】
   * @param _amount uint         //用户支付的费用份额
   * @param _maxPrice uint       //用户自己接受的最大价格
   * @param _depositor address   //债券收益接收者
   * @param _BID uint            //债券编号
   * @param _feo address         //这个地址由前端传入（接受部分奖励分配）
   * @return uint
   */
  function deposit(
    uint256 _amount,
    uint256 _maxPrice,
    address _depositor,
    uint256 _BID,
    address _feo
  ) external returns (uint256, uint256) {
    require(_depositor != address(0), "Invalid address");

    Bond memory info = bonds[_BID];

    require(bonds[_BID].termsSet, "Not initialized");
    require(block.number < info.terms.conclusion, "Bond concluded");

    emit beforeBond(_BID, bondPriceInUSD(_BID), bondPrice(_BID), debtRatio(_BID));

    //债务衰减
    decayDebt(_BID);

    require(info.totalDebt <= info.terms.maxDebt, "Max debt exceeded");
    require(_maxPrice >= _bondPrice(_BID), "Slippage limit: more than max price"); // slippage protection
    //计算这次购买的amount价值多少OHM
    uint256 value = treasury.tokenValue(address(info.principal), _amount);
    //判断买入的这些份额，协议会给他多少回报
    uint256 payout = payoutFor(value, _BID); // payout to bonder is computed

    // 确保债券有剩余容量【ensure there is remaining capacity for bond】
    if (info.capacityIsPayout) {
      // 校验该债券允许支出多少OHM【capacity in payout terms】
      require(info.capacity >= payout, "Bond concluded");
      info.capacity = info.capacity.sub(payout);
    } else {
      // 校验该债券允许买进多少资newBond产【capacity in principal terms】
      require(info.capacity >= _amount, "Bond concluded");
      info.capacity = info.capacity.sub(_amount);
    }

    require(payout >= 10000000, "Bond too small"); //必须大于（10000000/10**9=0.01） OHM【 must be > 0.01 OHM ( underflow protection )】
    require(payout <= maxPayout(_BID), "Bond too large"); // 必须小于债券允许消费的最大值【size protection because there is no slippage】

    //把用户买进的资产（LP）转给财政部合约   TODO 这里不用转用户的资产进来？
    info.principal.safeTransfer(address(treasury), _amount); // send payout to treasury
    //已售债务累加
    bonds[_BID].totalDebt = info.totalDebt.add(value); // increase total debt
    
    //计算可取回本金时间
    uint256 expiration = info.terms.vestingTerm.add(block.number);
    if (!info.terms.fixedTerm) {
      expiration = info.terms.expiration;
    }

    // user info stored with teller
    uint256 index = teller.newBond(_depositor, address(info.principal), _amount, payout, expiration, _feo);

    emit CreateBond(_BID, _amount, payout, expiration);

    return (payout, index);
  }

  /* ======== INTERNAL FUNCTIONS ======== */

  /**
   * @notice 待兑现债券份额衰减【reduce total debt】
   * @param _BID uint
   */
  function decayDebt(uint256 _BID) internal {
    bonds[_BID].totalDebt = bonds[_BID].totalDebt.sub(debtDecay(_BID));
    bonds[_BID].lastDecay = block.number;
  }

  /* ======== VIEW FUNCTIONS ======== */

  // BOND TYPE INFO

  /**
   * @notice 根据索引id查询某个债券的信息【returns data about a bond type】
   * @param _BID uint                   债券索引
   * @return principal_ address         支持质押的资产地址
   * @return calculator_ address        StandardBondingCalculator合约地址（债券计算合约）
   * @return totalDebt_ uint            当前的债务总额
   * @return lastBondCreatedAt_ uint    
   */
  function bondInfo(uint256 _BID)
    external
    view
    returns (
      address principal_,
      address calculator_,
      uint256 totalDebt_,
      uint256 lastBondCreatedAt_
    )
  {
    Bond memory info = bonds[_BID];
    principal_ = address(info.principal);
    calculator_ = address(info.calculator);
    totalDebt_ = info.totalDebt;
    lastBondCreatedAt_ = info.lastDecay;
  }

  /**
   * @notice 根据债券的索引获取其配置的周期信息【returns terms for a bond type】
   * @param _BID uint
   * @return controlVariable_ uint
   * @return vestingTerm_ uint
   * @return minimumPrice_ uint
   * @return maxPayout_ uint
   * @return maxDebt_ uint
   */
  function bondTerms(uint256 _BID)
    external
    view
    returns (
      uint256 controlVariable_,
      uint256 vestingTerm_,
      uint256 minimumPrice_,
      uint256 maxPayout_,
      uint256 maxDebt_
    )
  {
    Terms memory terms = bonds[_BID].terms;
    controlVariable_ = terms.controlVariable;
    vestingTerm_ = terms.vestingTerm;
    minimumPrice_ = terms.minimumPrice;
    maxPayout_ = terms.maxPayout;
    maxDebt_ = terms.maxDebt;
  }

  // PAYOUT

  /**
   * @notice 控制单笔购买债券的最大消费金额（合约购买债券单笔允许支出最大金额）【determine maximum bond size】
   * @param _BID uint
   * @return uint
   */
  function maxPayout(uint256 _BID) public view returns (uint256) {
    return treasury.baseSupply().mul(bonds[_BID].terms.maxPayout).div(100000);
  }

  /**
   * @notice 判断买入的这些份额，协议会给他多少回报【payout due for amount of treasury value】
   * @param _value uint
   * @param _BID uint
   * @return uint
   */
  function payoutFor(uint256 _value, uint256 _BID) public view returns (uint256) {
    return FixedPoint.fraction(_value, bondPrice(_BID)).decode112with18().div(1e16);
  }

  /**
   * @notice 指定购买金额和债券索引，判断能领取多少报酬(OHM)【payout due for amount of token】
   * @param _amount uint
   * @param _BID uint
   */
  function payoutForAmount(uint256 _amount, uint256 _BID) public view returns (uint256) {
    address principal = address(bonds[_BID].principal);
    //计算出购买的债券价值多少OHM,再判断买入的这些份额，协议会给他多少回报
    return payoutFor(treasury.tokenValue(principal, _amount), _BID);
  }

  // BOND PRICE

  /**
   * @notice 根据id获取债券的价格()【calculate current bond premium】
   * @param _BID uint
   * @return price_ uint
   */
  function bondPrice(uint256 _BID) public view returns (uint256 price_) {
    price_ = bonds[_BID].terms.controlVariable.mul(debtRatio(_BID)).add(1000000000).div(1e7);
    if (price_ < bonds[_BID].terms.minimumPrice) {
      price_ = bonds[_BID].terms.minimumPrice;
    }
  }

  /**
   * @notice 计算当前债券价格，如高于底部则移除底部 【calculate current bond price and remove floor if above】
   * @param _BID uint
   * @return price_ uint
   */
  function _bondPrice(uint256 _BID) internal returns (uint256 price_) {
    Bond memory info = bonds[_BID];
    price_ = info.terms.controlVariable.mul(debtRatio(_BID)).add(1000000000).div(1e7);
    if (price_ < info.terms.minimumPrice) {
      price_ = info.terms.minimumPrice;
    } else if (info.terms.minimumPrice != 0) {
      bonds[_BID].terms.minimumPrice = 0;
    }
  }

  /**
   * @notice 获取债券相对于DAI的价格【converts bond price to DAI value】
   * @param _BID uint
   * @return price_ uint
   */
  function bondPriceInUSD(uint256 _BID) public view returns (uint256 price_) {
    Bond memory bond = bonds[_BID];
    if (address(bond.calculator) != address(0)) {
      price_ = bondPrice(_BID).mul(bond.calculator.markdown(address(bond.principal))).div(100);
    } else {
      price_ = bondPrice(_BID).mul(10**IERC20Metadata(address(bond.principal)).decimals()).div(100);
    }
  }

  // DEBT

  /**
   * @notice 计算当前待兑现债券（已减去衰减但未领取部分）与OHM供应的比率【calculate current ratio of debt to OHM supply】
   * @param _BID uint           债券id
   * @return debtRatio_ uint    返回
   */
  function debtRatio(uint256 _BID) public view returns (uint256 debtRatio_) {
    //比例=当前未兑现的债券报酬/OHM总供应量
    debtRatio_ = FixedPoint.fraction(currentDebt(_BID).mul(1e9), treasury.baseSupply()).decode112with18().div(1e18); 
  }

  /**
   * @notice debt ratio in same terms for reserve or liquidity bonds
   * @return uint
   */
  function standardizedDebtRatio(uint256 _BID) public view returns (uint256) {
    Bond memory bond = bonds[_BID];
    if (address(bond.calculator) != address(0)) {
      return debtRatio(_BID).mul(bond.calculator.markdown(address(bond.principal))).div(1e9);
    } else {
      return debtRatio(_BID);
    }
  }

  /**
   * @notice 计算当前带兑现债务（不包括已衰减的）【calculate debt factoring in decay】
   * @param _BID uint
   * @return uint
   */
  function currentDebt(uint256 _BID) public view returns (uint256) {
    //待兑现债券总额（已减去衰减但未领取部分）=当前待兑现债券总额-已减去衰减但未领取份额
    return bonds[_BID].totalDebt.sub(debtDecay(_BID));
  }

  /**
   * @notice 根据债券Id,计算当前时间段已衰减的债务总额【amount to decay total debt by】
   * @param _BID uint
   * @return decay_ uint
   */
  function debtDecay(uint256 _BID) public view returns (uint256 decay_) {
    Bond memory bond = bonds[_BID];
    uint256 blocksSinceLast = block.number.sub(bond.lastDecay);//与上次衰减时的区块间隔
    //当前时间段衰减的债务=待兑现债务总额*区块间隔/债务授权区块个数
    decay_ = bond.totalDebt.mul(blocksSinceLast).div(bond.terms.vestingTerm);
    //衰减的债务不得大于待兑现债务总额
    if (decay_ > bond.totalDebt) {
      decay_ = bond.totalDebt;
    }
  }
}
