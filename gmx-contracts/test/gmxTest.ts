const util = require("ethereumjs-util");
const moment = require("moment");
const fs = require("fs");
const Web3 = require("web3");
const { ethers, artifacts } = require("hardhat");
const { sleep, deploy, waitTrans, upgradeDeploy, upgradeContract, openLocalTest } = require("../scripts/contractDeploy.ts");
const { A_MINUTES_SECONDS, A_HOUR_SECONDS, A_DAY_SECONDS, A_WEEK_SECONDS, errorConfigs } = require("../scripts/constants.ts");
const { HashZero, AddressZero } = ethers.constants;

//用户及地址
let deployer: any;
let deployerAddress = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"; //不用填，会自动赋值  TODO 根据实际填写Owner地址
let govAddress = ""; //owner,最好是多签地址

//constant
const isLocalTest = true;
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
let vaultAddr = "";
let deployedUSDG: any; //USDG(Token)
let usdgAddr = "";
let deployedWETH: any; //WETH(Token)
let wethAddr = "";
let deployedGLP: any; //GLP(Token)
let glpAddr = "";
let deployedUSDT: any; //USDT(Token)
let usdtAddr = "";
let deployedGMX: any; //GMX(Token)
let gmxAddr = "";
let deployedVaultUtils: any; //VaultUtils
let vaultUtilsAddr = "";
let deployedRouter: any; //Router
let routerAddr = "";
let deployedVaultPriceFeed: any; //VaultPriceFeed
let vaultPriceFeedAddr = "";
let deployedVaultErrorController: any; //VaultErrorController
let vaultErrorControllerAddr = "";
let deployedShortsTracker: any; //ShortsTracker
let shortsTrackerAddr = "";
let deployedOrderBook: any; //OrderBook
let orderBookAddr = "";
let deployedPositionUtils: any; //PositionUtils
let positionUtilsAddr = "";
let deployedPositionManager: any; //PositionManager
let positionManagerAddr = "";
let deployedPositionRouter: any; //PositionRouter
let positionRouterAddr = "";
let deployedGlpManager: any; //GlpManager
let glpManagerAddr = "";
let deployedTimelock: any; //Timelock
let timelockAddr = "";
let deployedVaultReader: any; //VaultReader
let vaultReaderAddr = "";
let deployedRewardRouterV2: any; //RewardRouterV2
let rewardRouterV2Addr = "";
let deployedRewardReader: any; //RewardReader
let rewardReaderAddr = "";
let deployedOrderBookReader: any; //OrderBookReader
let orderBookReaderAddr = "";
let deployedReader: any; //Reader
let readerAddr = "";
let deployedShortsTrackerTimelock: any; //ShortsTrackerTimelock
let shortsTrackerTimelockAddr = "";
let deployedPriceFeedEthUsd: any; //PriceFeeEthUSD
let priceFeedEthUsdAddr = "";

