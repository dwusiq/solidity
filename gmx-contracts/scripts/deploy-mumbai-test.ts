//执行：npx hardhat run scripts/deploy-mumbai-test.ts --network testnetMumbai

const util = require("ethereumjs-util");
const moment = require("moment");
const fs = require("fs");
const Web3 = require("web3");
const { ethers, artifacts } = require("hardhat");
const { sleep, deploy, waitTrans, upgradeDeploy, upgradeContract } = require("./contractDeploy.ts");
const { A_MINUTES_SECONDS, A_HOUR_SECONDS, A_DAY_SECONDS, A_WEEK_SECONDS, errorConfigs } = require("./constants.ts");
const { HashZero, AddressZero } = ethers.constants;

//用户及地址
let deployer: any;
let deployerAddress = "0x83B99A8f769048d3344eaC186e363Cd249B06891"; //不用填，会自动赋值  TODO 根据实际填写Owner地址
let govAddress = ""; //owner,最好是多签地址

//constant
const isLocalTest = false;
const ethDecimal = 18;
const usdtDecimal = 18;
const usdgDecimal = 18;
const ONE_DAY_BLOCK = A_DAY_SECONDS / 2; //每天区块数
const depositFee = 30; // 0.3%
const minExecutionFee = ethers.utils.parseEther("0.0001"); // 0.0001 ETH
const cooldownDuration = 15 * A_MINUTES_SECONDS; //添加流动行之后需要过多久才能赎回
const timeLockBuff = 5 * A_DAY_SECONDS;
const marginFeeBasisPoints = 10; //0.1%
const maxMarginFeeBasisPoints = 500; //5%
//vault相关常量
const liquidationFeeUsd = parseU(2); //添加流动性的手续费
const fundingRateFactor = 100; //非稳定币资金费率因子(用于计算资金费率)
const stableFundingRateFactor = 100; //稳定币资金费率因子(用于计算资金费率)
const fundingInterval = A_HOUR_SECONDS; //资金费率周期时长(秒)
//orderBook
const minPurchaseTokenAmountUsd = parseU(10); // min purchase token amount usd
//PositionRouter
const positionKeeper = deployerAddress; //TODO 生产根据实际情配置
const minBlockDelayKeeper = 0; //头寸数据过多久才能被keeper操作
const minTimeDelayPublic = 3 * A_MINUTES_SECONDS; //头寸数据过多久才能被任何用户操作
const maxTimeDelay = 30 * A_MINUTES_SECONDS; //头寸数据有效时长
//ShortsTrackerTimelock
const buffer = A_MINUTES_SECONDS; // 60 seconds
const updateDelay = 5 * A_MINUTES_SECONDS; // 300 seconds, 5 minutes
const maxAveragePriceChange = 20; // 0.2%
const shortsTrackerKeeperArray = [deployerAddress]; //short头寸的keeper
//PositionManager
const orderKeepers = [deployerAddress]; //头寸的keeper
const liquidators = [deployerAddress]; //清算用户
const partnerContracts = []; //

