# `OlympusDao`合约描述

## 一、OHM简述
**原理：** OHM代币被其它加密货币（如I）支持，但不是一对一挂钩，在OHM的价格比DAI低时，合约会回购OHM销毁，让其价格提升到1。假如OHM价格高时，合约会供应更多的OHM出售，让价格回落到1（前提是有人拿DAI来买OHM）。因此协议允许OHM对DAI的价格>=1

**目的：**  OlympusDAO 希望 OHM可以成为一个尽管市场波动性高但仍有办法把持住购买力的货币

**用户参与形式：** 

* staking(质押)：当价格上涨会触发合约铸造新的OHM,而这些新铸造的OHM中，有很大一部分会分配给质押OHM的用户，作为质押OHM的收益。
* bonding(债券)：用户用合约指定的币种(或LP)来购买`OHM`,这样用户得到`OHM`,并且用户支付的资产将归属于合约。
* selling(出售)：用户出售自己手中的OHM获利。

## 二、合约理解
#### 用户与核心合约交互的资产流动方向
##### `staking`合约
> 质押`OHM`赚取分红

* `stake`（质押`OHM`）
  -  `sOHM.rebase()` -> `sOHM`的`_totalSupply`增加  ->  `_gonsPerFragment`减小  ->  每份`gon`折算的`sOHM`增多
  - `distributor.distribute()` -> 确定下次分红的块高 -> 给`staking`合约在内的地址铸造`OHM`,份额为`IERC20(OHM).totalSupply().mul(_rate).div(1000000)`，但是要依赖`Treasury`合约存在多余的储备金，否则报错。
  - 计算下次分红的`OHM`份额
  - 将用户的`OHM`份额转到当前合约 -> 累加该用户质押的`OHM`份额和待释放`gon`份额 -> 将本次质押`OHM`对应的`sOHM`份额转到`StakingWarmup`合约
* `claim`(提取质押的收益`sOHM`)
  - 判断最后一次质押时所在的周期是否已结束 -> 移除质押记录 -> `StakingWarmup.retrieve()` ->  从`StakingWarmup`将应得的`sOHM`转给收益地址。
* `forfeit`(放弃收益，直接提取自己的所有`OHM`)
  - 移除质押记录 -> `StakingWarmup.retrieve()` ->  从`StakingWarmup`将应得的`sOHM`转给`staking`合约。
  - 将用户质押的`OHM`返还给用户
* `unstake`(用`sOHM`兑换`OHM`)
  - 用户可以自行选择要不要触发`rebase()`
  - 从用户账户转`sOHM`到`staking`合约
  - 从`staking`合约将`sOHM`对应的`OHM`份额转给用户
  
##### `BondDepository`合约
> 以债券的形式用`Token`折扣价购买`OHM`

* `deposit`(折扣价购买`OHM`)
  - 分别计算：用于`rebase`分红份额、该购买者应付报酬份额、手续费份额
  - 将用户本次支付的`Token`转到`BondDepositroy`合约 -> 调用`Treasury.deposit()`
  - `Treasury.deposit()` -> 将调用者的`Token`转到`Treasury`合约 -> 给发送者铸造`OHM`(用于支付购买者的报酬和支付手续费) -> 储备金值累加
* `redeem`(用户的债券报酬线性释放，可以不定期收割，可以选择是否质押这些收益)
  - 计算到目前为止需要支付给用户的报酬(`OHM`) -> `BondDepository`转`OHM`给用户，或者帮用户质押到`staking`合约

##### `Treasury`国库合约
> 支持存入储备金得到`OHM`，支持有权限的用户销毁`OHM`得到储备金

* `deposit`(被授权的地址存入储备金赚取`OHM`)
  - 将调用者的`Token`转到`Treasury`合约 -> 给发送者铸造`OHM`(用于支付购买者的报酬和支付手续费) -> 储备金值累加
* `withdraw`(被授权的地址销毁`OHM`得到`DAI`)
  - 计算销毁的`OHM`份额 -> 销毁`OHM` -> 将储备金的`Token`转给用户

## 三、合约理解的关键点

* `sOHM`合约的关注点：
  - 协议内计算份额是用`gon`,但协议外从用户的角度都是取`sOHM`的份额（即：`sOHM`对外，gon对内）
  - `sOHM`份额=`gon`份额/`_gonsPerFragment`，其中`_gonsPerFragment`跟`_totalSupply`成反比，`_gonsPerFragment`表示每单位`sOHM`价值多少`gon`
  - 每次调用`rebase`函数都会执行`_gonsPerFragment = TOTAL_GONS.div(_totalSupply);`,由`balanceOf`接口得知，则用户持有相同`gon`的前提下，`_gonsPerFragment`越小，则`sOHM`值越大
  
* `distributor`合约的关注点（这个合约解决了分红`OHM`的来源）
  - 这个合约配置在每个周期(`epoch`)给`staking`合约铸造多少`OHM`，这些`OHM`份额就是`staker`的收益来源
  - `await deployedDistributor.addRecipient(stakingAddress, initialRewardRate)`就是配置每周期的分红总额
  - 每次`staking`合约触发`rebase`都会调用`IDistributor(distributor).distribute()`产出用于分红的`OHM`
  - 因此每个周期都会有新的`OHM`产生
  
* `BondDepository`合约：
  - 用户购买债券收获到的`OHM`份额=无风险价值/价格=支付的资产份额折算回`OHM`的份额/价格
  

