# `OlympusDao`合约描述

## 一、OHM简述
**原理：** OHM代币被其它加密货币（如I）支持，但不是一对一挂钩，在OHM的价格比DAI低时，合约会回购OHM销毁，让其价格提升到1。假如OHM价格高时，合约会供应更多的OHM出售，让价格回落到1（前提是有人拿DAI来买OHM）。因此协议允许OHM对DAI的价格>=1

**目的：**  OlympusDAO 希望 OHM可以成为一个尽管市场波动性高但仍有办法把持住购买力的货币

**用户参与形式：** 
* staking(质押)：当价格上涨会触发合约铸造新的OHM,而这些新铸造的OHM中，有很大一部分会分配给质押OHM的用户，作为质押OHM的收益。
* bonding(债券)：用户用合约指定的币种(或LP)来购买`OHM`,这样用户得到`OHM`,并且用户支付的资产将归属于合约。
* selling(出售)：用户出售自己手中的OHM获利。


## 二、经济模型
* 质押（staking)`OHM`
  - 得到`sOHM`或`gOHM`。(可配置即时到账或锁仓)
  - 管理员可配置每次变基给那些地址额外分配一定比例的`OHM`--直接mint
  - 目前没搞懂质押分红的逻辑
* 用指定`LP`购买债券
  - 当债券的价格比市场价格低时（即使打折），用户可以选择用`LP`来购买债券，但`LP`已归合约所有,得到收益（V1收益线性释放，锁仓到期才可以一次领取）
  - 用户购买时可额外指定一个收益地址（这个收益地址会得到额外比例的`OHM`）-自己领
  - 用户购买债券的报酬是`sOHM`，到期后可自行提取


## 三、版本主要合约
|合约|描述|其它|
|-|-|-|
|`Treasury`|财务部合约<Br/>维护协议的所有资产<Br/>其它有权限合约可以向这个合约申请铸造`OHM`<Br/>有权的用户可以申请借还储备金或`OHM`|时间锁不知干什么用|
|`OlympusERC20`|`OHM`主币||
|`sOlympusERC20`|辅助币，质押(`staking`)`OHM`或购买债券(`bond`)获取|待了解`index`、`rebase`|
|`gOHM`|治理代币,质押(`staking`)`OHM`获取|待了解|
|`Staking`|用户可以质押`OHM`得到`sOHM`或`gOHM`<Br/>反过来也可以销毁`sOHM`或`gOHM`得到`OHM`<Br/>可以`sOHM`和`gOHM`相互兑换|rebase细节待了解|
|`StakingDistributor`|可以配置收益者的收益占总OHM供应的比例；<Br/>给staking合约铸币用户质押分红(在`staking`合约`rebase`时触发)||
|`BondDepository`|债券信息维护、债券信息查询、设置债券期限(只能一次)；<Br/>用户购买债券，购买的记录最终记录到`BondTeller`合约|购买债券逻辑有误|
|`BondTeller`|支持查询用户的债券报酬<Br/>支持领取报酬||
|`ERC20Permit`|用户线下签名`approve`函数，其它用户可以线上验证这个签名串，然后自行调用`approve`获得`owner`的`allowance`份额||
|`OlympusAccessControlled`|各权限控制的`modifier`||
|`OlympusAuthority`|角色权限管理,允许变更相关地址||



## 四、部署合约
###  依赖合约地址准备
* `DAI`
*  `sushiRouter`
*  `uniRouter`
*  `FRAX`
*  `LUSD`

### 部署步骤
* 部署`OlympusAuthority`
* 部署`OlympusTokenMigrator`,(依赖`OlympusAuthority`)
* 部署·`OlympusERC20Token`,(依赖`OlympusAuthority`)
* 部署`sOlympus`
* 部署`gOHM`,(依赖`OlympusTokenMigrator`、`sOlympus`)
* 部署`OlympusTreasury`,(依赖`OlympusERC20Token`、`OlympusAuthority`)
* 部署`OlympusStaking`,(依赖`OlympusERC20Token`、`sOlympus`、`gOHM`、`OlympusAuthority`)
* 部署`Distributor`,(依赖`OlympusTreasury`、`OlympusERC20Token`、`OlympusStaking`、`OlympusAuthority`)
* 部署`BondDepository`(依赖`OlympusERC20Token`、`OlympusTreasury`、`OlympusAuthority`)
* 部署`BondTeller`(依赖`BondDepository`、`OlympusStaking`、`OlympusTreasury`、`OlympusERC20Token`、`sOlympus`、`OlympusAuthority`)

## 五、主要合约的函数