//合约地址
let deployedVault: any; //Vault
let vaultAddr = "0x19C986C2Ce01656268736A5741e7e2ab1e0Df187";
let deployedUSDG: any; //USDG(Token)
let usdgAddr = "0x5C76E3c60269dc1657ED1ba245A31f3564311a4d";
let deployedWETH: any; //WETH(Token)
let wethAddr = "0xd4589C11277d8d1A45D643D621CBF5e11e8b265f";
let deployedGLP: any; //GLP(Token)
let glpAddr = "0xE5A39C42EB1B383200f56b3Ff1BF65583fDFc772";
let deployedUSDT: any; //USDT(Token)
let usdtAddr = "0x0762ba210232bF587A1B8BCBEc6F4c22036b1F82";
let deployedGMX: any; //GMX(Token)
let gmxAddr = "0x53623846843ea2A0459C8da30C3d58a2dc4b4450";
let deployedVaultUtils: any; //VaultUtils
let vaultUtilsAddr = "0x0eB4D6F6Df76439330DE917ea4352d1eDF0A0E53";
let deployedRouter: any; //Router
let routerAddr = "0xFBd24EfF8EDdafc8FE86c3be4c8B626d7E79e123";
let deployedVaultPriceFeed: any; //VaultPriceFeed
let vaultPriceFeedAddr = "0x56a6192F25600568D67D2706bCF18B3C36aa89f6";
let deployedVaultErrorController: any; //VaultErrorController
let vaultErrorControllerAddr = "0x8D5A1752610C4199182693e88FdB90409f80C8D9";
let deployedShortsTracker: any; //ShortsTracker
let shortsTrackerAddr = "0x18d854c97ff9BA3B802cbA6916e201bb5d774605";
let deployedOrderBook: any; //OrderBook
let orderBookAddr = "0xa433070a8d54101B98FDe60a38b46eE1e990b8CC";
let deployedPositionUtils: any; //PositionUtils
let positionUtilsAddr = "0x796ada81039F7bCB56B9657A087878B39851D646";
let deployedPositionManager: any; //PositionManager
let positionManagerAddr = "0x7c698D643E532c35c0408C3850Db055d3a77959A";
let deployedPositionRouter: any; //PositionRouter
let positionRouterAddr = "0xf54ffB6fF13A1f46C995e59cc3A4eA847D17564c";
let deployedGlpManager: any; //GlpManager
let glpManagerAddr = "0x42AAeE8b0B766a49DdE4f9caC6ABe54350AEB7d0";
let deployedTimelock: any; //Timelock
let timelockAddr = "0xEe949EACdAFabBaecA7C27e4eD2cBf8581f734EA";
let deployedVaultReader: any; //VaultReader
let vaultReaderAddr = "0x0c484D68912673025dE39a0B0746e3C7Fb9A5002";
let deployedRewardRouterV2: any; //RewardRouterV2
let rewardRouterV2Addr = "0x9FB433d10e9416d2990afF475B61eE70A0a33e4e";
let deployedRewardReader: any; //RewardReader
let rewardReaderAddr = "0xc3aa3C409166A79CAe5cb21D4153F2BDb6A79F7D";
let deployedOrderBookReader: any; //OrderBookReader
let orderBookReaderAddr = "0xD073bB700fC9c31b4183543Dbe4843aBE8CbD8E8";
let deployedReader: any; //Reader
let readerAddr = "0x5489E0857f0EE6298Ab23cC8107Fa2102Dc76221";
let deployedShortsTrackerTimelock: any; //ShortsTrackerTimelock
let shortsTrackerTimelockAddr = "0xC48a1FF0001762fa730D315A3f6261e8cb706eb5";
let deployedPriceFeedEthUsd: any; //PriceFeeEthUSD
let priceFeedEthUsdAddr = "0x007A22900a3B98143368Bd5906f8E17e9867581b";