## 四、环境部署关键配置
##### `staking`质押合约
* 构造函数
  - `_OHM`: `OHM`合约地址
  - `_sOHM`: `SOHM`合约地址
  - `_epochLength`: 每经过多少区块`rebase`一次，值跟`distributor`合约保持一致。
  - `_firstEpochNumber`: 首个`epoch`周期起始区块。
  - `_firstEpochBlock`：首个`epoch`周期结束区块。
* `setContract`(设置相关合约地址)
  - `_contract`:  合约类型 0-`distributor`合约  1-`StakingWarmup`合约（只能设置一次） 2-`locker`合约（只能设置一次）
  - `_address`: 合约地址
* `setWarmup`(设置质押热身期，默认0)
  - `_warmupPeriod`: 为参与者设置热身时间（需要超过这么多区块才能领取收益

##### `StakingDistributor`质押分配者合约
* 构造函数
  - `_treasury`: `Treasury`国库合约
  - `_ohm`: `OHM`合约
  - `_epochLength`: 每经过多少区块`rebase`一次，值跟`staking`合约保持一致。
  - `_nextEpochBlock`:  首个周期(`Epoch`)的结束区块
* `addRecipient`(添加接收者，每次`rebase`给这些地址分配`OHM`)
  - `_recipient`: 接收者地址(一定要添加`Staking`合约地址)
  - `_rewardRate`：  奖励比率是于每次的变基 (rebase) 时分配给每个质押者相对于总供应量的配置百分比 ,计算公式是`IERC20(OHM).totalSupply().mul(_rate).div(1000000)`

##### `BondDepository`债券合约(当前版本每种债券都要部署一个相应的合约)
* 构造函数
  - `_ohm`: `OHM`合约
  - `_principle`: 购买债券需要支付资产地址
  - `_treasury`:`Treasury`国库合约
  - `_DAO`:接收`DAO`手续费的地址
  - `_bondCalculator`:债券计算合约
* `initializeBondTerms`(初始化债券的发行周期信息) 
  - `_controlVariable`:`BCV`,价格控制变量,控制价格变化幅度，值越大价格变化越大。
  - `_vestingTerm`:用户购买债券需要锁定的期限（区块个数）
  - `_minimumPrice`:债券最低价格
  - `_maxPayout`:合约最大单笔债券支出
  - `_fee`:用户购买债券的手续费
  - `_maxDebt`: 合约当前被持有债券总额（用户购买债券支付的`Token`总价值`OHM`份额）
  - `_initialDebt`:初始化当前债券已售份额

##### `Treasury`国库合约
* `queue`:添加地址到变更授权的队列(调toggle前要先调这个接口添加地址，并且有等待期)
  - `_managing`:授权类型的
  - `_address`:授权地址
* `toggle`: （事先添加到queue，并且过了等待期后，可以调这个接口）检查队列，并且切换用户的授权状态。
  - `_managing`:授权类型的
  - `_address`:授权地址
  - `_calculator`: 给0地址就可以了

##### `OHM`合约
* `setVault`:设置金库合约
  - `vault_`:金库合约地址，只有这个地址允许调用`OHM`的`mint`函数
##### `SOHM`合约
> 与`OHM`可以1比1兑换，质押`OHM`可以得到`SOHM`

* `initialize`:初始化sOHM的参数
  - `stakingContract_`: `staking`合约地址
* `setIndex`: 设置起始的`index`,用户记录历史各次`rebase`的`index`和当前最新`index`对比，得出增长率。
  - `_INDEX`: 起始`indexs`

##### `StakingWarmup`热身期合约
> 用户质押`OHM`后，把`sOHM`转到该合约，等用户领取的时候再从这里转出去

* 构造函数
  - `_staking`: `Staking`合约地址
  - `_sOHM`:`SOHM`合约地址

##### `AlphaOHM`预售合约主币
> 预售期用户购买得到这个币，项目启动后可以到AlphaOhmMigration 1:1兑换OHM

* 构造函数：写死了`Token`名称和发行总量（实际生产可能要改这块逻辑）

##### `OlympusPresale`预售合约
> 项目方转入`AOHM`到该合约，白名单用户可以参与预售，支付代币得到`AOHM`

* `whiteListBuyers`: 增加预售用户白名单（实际生产可能要去掉这个功能）
  - `_buyers`: 用户地址列表
* `initialize`:初始化
  - `_addressToSendDai`: 用户参与预售的`dai`将转入这个地址
  - `_dai`: `dai`合约地址
  - `_aOHM`: `aohm`合约地址，支付`dai`将得到`aOHM`
  - `_salePrice`:  预售价格，`dai`/`aOHM`(每单位`aOHM`需要多少`dai`)，实际生产可能要增加接口更改
  - `_saleLength`: 预售周期长度（时间戳）---设置该值要根据出块时间确定

##### `StakingHelper`
> 单币质押工具,质押和直接提取`SOHM`

* 构造函数
  - `_staking`: `Staking`合约地址
  - `_OHM`: `OHM`合约地址

##### `RedeemHelper`
> 债券收益提取工具,批量收取用户的多个债券收益

* `addBondContract`:增加债券合约地址
  - `_bond`: `BondDepository`类型合约地址
* `removeBondContract`:移除债券地址
  - `_index`: 要删除的债券索引