#### `Treasury`：财政部合约(管理所有资产)
* 构造函数
* `deposit`: 被授权的地址可以存入资产并获得`OHM`的回报
* `withdraw`:被授权的地址销毁`OHM`换回储备中的其它`Token`
* `manage`:被授权的地址允许提取`Token`（不会销毁`OHM`）（目前只有升级合约调用）
* `mint`:被授权的地址允许`OHM`给指定用户
* `incurDebt`:被授权的地址可以借用储备金
* `repayDebtWithReserve`:授权用户偿还之前的借款（不是`OHM`,而是其它`Token`）
* `repayDebtWithOHM`:授权用户偿还之前的OHM借款
* `auditReserves`:重新盘点当前合约储备的所有`Token`的总价值
* `setDebtLimit`:设置某个地址允许的最大债务值
* `enable`:给指定地址设置某个权限
* `disable`:取消某个地址某个权限
* `indexInRegistry`:判断指定状态中是否包含某个地址
* `queueTimelock`:`?`
* `execute`:`?`
* `nullify`:取消指定index的时间锁
* `disableTimelock`:取消所有的时间锁
* `initialize`:初始化
* `excessReserves`:`?`
* `tokenValue`:指定`Token`地址和`amount` 估算价值多少的`OHM`
* `baseSupply`:在任何需要查询`OHM`供应的时候使用这个

#### `OlympusERC20`：主币
* 构造函数
* `ERC20`相关接口
* `ERC20Permit`相关接口（线下授权转移gas费）
* `mint`: 拥有`Vault`角色的地址可以mint
* `burn`:销毁`OHM`
* `burnFrom`: 从指定地址销毁（需要得到授权）

#### `sOlympusERC20`：辅助代币
* 构造函数
* `setIndex`:初始化`INDEX`, 只能合约初始化者调用，而且只能调用一次
* `setgOHM`:设置`gOHM`地址
* `initialize`:初始化`stak`和`treasury`合约地址, 只能合约初始化者调用，而且只能调用一次
* `rebase`:  细节待调查
* `transfer`: 发送自己的份额给其它地址
* `transferFrom`:从指定地址给别人发送份额
* `approve`:授权额度
* `increaseAllowance`:降低授权额度
* `decreaseAllowance`:增加授权额度
* `changeDebt`: 变更（增加或减少）指定地址当前欠款份额
* `balanceOf`: 查询某个地址的份额
* `gonsForBalance`: 计算`gons`的份额折算回`sOHM`份额(`gons`是)
* `balanceForGons`:计算`sOHM`的份额这算会`gons`的份额
* `toG`:计算`sOHM`折算回`gOHM`
* `fromG`:计算`gOHM`的份额折算回`sOHM`有多少
* `circulatingSupply`: 获取当前sOHM的流动份额（流动资金=总sOHM供应量-staking合约的sOHM总份额+gOHM总流动性折算OHM的总价值+质押合约中处于质押热身阶段的OHM）？？
* `index`: 根据`INDEX`查询
* `allowance`: 查询用户授权份额

#### `Staking`：质押合约
* 构造函数
* `stake`: 质押`OHM`,得到`sOHM`或`gOHM`。(根据配置可有即时到账或锁仓)
* `claim`:锁仓的份额到期后，可以提取自己的份额（`sOHM`或`gOHM`）
* `forfeit`:在锁仓期间可以直接提取自己质押的`OHM`没有收益
* `toggleLock`: 切换当前自己锁仓的`OHM`的锁状态（影响提取收益的用户地址） 
* `unstake`:用`sOHM`或`gOHM`赎回指定份额的`OHM`
* `wrap`:将sOHM兑换成gOHM
* `unwrap`:将gOHM的份额兑换回sOHM的
* `rebase`:判断当前epoch是否已结束，如果epoch已结束，触发rebase
* `index`:获取`sOHM`的`index`
* `supplyInWarmup`: 当前锁仓中总价值多少`sOHM`
* `secondsToNextEpoch`:还有多久到下一轮纪元（即本轮纪元还有多久结束）
* `setDistributor`: 变更`StakingDistributor`合约地址
* `setWarmupLength`:为新参与者设置热身时间，从存入到取出之间的时间如果不超过该值，则只能取回本金而没有受益

#### `StakingDistributor`：收益分配合约
* 构造函数
* `distribute`: 按各自比例分配分红给相关受益者（直接mint）,然后触发下一次收益比例变更。（受益者和比例有接口配置）
* `retrieveBounty`: 给staking合约铸币，用于给质押者的分红分红
* `adjust`: 调整收集者的分红收益率（需要预先调setAdjustment接口配置）
* `nextRewardAt`: 查看指定比率的下一个奖励金额是多少
* `nextRewardFor`:查看指定地址的下一个奖励金额是多少
* `setBounty`:设置每次给`OHM`的质押者分配的总分红
* `addRecipient`: 增加受益者和收益比例
* `removeRecipient`: 将用户从分红用户列表中移除
* `setAdjustment`: 调整用户的分红比率的下次变更参数（在distribute分配分红后，会按这里设置的ajust参数调整下一次分红比率）