//部署合约0x0715A7794a1dc8e42615F059dD6e406A6594651A
async function deployContract() {
  [deployedVault, vaultAddr] = await deploy("Vault", vaultAddr, []);
  [deployedVaultUtils, vaultUtilsAddr] = await deploy("VaultUtils", vaultUtilsAddr, [vaultAddr]);
  [deployedUSDG, usdgAddr] = await deploy("USDG", usdgAddr, [vaultAddr]);
  [deployedUSDT, usdtAddr] = await deploy("UsdToken", usdtAddr, []);
  [deployedWETH, wethAddr] = await deploy("WETH", wethAddr, ["Wrapped Ether", "WETH", 18]);
  [deployedGLP, glpAddr] = await deploy("GLP", glpAddr, []);
  [deployedGMX, gmxAddr] = await deploy("GMX", gmxAddr, []);
  [deployedWETH, wethAddr] = await deploy("WETH", wethAddr, []);
  [deployedVaultReader, vaultReaderAddr] = await deploy("VaultReader", vaultReaderAddr, []);
  [deployedRouter, routerAddr] = await deploy("Router", routerAddr, [vaultAddr, usdgAddr, wethAddr]);
  [deployedRewardRouterV2, rewardRouterV2Addr] = await deploy("RewardRouterV2", rewardRouterV2Addr, []);
  [deployedRewardReader, rewardReaderAddr] = await deploy("RewardReader", rewardReaderAddr, []);
  [deployedVaultPriceFeed, vaultPriceFeedAddr] = await deploy("VaultPriceFeed", vaultPriceFeedAddr, []);
  [deployedShortsTracker, shortsTrackerAddr] = await deploy("ShortsTracker", shortsTrackerAddr, [vaultAddr]);
  [deployedOrderBook, orderBookAddr] = await deploy("OrderBook", orderBookAddr, []);
  [deployedOrderBookReader, orderBookReaderAddr] = await deploy("OrderBookReader", orderBookReaderAddr, []);
  [deployedReader, readerAddr] = await deploy("Reader", readerAddr, []);
  [deployedPositionUtils, positionUtilsAddr] = await deploy("PositionUtils", positionUtilsAddr, []);
  [deployedVaultErrorController, vaultErrorControllerAddr] = await deploy("VaultErrorController", vaultErrorControllerAddr, []);

  const shortsTrackerTimelockArgs = [deployerAddress, buffer, updateDelay, maxAveragePriceChange];
  [deployedShortsTrackerTimelock, shortsTrackerTimelockAddr] = await deploy("ShortsTrackerTimelock", shortsTrackerTimelockAddr, shortsTrackerTimelockArgs);

  const positionManagerArgs = [vaultAddr, routerAddr, shortsTrackerAddr, wethAddr, depositFee, orderBookAddr];
  [deployedPositionManager, positionManagerAddr] = await deploy("PositionManager", positionManagerAddr, positionManagerArgs, {
    libraries: {
      PositionUtils: positionUtilsAddr,
    },
  });

  const positionRouterArgs = [vaultAddr, routerAddr, wethAddr, shortsTrackerAddr, depositFee, minExecutionFee];
  [deployedPositionRouter, positionRouterAddr] = await deploy("PositionRouter", positionRouterAddr, positionRouterArgs, {
    libraries: {
      PositionUtils: positionUtilsAddr,
    },
  });

  const glpManagerArgs = [vaultAddr, usdgAddr, glpAddr, shortsTrackerAddr, cooldownDuration];
  [deployedGlpManager, glpManagerAddr] = await deploy("GlpManager", glpManagerAddr, glpManagerArgs);

  //TODO根据实际部署配置相关参数
  const tokenManager = deployerAddress;
  const mintReceiver = deployerAddress;
  const maxTokenSupply = ethers.utils.parseEther("100000000");
  const timeLockArgs = [
    deployerAddress,
    timeLockBuff,
    tokenManager,
    mintReceiver,
    glpManagerAddr,
    rewardRouterV2Addr,
    maxTokenSupply,
    marginFeeBasisPoints,
    maxMarginFeeBasisPoints,
  ];
  [deployedTimelock, timelockAddr] = await deploy("Timelock", timelockAddr, timeLockArgs);

  //priceFeed
  [deployedPriceFeedEthUsd, priceFeedEthUsdAddr] = await deploy("PriceFeed", priceFeedEthUsdAddr, []);
}

//主程序运行前配置
async function initBeforMainProcessLaunch() {
  console.log("initBeforMainProcessLaunch.start");
  // console.log("admin",await deployedTimelock.admin());
  // console.log("deployer",deployerAddress);
  // console.log("gov",await deployedVault.gov());

  //配置GLP  true-只能白名单转账
  await waitTrans(await deployedGLP.setInPrivateTransferMode(true), "GLP.setInPrivateTransferMode");

  //配置vault
  await waitTrans(
    await deployedVault.initialize(routerAddr, usdgAddr, vaultPriceFeedAddr, liquidationFeeUsd, fundingRateFactor, stableFundingRateFactor),
    "Vault.initialize"
  );
  await waitTrans(await deployedVault.setFundingRate(fundingInterval, fundingRateFactor, stableFundingRateFactor), "vault.setFundingRate");
  await waitTrans(await deployedVault.setVaultUtils(vaultUtilsAddr), "Vault.setVaultUtils");
  await waitTrans(await deployedVault.setErrorController(vaultErrorControllerAddr), "Vault.setErrorController");
  await waitTrans(await deployedVaultErrorController.setErrors(vaultAddr, errorConfigs), "ErrorController.setErrors");
  console.log("initBeforMainProcessLaunch.success");
}

