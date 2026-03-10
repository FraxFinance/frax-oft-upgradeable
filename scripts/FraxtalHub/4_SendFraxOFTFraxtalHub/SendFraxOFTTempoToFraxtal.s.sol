// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "./SendFraxOFTFraxtalHub.sol";
import { TempoAltTokenBase } from "contracts/base/TempoAltTokenBase.sol";
import { StdPrecompiles } from "tempo-std/StdPrecompiles.sol";
import { StdTokens } from "tempo-std/StdTokens.sol";

// forge script scripts/FraxtalHub/4_SendFraxOFTFraxtalHub/SendFraxOFTTempoToFraxtal.s.sol --rpc-url $TEMPO_RPC_URL --broadcast

contract SendFraxOFTTempoToFraxtal is SendFraxOFTFraxtalHub {
    constructor() {
        wfraxOft = 0x00000000E9CE0f293D1Ce552768b187eBA8a56D4;
        sfrxUsdOft = 0x00000000fD8C4B8A413A06821456801295921a71;
        sfrxEthOft = 0x00000000883279097A49dB1f2af954EAd0C77E3c;
        frxUsdOft = 0x00000000D61733e7A393A10A5B48c311AbE8f1E5;
        frxEthOft = 0x000000008c3930dCA540bB9B3A5D0ee78FcA9A4c;
        fpiOft = 0x00000000bC4aEF4bA6363a437455Cb1af19e2aEb;

        srcEid = 30410;
        dstEid = 30255;
        amount = 0.0001 ether;
        senderWallet = 0x741F0d8Bde14140f62107FC60A0EE122B37D4630;
        recipientWallet = 0x741F0d8Bde14140f62107FC60A0EE122B37D4630;
    }

    /// @dev Override run() because Tempo OFTs use ERC20 for gas (no msg.value).
    ///      There is no FraxOFTWalletUpgradeable on Tempo, so we send directly from the deployer.
    function run() public override broadcastAs(configDeployerPK) {
        // Validate peers on source chain
        require(
            OFTUpgradeable(srcFraxOft).isPeer(uint32(dstEid), addressToBytes32(dstFraxOft)),
            "wfrax is not wired to destination"
        );
        require(
            OFTUpgradeable(srcsfrxusdOft).isPeer(uint32(dstEid), addressToBytes32(dstsfrxusdOft)),
            "sfrxusd is not wired to destination"
        );
        require(
            OFTUpgradeable(srcsfrxethOft).isPeer(uint32(dstEid), addressToBytes32(dstsfrxethOft)),
            "sfrxeth is not wired to destination"
        );
        require(
            OFTUpgradeable(srcfrxusdOft).isPeer(uint32(dstEid), addressToBytes32(dstfrxusdOft)),
            "frxusd is not wired to destination"
        );
        require(
            OFTUpgradeable(srcfrxethOft).isPeer(uint32(dstEid), addressToBytes32(dstfrxethOft)),
            "frxeth is not wired to destination"
        );
        require(
            OFTUpgradeable(srcfpiOft).isPeer(uint32(dstEid), addressToBytes32(dstfpiOft)),
            "fpi is not wired to destination"
        );

        SendParam memory _sendParam = SendParam({
            dstEid: uint32(dstEid),
            to: addressToBytes32(recipientWallet),
            amountLD: amount,
            minAmountLD: 0,
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });

        // Resolve user's TIP20 gas token for fee approvals
        address gasToken = StdPrecompiles.TIP_FEE_MANAGER.userTokens(msg.sender);
        if (gasToken == address(0)) gasToken = StdTokens.PATH_USD_ADDRESS;

        // Send each OFT individually — no wallet on Tempo, ERC20 gas payment via TempoAltTokenBase
        _sendOFTTempo(IOFT(srcFraxOft), _sendParam, gasToken);
        _sendOFTTempo(IOFT(srcsfrxusdOft), _sendParam, gasToken);
        _sendOFTTempo(IOFT(srcsfrxethOft), _sendParam, gasToken);
        _sendOFTTempo(IOFT(srcfrxusdOft), _sendParam, gasToken);
        _sendOFTTempo(IOFT(srcfrxethOft), _sendParam, gasToken);
        _sendOFTTempo(IOFT(srcfpiOft), _sendParam, gasToken);
    }

    /// @dev Send a single OFT from Tempo using ERC20 gas payment.
    ///      Approves the OFT for both the underlying token and the gas token,
    ///      then calls send{value: 0} (Tempo OFTs revert on msg.value > 0).
    function _sendOFTTempo(IOFT _oft, SendParam memory _sendParam, address _gasToken) internal {
        // Approve OFT to spend the underlying token for bridging
        IERC20(_oft.token()).approve(address(_oft), _sendParam.amountLD);

        // Quote LZ fee (in endpoint-native / LZEndpointDollar units)
        MessagingFee memory fee = _oft.quoteSend(_sendParam, false);

        // Quote gas token cost and approve — TempoAltTokenBase pulls from msg.sender via transferFrom
        uint256 gasTokenFee = TempoAltTokenBase(address(_oft)).quoteUserTokenFee(_gasToken, fee.nativeFee);
        IERC20(_gasToken).approve(address(_oft), gasTokenFee);

        // Send with value=0 — Tempo OFTs handle gas payment via ERC20 internally
        _oft.send{ value: 0 }(_sendParam, fee, senderWallet);
    }
}
