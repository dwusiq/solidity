// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * ERC20USDT合约。
 */
contract UsdToken is ERC20, Ownable {
    /// @notice 构造函数
    constructor() ERC20("test USDT", "tUSDT") {}

    /**
     * @notice 铸币
     * @param _to 接收者
     * @param _amount 铸造份额
     */
    function mint(address _to, uint256 _amount) external onlyOwner {
        _mint(_to, _amount);
    }
}