#### `BondDepository`：债券合约
* `addBond`: 新增一个平台支持的债券类型
* `setTerms`:设置债券的售卖期信息，如：最大单笔销售量、价格缩放变量等
* `deprecateBond`: 禁用现有债券
* `setTeller`: 设置`teller`合约地址
* `deposit`: 购买债券,要锁仓一段时间才能提取报酬
* `decayDebt`: 待兑现债券份额衰减
* `bondInfo`: 根据债券索引查询债券信息，如支持资产地址、当前债券总额
* `bondTerms`:根据债券的索引获取其配置的周期信息，如：价格变量、最大单笔售额
* `maxPayout`: 控制单笔购买债券的最大消费金额（合约购买债券单笔允许支出最大金额）
* `payoutFor`:判断买入的这些份额，协议会给他多少回报
* `payoutForAmount`:指定购买金额和债券索引，判断能领取多少报酬(OHM)
* `bondPrice`:根据id获取债券的价格
* `bondPriceInUSD`:获取债券相对于DAI的价格
* `debtRatio`:计算当前待兑现债券（已减去衰减但未领取部分）与OHM供应的比率
* `standardizedDebtRatio`:
* `currentDebt`:计算当前带兑现债务（不包括已衰减的）
* `debtDecay`: 根据债券Id,计算当前时间段已衰减的债务总额

#### `BondTeller`：债券出纳员合约（查询和领取用户的债券收益）
* 构造函数
* `newBond`: 等级用户持有债券的信息（每次购买都追加到数组）
* `redeemAll`:提取指定地址的所有债券报酬
* `redeem`: 根据用户地址和索引支付债券报酬给用户（sOHM）
* `getReward`:领取自己的奖励（OHM）
* `setFEReward`:设置奖励的比值（用户购买债券时会传入收益地址，将按用户的报酬乘于这个比值，给收益地址额外分配奖励）
* `updateIndexesFor`:更新用户购买的债券的索引列表（只保留未领取债券报酬的索引）
* `pendingFor`:根据用户地址和债券索引查询待兑现的债券报酬（OHM）
* `pendingForIndexes`:根据用户地址和债券索引数组查询带发放的奖励总数（OHM）
* `totalPendingFor`:根据用户地址查询该用户的所有购买的债券中待发放的奖励总数（OHM）
* `percentVestedFor`:？？？

#### `OlympusAuthority`：角色权限代币
角色包括：
* `governor`:总理事
* `guardian`:监护者
* `policy`:决策者
* `vault`:金库


#### `gOHM`：治理代币
> 未细看


## 六、合约理解的关键点

* `sOHM`合约的关注点：
  - 协议内计算份额是用`gon`,但协议外从用户的角度都是取`sOHM`的份额（即：`sOHM`对外，gon对内）
  - `sOHM`份额=`gon`份额/`_gonsPerFragment`，其中`_gonsPerFragment`跟`_totalSupply`成反比，`_gonsPerFragment`表示每单位`sOHM`价值多少`gon`
  - 每次调用`rebase`函数都会执行`_gonsPerFragment = TOTAL_GONS.div(_totalSupply);`,由`balanceOf`接口得知，则用户持有相同`gon`的前提下，`_gonsPerFragment`越小，则`sOHM`值越大
* `distributor`合约的关注点（这个合约解决了分红`OHM`的来源）
  
  - 这个合约配置在每个周期(`epoch`)给`staking`合约铸造多少`OHM`，这些`OHM`份额就是`staker`的收益来源
  
  - `await deployedDistributor.addRecipient(stakingAddress, initialRewardRate)`就是配置每周期的分红总额
  
  - 每次`staking`合约触发`rebase`都会调用`IDistributor(distributor).distribute()`产出用于分红的`OHM`
  
  - 因此每个周期都会有新的`OHM`产生
  
    


## 七、其它

* V2与V1比较：
  - V2的BondDepository合约用数组实现同时支持多个不同的资产购买债券，而V1每种支持的资产都要新建一个同类型的合约 
  - 关于购买债券的收益：V1收益线性释放，V2锁仓到期才可以一次领取。V1可以直接将收益staking赚取sOHM,V2则直接直接提取收益。
  
* 执行价格 = RFV / 溢价 {溢价 ≥ 1}
* 溢价 = 1 +（债务比率 * BCV）
* 债务比率 = 未偿债券 / OHM 供应
* 无风险价值 = (LP / Total LP) * 2sqrt(Constant Product) 
  - 无风险价值：Risk-Free Value


* 质押：您将把您的 OHM 发送到 Staking 合约并以 1:1 的比例接收 sOHM。sOHM可以被兑换成OHM。
* 变基（rebase）：切换到新的纪元

*   BCV：Bond Control Variable