// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import "./lzApp/NonblockingLzApp.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/*
   link-test: https://layerzero.gitbook.io/docs/technical-reference/testnet/testnet-addresses
   link-main: https://layerzero.gitbook.io/docs/technical-reference/mainnet/supported-chain-ids
    LayerZero Arbitrum Goerli
      lzChainId:10143 lzEndpoint:0x6aB5Ae6822647046626e83ee6dB8187151E1d5ab
    LayerZero Goerli
      lzChainId:10121 lzEndpoint:0xbfD2135BFfbb0B5378b56643c2Df8a87552Bfa23
*/

contract LayerZeroTestCoin is NonblockingLzApp, ERC20 {
    uint16 destChainId;

    constructor(
        address _lzEndpoint
    ) NonblockingLzApp(_lzEndpoint) ERC20("Test Coin", "tCoin") {
        //根据当前端点合约地址确认要跨链的目标链ID(注意，这里并不是端点当前所在链的ID，而是目标链的ID,后续可改成mapping或参数传入等灵活方式)
        if (_lzEndpoint == 0x6aB5Ae6822647046626e83ee6dB8187151E1d5ab)
            destChainId = 10121;
        if (_lzEndpoint == 0xbfD2135BFfbb0B5378b56643c2Df8a87552Bfa23)
            destChainId = 10143;
        _mint(msg.sender, 1000000 * 10 ** decimals());
    }

    function _nonblockingLzReceive(
        uint16,
        bytes memory,
        uint64,
        bytes memory _payload
    ) internal override {
        (address toAddress, uint amount) = abi.decode(
            _payload,
            (address, uint)
        );
        _mint(toAddress, amount);
    }

    function bridge(uint _amount) public payable {
        _burn(msg.sender, _amount);
        bytes memory payload = abi.encode(msg.sender, _amount);
        _lzSend(
            destChainId,
            payload,
            payable(msg.sender),
            address(0x0),
            bytes(""),
            msg.value
        );
    }

    function trustAddress(address _otherContract) public onlyOwner {
        trustedRemoteLookup[destChainId] = abi.encodePacked(
            _otherContract,
            address(this)
        );
    }
}
