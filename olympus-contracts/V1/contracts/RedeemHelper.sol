// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.7.5;

interface IOwnable {
  function policy() external view returns (address);

  function renounceManagement() external;

  function pushManagement(address newOwner_) external;

  function pullManagement() external;
}

contract Ownable is IOwnable {
  address internal _owner;
  address internal _newOwner;

  event OwnershipPushed(
    address indexed previousOwner,
    address indexed newOwner
  );
  event OwnershipPulled(
    address indexed previousOwner,
    address indexed newOwner
  );

  constructor() {
    _owner = msg.sender;
    emit OwnershipPushed(address(0), _owner);
  }

  function policy() public view override returns (address) {
    return _owner;
  }

  modifier onlyPolicy() {
    require(_owner == msg.sender, "Ownable: caller is not the owner");
    _;
  }

  function renounceManagement() public virtual override onlyPolicy {
    emit OwnershipPushed(_owner, address(0));
    _owner = address(0);
  }

  function pushManagement(address newOwner_)
    public
    virtual
    override
    onlyPolicy
  {
    require(newOwner_ != address(0), "Ownable: new owner is the zero address");
    emit OwnershipPushed(_owner, newOwner_);
    _newOwner = newOwner_;
  }

  function pullManagement() public virtual override {
    require(msg.sender == _newOwner, "Ownable: must be new owner to pull");
    emit OwnershipPulled(_owner, _newOwner);
    _owner = _newOwner;
  }
}

interface IBond {
  function redeem(address _recipient, bool _stake) external returns (uint256);

  function pendingPayoutFor(address _depositor)
    external
    view
    returns (uint256 pendingPayout_);
}

/**
 * 债券收益提取工具
 */
contract RedeemHelper is Ownable {
  address[] public bonds;

  /**
   *  @notice 提取指定用户的所有债券收益(遍历所有债券，如果用户有购买这个债券，则提取)
   *  @param _recipient address    收益者地址
   *  @param _stake uint  收益是否质押到staking合约
   */
  function redeemAll(address _recipient, bool _stake) external {
    for (uint256 i = 0; i < bonds.length; i++) {
      if (bonds[i] != address(0)) {
        if (IBond(bonds[i]).pendingPayoutFor(_recipient) > 0) {
          IBond(bonds[i]).redeem(_recipient, _stake);
        }
      }
    }
  }

  /**
   *  @notice 新增债券地址
   *  @param _bond address    BondDepository类型合约地址
   */
  function addBondContract(address _bond) external onlyPolicy {
    require(_bond != address(0));
    bonds.push(_bond);
  }

  /**
   *  @notice 移除债券地址
   *  @param _index uint256   要删除的债券索引
   */
  function removeBondContract(uint256 _index) external onlyPolicy {
    bonds[_index] = address(0);
  }
}
