# `OlympusDao`合约描述




## 一、公式



* 无风险价值 = (LP / Total LP) * 2sqrt(Constant Product) 

  * LP： 用户计划用多少LP份额来购买（花费的LP份额）
  * Total LP： LP当前总供应量
  * 2sqrt(Constant Product)  ： LP的K值的平方根 * 2

  - 无风险价值：RFV（Risk-free value），其中RFV=2sqrt(constantProduct)∗ (LP/totalLP)，通过常数乘积（x*y=k）、LP和LP代币总量比例，以及平方根来得出RFV的值。当x=y时，也就是OHM=DAI时，RFV是x+y的最小值。 
  - 简单的说：无风险价值就是用指定份额的LP能购买多少的OHM

* 执行价格 = RFV / 溢价 {溢价 ≥ 1}
* 溢价( *Premium* ) = 1 +（债务比率 * BCV）
* 债务比率（ *Debt Ratio* ） =   *Bonds Outstanding / OHM Supply*  = 当前用户持有总债券 / OHM总供应量


* 质押：您将把您的 OHM 发送到 Staking 合约并以 1:1 的比例接收 sOHM。sOHM可以被兑换成OHM。
* 变基（rebase）：切换到下一个周期，并结算上期分红。
* 价格控制变量(BCV)：Bond Control Variable，用于调整债券价格。
* 年化收益（APY）:  APY = Math.pow(1 + stakingRebase, 365 * 3) - 1;
  -  stakingRebase = 每期质押分红/当前被用户持有的sOHM;
  -  Math.pow(x,y): 用于返回第一个参数的第二个参数次方
  -  `365 * 3`的理解是一年365天，每天三次（8小时一次）
