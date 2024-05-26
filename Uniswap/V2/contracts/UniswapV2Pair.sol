pragma solidity =0.5.16;

import "./interfaces/IUniswapV2Pair.sol";
import "./UniswapV2ERC20.sol";
import "./libraries/Math.sol";
import "./libraries/UQ112x112.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/IUniswapV2Callee.sol";

/**
 *  @notice 每个交易对都是一个UniswapV2Pair实例
 */
contract UniswapV2Pair is IUniswapV2Pair, UniswapV2ERC20 {
    using SafeMath for uint256;
    using UQ112x112 for uint224;

    //设置最小流动性
    uint256 public constant MINIMUM_LIQUIDITY = 10**3;
    //ERC20转账函数选择器
    bytes4 private constant SELECTOR =
        bytes4(keccak256(bytes("transfer(address,uint256)")));

    address public factory;
    address public token0;
    address public token1;

    //pair中token0当前储备金总额
    uint112 private reserve0; // uses single storage slot, accessible via getReserves
    //pair中token1当前储备金总额
    uint112 private reserve1; // uses single storage slot, accessible via getReserves
    //最新交易时的区块（创建）时间
    uint32 private blockTimestampLast; // uses single storage slot, accessible via getReserves
    //记录交易对中两种价格的累计值,价格预言用户可以自己存储这个两个值来提供价格信息。
    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    //记录某一时刻恒定乘积中积的值k，主要用于开发团队手续费计算
    uint256 public kLast; // reserve0 * reserve1, as of immediately after the most recent liquidity event

    uint256 private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, "UniswapV2: LOCKED");
        unlocked = 0;
        _;
        unlocked = 1;
    }

    /**
     *  @notice 获取pair中两个token当前各自的总储备金
     */
    function getReserves()
        public
        view
        returns (
            uint112 _reserve0,
            uint112 _reserve1,
            uint32 _blockTimestampLast
        )
    {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    /**
     *  @notice ERC20代码发送
     */
    function _safeTransfer(
        address token,
        address to,
        uint256 value
    ) private {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(SELECTOR, to, value)
        );
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "UniswapV2: TRANSFER_FAILED"
        );
    }

    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(
        address indexed sender,
        uint256 amount0,
        uint256 amount1,
        address indexed to
    );
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    /**
     *  @notice 构造函数，设计为在factory统一创建pair,因此直接认为sender是factory
     */
    constructor() public {
        factory = msg.sender;
    }

    /**
     *  @notice 工厂合约只在部署该pair时调用一次【called once by the factory at time of deployment】
     *  @param _token0 指定token0地址
     *  @param _token1 指定token1地址
     */
    function initialize(address _token0, address _token1) external {
        require(msg.sender == factory, "UniswapV2: FORBIDDEN"); // sufficient check
        token0 = _token0;
        token1 = _token1;
    }

    /**
     *  @notice 【更新储备，并在每个区块的第一次调用时，价格累加】update reserves and, on the first call per block, price accumulators
     *  @param balance0 变更份额0
     *  @param balance1 变更份额1
     */
    function _update(
        uint256 balance0,
        uint256 balance1,
        uint112 _reserve0,
        uint112 _reserve1
    ) private {
        //要求变更份额在uint112支持的最大值范围内
        require(
            balance0 <= uint112(-1) && balance1 <= uint112(-1),
            "UniswapV2: OVERFLOW"
        );
        //获取当前区块时间戳的unit32类型值
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        //计算当前区块时间戳与上次记录的区块时间戳之间的差值
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
        //如果时间戳差值大于0，并且两个token的份额大于0，则累加价格（这里目的是每个区块首条交易累加价格）
        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            // * never overflows, and + overflow is desired
            //累加token0的价格（即上一个区块的首条交易）（[价格*时间差]是为了增加价格操控难度）
            price0CumulativeLast +=
                uint256(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) *
                timeElapsed;
            //累加前一次交易token1的价格（即上一个区块的首条交易）
            price1CumulativeLast +=
                uint256(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) *
                timeElapsed;
        }
        //更新token0和token1的储备金额
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        //记录本次储备金变更的时间戳
        blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
    }

    // 如果收取费用，铸币流动性相当于根号(k)增长的1/6  【if fee is on, mint liquidity equivalent to 1/6th of the growth in sqrt(k)】
    function _mintFee(uint112 _reserve0, uint112 _reserve1)
        private
        returns (bool feeOn)
    {
        address feeTo = IUniswapV2Factory(factory).feeTo();
        feeOn = feeTo != address(0);
        //当前记录的最新K值
        uint256 _kLast = kLast; // gas savings
        if (feeOn) {
            if (_kLast != 0) {
                //计算两个份额的根号k
                uint256 rootK = Math.sqrt(uint256(_reserve0).mul(_reserve1));
                //计算当前记录的k的根号值
                uint256 rootKLast = Math.sqrt(_kLast);
                //要求传入的根号K大于原来记录中的根号K
                if (rootK > rootKLast) {
                    //lp总供应*新旧根号k的差
                    uint256 numerator = totalSupply.mul(rootK.sub(rootKLast));
                    //计算新根号K*5+旧根号K
                    uint256 denominator = rootK.mul(5).add(rootKLast);
                    //计算手续费
                    uint256 liquidity = numerator / denominator;
                    //铸造手续费
                    if (liquidity > 0) _mint(feeTo, liquidity);
                }
            }
        } else if (_kLast != 0) {
            kLast = 0;
        }
    }

    // this low-level function should be called from a contract which performs important safety checks
    //铸造Lp给指定地址
    function mint(address to) external lock returns (uint256 liquidity) {
        //获取pair中两个token当前各自的总储备金
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves(); // gas savings
        //获取合约当前拥有两个token的份额
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        //存入份额=当前份额-记录的储备金份额
        uint256 amount0 = balance0.sub(_reserve0);
        uint256 amount1 = balance1.sub(_reserve1);

        //如果收取费用，铸币流动性相当于根号(k)增长的1/6
        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint256 _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        if (_totalSupply == 0) {
            //首次添加的流动性未两个token的份额乘积开放再减流动性最低份额
            liquidity = Math.sqrt(amount0.mul(amount1)).sub(MINIMUM_LIQUIDITY);
            _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {
            //自己本次新增流动性/总流动性=自己本次存入token份额/pair中token储备金总份额
            //因此： 自己本次新增流动性=自己本次存入token份额*总流动性/pair中token储备金总份额
            liquidity = Math.min(
                amount0.mul(_totalSupply) / _reserve0,
                amount1.mul(_totalSupply) / _reserve1
            );
        }
        //给用户铸造新增的流动性份额
        require(liquidity > 0, "UniswapV2: INSUFFICIENT_LIQUIDITY_MINTED");
        _mint(to, liquidity);
        //更新pair中最新的储备金
        _update(balance0, balance1, _reserve0, _reserve1);
        //TODO ????为什么在有手续费时才重新计算k值
        if (feeOn) kLast = uint256(reserve0).mul(reserve1); // reserve0 and reserve1 are up-to-date
        emit Mint(msg.sender, amount0, amount1);
    }

    // this low-level function should be called from a contract which performs important safety checks
    //销毁自己的lp份额取回相应的两个token份额
    function burn(address to)
        external
        lock
        returns (uint256 amount0, uint256 amount1)
    {
        //获取pair中两个token当前记录的储备金份额
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves(); // gas savings
        address _token0 = token0; // gas savings
        address _token1 = token1; // gas savings
        //获取pair中两个token当前实际的份额
        uint256 balance0 = IERC20(_token0).balanceOf(address(this));
        uint256 balance1 = IERC20(_token1).balanceOf(address(this));
        //获取pair中当前的lp份额，这个份额就是要销毁的份额（需要用户在调用burn接口前，先将lp转到该合约）
        uint256 liquidity = balanceOf[address(this)];
        //扣取费用
        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint256 _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        //根据比例计算销毁的lp份额分别得到两个token的份额为多少
        amount0 = liquidity.mul(balance0) / _totalSupply; // using balances ensures pro-rata distribution
        amount1 = liquidity.mul(balance1) / _totalSupply; // using balances ensures pro-rata distribution
        require(
            amount0 > 0 && amount1 > 0,
            "UniswapV2: INSUFFICIENT_LIQUIDITY_BURNED"
        );
        //销毁lp份额
        _burn(address(this), liquidity);
        //分别将用户应得的两个token转给用户
        _safeTransfer(_token0, to, amount0);
        _safeTransfer(_token1, to, amount1);
        //获取当前pair中实际拥有的两个token份额
        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));
        //更新储备金的份额
        _update(balance0, balance1, _reserve0, _reserve1);
        //TODO ????为什么在有手续费时才重新计算k值
        if (feeOn) kLast = uint256(reserve0).mul(reserve1); // reserve0 and reserve1 are up-to-date
        emit Burn(msg.sender, amount0, amount1, to);
    }

    // this low-level function should be called from a contract which performs important safety checks
    //兑换token(转入其中一个token的份额，用户得到等价值的另一个token)
    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external lock {
        require(
            amount0Out > 0 || amount1Out > 0,
            "UniswapV2: INSUFFICIENT_OUTPUT_AMOUNT"
        );
        //获取pair中两个token当前的储备金份额
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves(); // gas savings
        require(
            amount0Out < _reserve0 && amount1Out < _reserve1,
            "UniswapV2: INSUFFICIENT_LIQUIDITY"
        );

        uint256 balance0;
        uint256 balance1;
        {
            // scope for _token{0,1}, avoids stack too deep errors
            address _token0 = token0;
            address _token1 = token1;
            require(to != _token0 && to != _token1, "UniswapV2: INVALID_TO");
            //将指定token份额转给用户
            if (amount0Out > 0) _safeTransfer(_token0, to, amount0Out); // optimistically transfer tokens
            if (amount1Out > 0) _safeTransfer(_token1, to, amount1Out); // optimistically transfer tokens
            //这个调用不知道是干嘛的
            if (data.length > 0)
                IUniswapV2Callee(to).uniswapV2Call(
                    msg.sender,
                    amount0Out,
                    amount1Out,
                    data
                );
            //获取转账过后pair剩余的两个token份额
            balance0 = IERC20(_token0).balanceOf(address(this));
            balance1 = IERC20(_token1).balanceOf(address(this));
        }

        //举例：用token0兑换token1,则本次交易中pair合约要先收到token0的转入份额，并且pair合约转出的token0份额amount0Out为0，
        //所以token的转入份额为： amount0Int = balance0-_reserve0 【注意，此时amount0Out=0】
        uint256 amount0In = balance0 > _reserve0 - amount0Out
            ? balance0 - (_reserve0 - amount0Out)
            : 0;
        uint256 amount1In = balance1 > _reserve1 - amount1Out
            ? balance1 - (_reserve1 - amount1Out)
            : 0;
        require(
            amount0In > 0 || amount1In > 0,
            "UniswapV2: INSUFFICIENT_INPUT_AMOUNT"
        );
        {
            // scope for reserve{0,1}Adjusted, avoids stack too deep errors
            //扣除手续费，验证转账后的余额满足 X*Y >= K的要求   TODO?????没懂
            //调整后的余额0 = 余额0 * 1000 - (amount0In * 3)
            uint256 balance0Adjusted = balance0.mul(1000).sub(amount0In.mul(3));
            uint256 balance1Adjusted = balance1.mul(1000).sub(amount1In.mul(3));
            //确认balance0Adjusted * balance1Adjusted >= 储备0 * 储备1 * 1000000
            require(
                balance0Adjusted.mul(balance1Adjusted) >=
                    uint256(_reserve0).mul(_reserve1).mul(1000**2),
                "UniswapV2: K"
            );
        }

        _update(balance0, balance1, _reserve0, _reserve1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    // force balances to match reserves
    //强制将合约多余的储备转给指定地址，前提是合约实际份额大于记录的储备金份额（任何人都可以调用该接口）
    function skim(address to) external lock {
        address _token0 = token0; // gas savings
        address _token1 = token1; // gas savings
        _safeTransfer(
            _token0,
            to,
            IERC20(_token0).balanceOf(address(this)).sub(reserve0)
        );
        _safeTransfer(
            _token1,
            to,
            IERC20(_token1).balanceOf(address(this)).sub(reserve1)
        );
    }

    // force reserves to match balances
    //与skim相反，强制保存的恒定乘积的资产数量为交易对合约中两种代币的实际余额
    function sync() external lock {
        _update(
            IERC20(token0).balanceOf(address(this)),
            IERC20(token1).balanceOf(address(this)),
            reserve0,
            reserve1
        );
    }
}