//GlpManager
async function initSupportGlpManager() {
  console.log("initSupportGlpManager.start");
  //配置GlpManager  true-不允许增减流动性
  await waitTrans(await deployedGlpManager.setInPrivateMode(true), "GlpManager.setInPrivateMode");

  //其它合约配置glpManager
  await waitTrans(await deployedUSDG.addVault(glpManagerAddr), "USDG.addVault");
  await waitTrans(await deployedGLP.setMinter(glpManagerAddr, true), "GLP.setMinter");
  await waitTrans(await deployedVault.setInManagerMode(true), "vault.setInManagerMode");
  await waitTrans(await deployedVault.setManager(glpManagerAddr, true), "vault.setManager");
  console.log("initSupportGlpManager.success");
}

//OrderBook
async function initSupportOrderBook() {
  console.log("initSupportOrderBook.start");
  await waitTrans(
    await deployedOrderBook.initialize(routerAddr, vaultAddr, wethAddr, usdgAddr, minExecutionFee, minPurchaseTokenAmountUsd),
    "orderBook.initialize"
  );
  console.log("initSupportOrderBook.success");
}

//ShortsTrackerTimelock
async function initSupportShortsTrackerTimelock() {
  console.log("initSupportShortsTrackerTimelock.start");
  for (let keeper of shortsTrackerKeeperArray) {
    await waitTrans(await deployedShortsTrackerTimelock.setContractHandler(keeper, true), `shortsTrackerTimelock.setContractHandler ${keeper}`);
  }
  console.log("initSupportShortsTrackerTimelock.success");
}

//positionRouter
async function initSupportPositionRouter() {
  console.log("initSupportPositionRouter.start");
  // await waitTrans(await deployedShortsTrackerTimelock.signalSetHandler(positionRouterAddr, true), "shortsTrackerTimelock.signalSetHandler(positionRouter)");
  await waitTrans(await deployedRouter.addPlugin(positionRouterAddr), "router.addPlugin");
  await waitTrans(await deployedPositionRouter.setDelayValues(minBlockDelayKeeper, minTimeDelayPublic, maxTimeDelay), "positionRouter.setDelayValues");
  await waitTrans(await deployedTimelock.setContractHandler(positionRouterAddr, true), "timelock.setContractHandler(positionRouter)");
  await waitTrans(await deployedPositionRouter.setGov(await deployedVault.gov()), "positionRouter.setGov"); //TODO 多签合约,暂用deployer,因此不需要设置
  await waitTrans(await deployedPositionRouter.setAdmin(deployerAddress), "positionRouter.setAdmin");

  //配置keeper
  await waitTrans(await deployedPositionRouter.setPositionKeeper(positionKeeper, true), "positionRouter.keeper");

  console.log("initSupportPositionRouter.success");
}

//PositionManager
async function initSupportPositionManager() {
  console.log("initSupportPositionManager.start");

  // for (let orderKeeper of orderKeepers)
  //   await waitTrans(await deployedPositionManager.setOrderKeeper(orderKeeper,true), "deployedPositionManager.setOrderKeeper(orderKeeper)");

  // for (let liquidator of liquidators)
  //   await waitTrans(await deployedPositionManager.setLiquidator(liquidator, true), "deployedPositionManager.setLiquidator(liquidator)");

  // for (let partnerContract of partnerContracts)
  //   await waitTrans(await deployedPositionManager.setPartner(partnerContract, true), "deployedPositionManager.setPartner(partnerContract)");

  // await waitTrans(await deployedPositionManager.setShouldValidateIncreaseOrder(false), "deployedPositionManager.setShouldValidateIncreaseOrder(false)");
  // await waitTrans(await deployedTimelock.setContractHandler(deployedPositionManager.address, true), "timelock.setContractHandler");

  // await waitTrans(await deployedTimelock.setLiquidator(vaultAddr, deployedPositionManager.address, true),"timelock.setLiquidator");TODO等同vault.setLiquidator
  await waitTrans(await deployedVault.setLiquidator(deployedPositionManager.address, true), "timelock.setLiquidator");
  await waitTrans(await deployedShortsTracker.setHandler(deployedPositionManager.address, true), "shortsTracker.setContractHandler");
  await waitTrans(await deployedRouter.addPlugin(deployedPositionManager.address), "router.addPlugin(positionManager)");
  await waitTrans(await deployedPositionManager.setGov(await deployedVault.gov()), "deployedPositionManager.setGov");

  console.log("initSupportPositionManager.success");
}