let user1: any;
describe("===========================tifo test===========================", function () {
  beforeEach(async function () {
    [deployer, user1] = await ethers.getSigners();
    console.log("deployer", deployer.address);

    //开启测试环境，即在部署合约之后不会睡眠5秒
    if (isLocalTest) {
      await openLocalTest();
    }
  });

  //部署合约
  it("deploy contract test", async function () {
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
  });

  //参数初始化
  it("initBeforMainProcessLaunch.test", async function () {
    console.log("initBeforMainProcessLaunch.start");
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
  });

  //参数初始化
  it("initSupportGlpManager.test", async function () {
    console.log("initSupportGlpManager.start");
    //配置GlpManager  true-不允许增减流动性
    await waitTrans(await deployedGlpManager.setInPrivateMode(true), "GlpManager.setInPrivateMode");

    //其它合约配置glpManager
    await waitTrans(await deployedUSDG.addVault(glpManagerAddr), "USDG.addVault");
    await waitTrans(await deployedGLP.setMinter(glpManagerAddr, true), "GLP.setMinter");
    await waitTrans(await deployedVault.setInManagerMode(true), "vault.setInManagerMode");
    await waitTrans(await deployedVault.setManager(glpManagerAddr, true), "vault.setManager");
    console.log("initSupportGlpManager.success");
  });

  //参数初始化
  it("initSupportOrderBook.test", async function () {
    console.log("initSupportOrderBook.start");
    await waitTrans(
      await deployedOrderBook.initialize(routerAddr, vaultAddr, wethAddr, usdgAddr, minExecutionFee, minPurchaseTokenAmountUsd),
      "orderBook.initialize"
    );
    console.log("initSupportOrderBook.success");
  });

  //参数初始化
  it("initSupportShortsTrackerTimelock.test", async function () {
    console.log("initSupportShortsTrackerTimelock.start");
    for (let keeper of shortsTrackerKeeperArray) {
      await waitTrans(await deployedShortsTrackerTimelock.setContractHandler(keeper, true), `shortsTrackerTimelock.setContractHandler ${keeper}`);
    }
    console.log("initSupportShortsTrackerTimelock.success");
  });

  //参数初始化
  it("initSupportPositionRouter.test", async function () {
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
  });

  //参数初始化
  it("initSupportPositionManager.test", async function () {
    console.log("initSupportPositionManager.start");

    for (let orderKeeper of orderKeepers)
      await waitTrans(await deployedPositionManager.setOrderKeeper(orderKeeper, true), "deployedPositionManager.setOrderKeeper(orderKeeper)");

    for (let liquidator of liquidators)
      await waitTrans(await deployedPositionManager.setLiquidator(liquidator, true), "deployedPositionManager.setLiquidator(liquidator)");

    for (let partnerContract of partnerContracts)
      await waitTrans(await deployedPositionManager.setPartner(partnerContract, true), "deployedPositionManager.setPartner(partnerContract)");

    await waitTrans(await deployedPositionManager.setShouldValidateIncreaseOrder(false), "deployedPositionManager.setShouldValidateIncreaseOrder(false)");
    await waitTrans(await deployedTimelock.setContractHandler(deployedPositionManager.address, true), "timelock.setContractHandler");

    await waitTrans(await deployedVault.setLiquidator(deployedPositionManager.address, true), "timelock.setLiquidator");
    await waitTrans(await deployedShortsTracker.setHandler(deployedPositionManager.address, true), "shortsTracker.setContractHandler");
    await waitTrans(await deployedRouter.addPlugin(deployedPositionManager.address), "router.addPlugin(positionManager)");
    await waitTrans(await deployedPositionManager.setGov(await deployedVault.gov()), "deployedPositionManager.setGov");

    console.log("initSupportPositionManager.success");
  });

  //参数初始化
  it("configTokenPriceFeed.test", async function () {
    console.log("initSupportPositionManager.start");

    //TODO 暂不开放AMM,后续有必要才开放AMM
    // await waitTrans(await deployedVaultPriceFeed.setIsAmmEnabled(false), "VaultPriceFeed.setIsAmmEnabled");

    const isStrictStable = false; //是否是稳定币
    await waitTrans(await deployedVaultPriceFeed.setTokenConfig(wethAddr, priceFeedEthUsdAddr, 8, isStrictStable), "VaultPriceFeed.setTokenConfig.eth");
    await waitTrans(await deployedVaultPriceFeed.setTokenConfig(AddressZero, priceFeedEthUsdAddr, 8, isStrictStable), "VaultPriceFeed.setTokenConfig.weth");

    console.log("initSupportPositionManager.success");
  });

  //喂价
  it("setLatestAnswer.test", async function () {
    await waitTrans(await deployedPriceFeedEthUsd.setLatestAnswer("2936309000000"), "riceFeed.setLatestAnswer");
  });

  //申请买入看多的订单
  it("createIncreasePosition.test", async function () {
    //查询价格
    const lastAnswer = await deployedPriceFeedEthUsd.latestAnswer();
    //查询执行手续费
    const executeFee = await deployedPositionRouter.minExecutionFee();
    console.log("executeFee", executeFee.toString());

    //下单
    const path = [wethAddr];
    const indexToken = wethAddr;
    const minOut = 0;
    const sizeDelta = ethers.utils.parseUnits("58722952", 26);
    const isLong = true;
    const acceptablePrice = lastAnswer;
    const executionFee = executeFee;
    const referralCode = "0x0000000000000000000000000000000000000000000000000000000000000000";
    const callbackTarget = AddressZero;

    await waitTrans(
      await deployedPositionRouter
        .connect(user1)
        .createIncreasePositionETH(path, indexToken, minOut, sizeDelta, isLong, acceptablePrice, executionFee, referralCode, callbackTarget),
      "PositionRouter.createIncreasePositionETH"
    );
  });

  //执行看多的衍生品订单
  it("createIncreasePosition.test", async function () {
    const requestQueueLengths = await deployedPositionRouter.getRequestQueueLengths();
    console.log("getRequestQueueLengths", requestQueueLengths.toString());
    
  });
});

function parseU(value: number) {
  return ethers.utils.parseUnits(String(value), usdtDecimal);
}
