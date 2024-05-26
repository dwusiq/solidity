// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "./library/SignUtils.sol";
import "./library/TransferHelper.sol";
// import "hardhat/console.sol";

contract MultiSignWallet {
    uint256 public currentNo = 1; //The current transaction number, each transaction is signed with this value
    uint256 public immutable permitNumMin; //The minimum number of signatures that need to be collected per transaction
    address[] public signers; //All signer
    uint256 public immutable chainId; //Current chain
    mapping(address => bool) public isSigner; //Record whether the user is a signer
    mapping(uint256 => mapping(address => bool)) isSignerPermitted; //Record whether the user agrees to a certain transfer record

    event SendToken(
        address to,
        address token,
        uint256 amount,
        uint256 currentNo
    );
    event Deposit(address indexed sender, uint256 amount, uint256 balance);

    constructor(address[] memory _signers, uint256 _permitNumMin) {
        require(_signers.length > 0, "Signer is require");
        require(_permitNumMin > 0, "PermitNumMin  is require");

        signers = _signers;
        chainId = block.chainid;
        permitNumMin = _permitNumMin;

        for (uint256 i = 0; i < signers.length; i++)
            isSigner[signers[i]] = true;
    }

    /**
     * @dev Use all signature strings to send the transaction
     * @param _token Address of sending token, if is AddressZero will send nativ(eg. eth)
     * @param _amount Amount of sending token
     * @param _to User address to receive tokens
     * @param _message Any string, can be empty
     * @param _signatures List of signature
     */
    function sendToken(
        address _token,
        uint256 _amount,
        address _to,
        string memory _message,
        bytes[] memory _signatures
    ) external {
        uint256 msgLength = _signatures.length;
        require(msgLength >= permitNumMin, "Signatures is not enough");
        require(_amount > 0, "Amount too low");
        require(address(0) != _to, "Not support zero address");

        //check all signature
        for (uint256 i = 0; i < msgLength; i++) {
            address signer = address(0);
            signer = getSigner(_token, _amount, _to, _message, _signatures[i]);
            require(isSigner[signer], "Invalid signature");
            require(!isSignerPermitted[currentNo][signer], "Duplicate signer");
            isSignerPermitted[currentNo][signer] = true;
        }

        if (address(0) == _token) {
            TransferHelper.safeTransferETH(_to, _amount);
        } else {
            TransferHelper.safeTransfer(_token, _to, _amount);
        }

        currentNo++;
        emit SendToken(_to, _token, _amount, currentNo);
    }

    /**
     * @dev Hash the transfer data
     * @param _token Address of sending token, if is AddressZero will send nativ(eg. eth)
     * @param _amount Amount of sending token
     * @param _to User address to receive tokens
     * @param _message User address to receive tokens
     */
    function getMessageHash(
        address _token,
        uint256 _amount,
        address _to,
        string memory _message
    ) public view returns (bytes32 _signature) {
        return
            keccak256(
                abi.encodePacked(
                    chainId,
                    _token,
                    _amount,
                    _to,
                    _message,
                    currentNo
                )
            );
    }



    /**
     * @dev Prefix the hash
     * @param _signature _signature
     */
    function getSigner(
        address _token,
        uint256 _amount,
        address _to,
        string memory _message,
        bytes memory _signature
    ) private view returns (address) {
        bytes32 msgHash = getMessageHash(_token, _amount, _to, _message);
        bytes32 ethSignedMessageHash = SignUtils.getEthSignedMessageHash(msgHash);
        return SignUtils.recoverSigner(ethSignedMessageHash, _signature);
    }

function recoverSignerr(bytes32 signedMsgHash,bytes memory _signature)public view returns (address) {
        return SignUtils.recoverSigner(signedMsgHash, _signature);
}

    receive() external payable {
        emit Deposit(msg.sender, msg.value, address(this).balance);
    }
}
