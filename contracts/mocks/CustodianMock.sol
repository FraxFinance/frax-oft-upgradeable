pragma solidity ^0.8.22;

import { OptionsBuilder } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oapp/libs/OptionsBuilder.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SendParam, MessagingFee, IOFT } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @dev used in conjunction with `scripts/ops/MoveLegacyLiquidity/1_DeployMockOFTs.s.sol`
contract CustodianMock is Ownable, Initializable{
    
    uint32 public constant dstEid = 30101; // Ethereum

    // Copied from L0Constants.sol
    address public constant ethFrxUsdLockbox = 0x566a6442A5A6e9895B9dCA97cC7879D632c6e4B0;
    address public constant ethSFrxUsdLockbox = 0x7311CEA93ccf5f4F7b789eE31eBA5D9B9290E126;
    address public constant ethFrxEthLockbox = 0x1c1649A38f4A3c5A0c4a24070f688C525AB7D6E6;
    address public constant ethSFrxEthLockbox = 0xbBc424e58ED38dd911309611ae2d7A23014Bd960;
    address public constant ethFxsLockbox = 0xC6F59a4fD50cAc677B51558489E03138Ac1784EC;

    receive() external payable {}

    constructor(address _initialOwner) {
        _transferOwnership(_initialOwner);
    }

    function send(
        address _mockFrxUsdOft,
        address _mockSfrxUsdOft,
        address _mockFrxEthOft,
        address _mockSfrxEthOft,
        address _mockFxsOft
    ) external payable onlyOwner initializer {
        require(
            _mockFrxUsdOft != address(0) &&
            _mockSfrxUsdOft != address(0) &&
            _mockFrxEthOft != address(0) &&
            _mockSfrxEthOft != address(0) &&
            _mockFxsOft != address(0),
            "CustodianMock: zero address"
        );

        _send(_mockFrxUsdOft, ethFrxUsdLockbox);
        _send(_mockSfrxUsdOft, ethSFrxUsdLockbox);
        _send(_mockFrxEthOft, ethFrxEthLockbox);
        _send(_mockSfrxEthOft, ethSFrxEthLockbox);
        _send(_mockFxsOft, ethFxsLockbox);

        // withdraw any remaining ETH
        payable(owner()).transfer(address(this).balance);
    }

    function _send(address _oft, address _to) internal {
        uint256 balance = IERC20(_oft).balanceOf(address(this));
        require(balance > 0, "CustodianMock: no balance");

        bytes memory options = OptionsBuilder.newOptions();
        SendParam memory sendParam = SendParam({
            dstEid: dstEid,
            to: bytes32(uint256(uint160(_to))),
            amountLD: balance,
            minAmountLD: balance,
            extraOptions: options,
            composeMsg: '',
            oftCmd: ''
        });
        MessagingFee memory fee = IOFT(_oft).quoteSend(sendParam, false);
        IOFT(_oft).send{value: fee.nativeFee}(
            sendParam,
            fee,
            payable(owner())
        );
    }
}