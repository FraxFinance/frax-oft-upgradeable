// SPDX-License-Identifier: ISC
pragma solidity ^0.8.22;

import {OftConfigBatch, IMessageLibManager, IOAppCore, IOAppOptionsType3} from "../OftConfigBatch.sol";
import {ILegacyRemoteHop, IOldHopV2} from "../HopAdminBatch.sol";

/// @dev Read side of the two endpoint settings that revert `LZ_SameValue` when already at target.
///      Declared here rather than in OftConfigBatch so the nine batches already deployed from that
///      file still compile to the bytecode living at their addresses.
interface IEndpointLibraryView {
    function getSendLibrary(address _sender, uint32 _eid) external view returns (address);
    function getReceiveLibrary(address _receiver, uint32 _eid) external view returns (address lib, bool isDefault);
}

/// @notice One Safe transaction on Katana (chain 747474) for FRA-100: the Fraxtal lane to 5/5.
///         Horizen now runs a DVN on Katana, so the six OFTs' send and receive ULN config toward
///         Fraxtal (30255) goes from 4 to 5 required DVNs (confirmations unchanged: 60 out, 5 in),
///         and the two live hops quote the return leg with numDVNs = 5. The V1 RemoteHop is already
///         wound down and stays untouched. Execute Batch202609Fraxtal FIRST.
///         FPI is retired mesh-wide: Fraxtal already severed its side, so the stale Katana FPI route
///         (still peered, live libraries, zero supply) is severed here instead of upgraded — but
///         idempotently, see `_severFpiTowardFraxtal`.
contract Batch202609Katana is OftConfigBatch {
    address public constant KATANA_SAFE = 0x19A90b0476cdc8EC1239266663CA820175B9B527;
    address public constant REMOTE_MINT_REDEEM_HOP = 0xF6f45CCB5E85D1400067ee66F9e168f83e86124E;
    address public constant REMOTE_HOP_V2 = 0x0000006D38568b00B457580b734e0076C62de659;
    uint32 public constant FRAXTAL_EID = 30255;
    uint64 public constant FRAXTAL_SEND_CONFIRMATIONS = 60;
    uint64 public constant FRAXTAL_RECEIVE_CONFIRMATIONS = 5;
    uint32 public constant NUM_DVNS = 5;

    function safe() public pure override returns (address) {
        return KATANA_SAFE;
    }

    function chainId() public pure override returns (uint256) {
        return 747474;
    }

    function endpoint() public pure override returns (address) {
        return 0x6F475642a6e85809B1c36Fa62763669b1b48DD5B;
    }

    function blockedLibrary() public pure override returns (address) {
        return 0xC1cE56B2099cA68720592583C7984CAb4B6d7E7a;
    }

    function sendUln302() public pure override returns (address) {
        return 0xC39161c743D0307EB9BCc9FEF03eeb9Dc4802de7;
    }

    function receiveUln302() public pure override returns (address) {
        return 0xe1844c5D63a9543023008D332Bd3d2e6f1FE1043;
    }

    address public constant FPI_OFT = 0x90581eCa9469D8D7F5D3B60f4715027aDFCf7927;

    /// @dev The five live OFTs on the Fraxtal lane.
    function ofts() public pure returns (address[] memory list) {
        list = new address[](5);
        list[0] = 0x64445f0aecC51E94aD52d8AC56b7190e764E561a; // WFRAX
        list[1] = 0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0; // sfrxUSD
        list[2] = 0x3Ec3849C33291a9eF4c5dB86De593EB4A37fDe45; // sfrxETH
        list[3] = 0x80Eede496655FB9047dd39d9f418d5483ED600df; // frxUSD
        list[4] = 0x43eDD7f3831b08FE70B7555ddD373C8bF65a9050; // frxETH
    }

    /// @dev Katana-side DVNs for the Fraxtal lane, ascending: LayerZero, Canary, Frax, Horizen, Nethermind.
    function fraxtalDvns() public pure returns (address[] memory dvns) {
        dvns = new address[](5);
        dvns[0] = 0x282b3386571f7f794450d5789911a9804FA346b4;
        dvns[1] = 0x53fF818a1c492e667E2cD0b5AFe0FC82c66d33c7;
        dvns[2] = 0x5FA12ebC08e183C1F5d44678cF897edEfe68738B;
        dvns[3] = 0x84a410A8a912e333B957680998a76e526f98e207;
        dvns[4] = 0xaCDe1f22EEAb249d3ca6Ba8805C8fEe9f52a16e7;
    }

    function _run() internal override {
        address[] memory list = ofts();
        address[] memory dvns = fraxtalDvns();
        for (uint256 i = 0; i < list.length; i++) {
            _setRequiredDvns(list[i], FRAXTAL_EID, sendUln302(), FRAXTAL_SEND_CONFIRMATIONS, dvns);
            _setRequiredDvns(list[i], FRAXTAL_EID, receiveUln302(), FRAXTAL_RECEIVE_CONFIRMATIONS, dvns);
        }
        ILegacyRemoteHop(REMOTE_MINT_REDEEM_HOP).setNumDVNs(NUM_DVNS);
        IOldHopV2(REMOTE_HOP_V2).setNumDVNs(NUM_DVNS);

        _severFpiTowardFraxtal();
    }

    /// @dev `_sever(FPI_OFT, FRAXTAL_EID, true, true)`, with the two calls that cannot be repeated
    ///      guarded.
    ///
    ///      This Safe is shared. Another campaign holds an executable proposal on it (nonce 22 at the
    ///      time of writing, 2 of 3 confirmations) that severs this exact route, and a Safe runs its
    ///      nonces in order, so that one lands first. The endpoint reverts `LZ_SameValue` when asked
    ///      to set a library that is already at its target, and in a single all-or-nothing batch that
    ///      one already-done call reverts everything — the FRA-100 DVN work above included. Measured
    ///      on a fork: of the six calls `_sever` makes, only `setSendLibrary` and `setReceiveLibrary`
    ///      revert on a second application; `setPeer`, `setEnforcedOptions` and both `setConfig`s are
    ///      idempotent and run unconditionally so the end state is identical either way.
    ///
    ///      So whichever campaign executes first, both finish. Nothing here depends on the other
    ///      proposal existing, being confirmed, or being deleted.
    function _severFpiTowardFraxtal() internal {
        IEndpointLibraryView view_ = IEndpointLibraryView(endpoint());

        if (view_.getSendLibrary(FPI_OFT, FRAXTAL_EID) != blockedLibrary()) {
            IMessageLibManager(endpoint()).setSendLibrary(FPI_OFT, FRAXTAL_EID, blockedLibrary());
        }
        IOAppCore(FPI_OFT).setPeer(FRAXTAL_EID, bytes32(0));
        (, bool isDefault) = view_.getReceiveLibrary(FPI_OFT, FRAXTAL_EID);
        if (!isDefault) {
            IMessageLibManager(endpoint()).setReceiveLibrary(FPI_OFT, FRAXTAL_EID, address(0), 0);
        }
        IOAppOptionsType3.EnforcedOptionParam[] memory options = new IOAppOptionsType3.EnforcedOptionParam[](2);
        options[0] =
            IOAppOptionsType3.EnforcedOptionParam({eid: FRAXTAL_EID, msgType: MSG_TYPE_SEND, options: EMPTY_TYPE3_OPTIONS});
        options[1] = IOAppOptionsType3.EnforcedOptionParam({
            eid: FRAXTAL_EID,
            msgType: MSG_TYPE_SEND_AND_CALL,
            options: EMPTY_TYPE3_OPTIONS
        });
        IOAppOptionsType3(FPI_OFT).setEnforcedOptions(options);
        _zeroUlnConfig(FPI_OFT, FRAXTAL_EID);
    }
}
