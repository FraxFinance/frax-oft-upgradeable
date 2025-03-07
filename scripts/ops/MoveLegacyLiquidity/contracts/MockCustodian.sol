pragma solidity ^0.8.22;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "scripts/BaseL0Script.sol";

contract MockCustodian is Ownable {
    
    uint32 public constant dstEid = 30101;
    address public immutable ethMsig;

    constructor(address _ethMsig) Ownable(msg.sender) {
        ethMsig = _ethMsig;
    }

    function send(address _oft) external onlyOwner {
        uint256 balance = IERC20(_oft).balanceOf(address(this));

        bytes memory options = OptionsBuilder.newOptions();
        SendParam memory sendParam = SendParam({
            dstEid: dstEid,
            to: bytes32(uint256(uint160(_addr))),
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


    function withdrawEth() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }
}