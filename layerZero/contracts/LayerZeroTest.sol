// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import "./lzApp/NonblockingLzApp.sol";

/*
   link-test: https://layerzero.gitbook.io/docs/technical-reference/testnet/testnet-addresses
   link-main: https://layerzero.gitbook.io/docs/technical-reference/mainnet/supported-chain-ids
    LayerZero Arbitrum Goerli
      lzChainId:10143 lzEndpoint:0x6aB5Ae6822647046626e83ee6dB8187151E1d5ab
    LayerZero Goerli
      lzChainId:10121 lzEndpoint:0xbfD2135BFfbb0B5378b56643c2Df8a87552Bfa23
*/
contract LayerZeroTest is NonblockingLzApp {
    string public data = "empty message";
    uint16 destChainId;

    constructor(address _lzEndpoint) NonblockingLzApp(_lzEndpoint) {
        //根据当前端点合约地址确认要跨链的目标链ID(注意，这里并不是端点当前所在链的ID，而是目标链的ID,后续可改成mapping或参数传入等灵活方式)
        if (_lzEndpoint == 0x6aB5Ae6822647046626e83ee6dB8187151E1d5ab)
            destChainId = 10121;
        if (_lzEndpoint == 0xbfD2135BFfbb0B5378b56643c2Df8a87552Bfa23)
            destChainId = 10143;
    }

    /**
     * @notice 接收跨链消息(内部函数)
     * @param _srcChainId 发起方的链ID（从哪条链发起的跨链请求）
     * @param _srcAddress 发起方的合约地址
     * @param _nonce nonce值
     * @param _payload 跨链过来的消息载体(即跨链参数内容)
     */
    function _nonblockingLzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload
    ) internal override {
        data = abi.decode(_payload, (string));
    }

    /**
     * @notice 发送跨链请求
     * @param _message 发送的消息内容
     */
    function send(string memory _message) public payable {
        bytes memory payload = abi.encode(_message);
        _lzSend(
            destChainId, //目标链ID,不是传统的链ID,而是layerzer维护的一套链ID,如ethereum-101,Arbitrum-110
            payload, //需要发送的有效负载(_nonblockingLzReceive函数有入参接收该值)，并且通过abi.encode(_message)转化为字节数组
            payable(msg.sender), //退款地址，多余的费用退回到这个地址，payable(this)或payable(msg.sender)等
            address(0x0), //未来参数（将来持有zro的地址，将来可支付交易费用）
            bytes(""), //自定义功能的参数， 例如从目的中继器接收的空投原生币
            msg.value //原生币手续费数量（多余的回转回上面的退款地址---待确认）
        );
    }

    /**
     * @notice 绑定信任的合约地址（将当前地址与目标链的同功能合约地址关联起来）
     * @param _otherContract 目标链的合约地址(即要将跨链消息传递到该合约)
     */
    function trustAddress(address _otherContract) public onlyOwner {
        trustedRemoteLookup[destChainId] = abi.encodePacked(
            _otherContract,
            address(this)
        );
    }
}