//配置token
async function configTokenPriceFeed() {
  console.log("configTokenPriceFeed.start");

  //TODO 暂不开放AMM,后续有必要才开放AMM
  // await waitTrans(await deployedVaultPriceFeed.setIsAmmEnabled(false), "VaultPriceFeed.setIsAmmEnabled");

  const isStrictStable = false; //是否是稳定币
  // await waitTrans(await deployedVaultPriceFeed.setTokenConfig(wethAddr, priceFeedEthUsdAddr, 8, isStrictStable), "VaultPriceFeed.setTokenConfig.eth");
  // await waitTrans(await deployedVaultPriceFeed.setTokenConfig(AddressZero, priceFeedEthUsdAddr, 8, isStrictStable), "VaultPriceFeed.setTokenConfig.weth");
  console.log("configTokenPriceFeed.success");
}

//升级staking合约
async function deployedContractUpgrade() {
  // console.log("upgradeLpBondExternal");
  // await upgradeLpBondExternal(lpBondExternalAddress);
}

async function saveIdoUser() {
  // await updateIDOUser();
  // await mergedAllUser();
}

//需要临时调用的接口
async function tmpSet() {
  // await waitTrans(await deployedPositionRouter.setPositionKeeper(positionKeeper,true), "positionRouter.keeper");

  let data: any;
  data = await deployedPriceFeedEthUsd.latestAnswer();
  console.log("latestAnswer",data.toString());

  // //查询待执行的记录数
  // data = await deployedPositionRouter.getRequestQueueLengths();
  // console.log("getRequestQueueLengths", data.toString());
  // //执行用户的申请
  // const feeTo = deployer.address;
  // const endIndex = data[1];
  //  await waitTrans(await deployedPositionRouter.executeIncreasePositions(endIndex, feeTo), "execute position request");
  // // //根据key的index查询key
  // // let key = await deployedPositionRouter.increasePositionRequestKeys(8);
  // // //根据key查询详情
  // // data = await deployedPositionRouter.increasePositionRequests(key);
  // // console.log("data", data.toString());
  // // console.log("path", data.path);
  // // console.log("indexToken", data.indexToken.toString());

  // // //查询当前的头寸
  // // const account = "0x81fAD06f5B782bc61E93085126C4c73b113e433f";
  // // const collateralTokens = [AddressZero];
  // // const indexToken = ["0xd4589C11277d8d1A45D643D621CBF5e11e8b265f"];
  // // const isLong = [true];
  // // // data = await deployedReader.getPositions(vaultAddr, account, collateralTokens, indexToken, isLong);
  // // // console.log("reader.getPositions",data.toString());
  // // data = await deployedVault.getPosition(account, collateralTokens[0], indexToken[0], isLong[0]);
  // // console.log("getPosition",data.toString());
}

async function main() {
  [deployer] = await ethers.getSigners();
  deployerAddress = deployer.address;
  console.log(">>>>deployerAddress:", deployerAddress);

  //部署合约
  await deployContract();
  //初始化金库
  // await initBeforMainProcessLaunch();
  //配置GlpManager
  // await initSupportGlpManager();
  //配置订单簿
  // await initSupportOrderBook();
  //配置ShortsTrackerTimelock
  // await initSupportShortsTrackerTimelock();
  //配置PositionRouter
  // await initSupportPositionRouter();
  //配置PositionManager
  // await initSupportPositionManager();
  //配置token
  // await configTokenPriceFeed();
  // 需要临时调用的接口在这里写
  await tmpSet();
  console.log("deploy finish");
}

function parseU(value: number) {
  return ethers.utils.parseUnits(String(value), usdtDecimal);
}

function parseUSDG(value: number) {
  return ethers.utils.parseUnits(String(value), usdtDecimal);
}

main()
  .then(() => process.exit())
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

export {};
