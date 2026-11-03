// SPDX-License-Identifier: ISC
pragma solidity ^0.8.22;

import {SafeDelegateBatch} from "./SafeDelegateBatch.sol";

/// LayerZero / legacy hop interfaces are inlined (only the members used) so the verified source is a
/// few short files a signer can read on the explorer without chasing package imports.
interface IMessageLibManager {
    struct SetConfigParam {
        uint32 eid;
        uint32 configType;
        bytes config;
    }

    function setSendLibrary(address _oapp, uint32 _eid, address _newLib) external;
    function setReceiveLibrary(address _oapp, uint32 _eid, address _newLib, uint256 _gracePeriod) external;
    function setConfig(address _oapp, address _lib, SetConfigParam[] calldata _params) external;
}

interface IOAppCore {
    function setPeer(uint32 _eid, bytes32 _peer) external;
}

interface IOAppOptionsType3 {
    struct EnforcedOptionParam {
        uint32 eid;
        uint16 msgType;
        bytes options;
    }

    function setEnforcedOptions(EnforcedOptionParam[] calldata _enforcedOptions) external;
}

/// @dev Legacy V1 Fraxtal hub registry (FraxtalHop / FraxtalMintRedeemHop, onlyOwner).
interface IFraxtalHub {
    function setRemoteHop(uint32 _eid, bytes32 _remoteHop) external;
}

/// @notice LayerZero endpoint / OFT config recipes for a SafeDelegateBatch (see SafeDelegateBatch.sol for
///         the delegatecall rules): sever or retire routes, freeze sends, pin DVN sets, hub registry.
///         `_sever` mirrors `DeprecateOFTBase._deprecatePairOnToken`:
///           send library  -> BlockedMessageLib
///           peer          -> bytes32(0)            (only where the peer is still set)
///           receive lib   -> DEFAULT (address(0))
///           enforced opts -> bare Type-3 (0x0003)   (owner-gated; skipped where the Safe is not owner)
///           app ULN cfg   -> empty UlnConfig on the send and receive ULN302 libraries
///         The endpoint reverts LZ_SameValue when a library is already at the target value, so a
///         subclass must only sever routes whose libraries are still dirty (the fork tests pin that).
abstract contract OftConfigBatch is SafeDelegateBatch {
    /// @dev UlnConfig layout from `@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol`;
    ///      encoded as the zero config so the OApp falls back to the library defaults.
    struct UlnConfig {
        uint64 confirmations;
        uint8 requiredDVNCount;
        uint8 optionalDVNCount;
        uint8 optionalDVNThreshold;
        address[] requiredDVNs;
        address[] optionalDVNs;
    }

    uint32 internal constant CONFIG_TYPE_ULN = 2;
    uint16 internal constant MSG_TYPE_SEND = 1;
    uint16 internal constant MSG_TYPE_SEND_AND_CALL = 2;
    /// @dev OptionsBuilder.newOptions() with no entries.
    bytes internal constant EMPTY_TYPE3_OPTIONS = hex"0003";

    /// @dev Legacy-mesh OFT set (same deterministic addresses on Ethereum-legacy, Metis, Base and Blast).
    address internal constant LEGACY_WFRAX = 0x23432452B720C80553458496D4D9d7C5003280d0;
    address internal constant LEGACY_SFRXUSD = 0xe4796cCB6bB5DE2290C417Ac337F2b66CA2E770E;
    address internal constant LEGACY_SFRXETH = 0x1f55a02A049033E3419a8E2975cF3F572F4e6E9A;
    address internal constant LEGACY_FRXUSD = 0x909DBdE1eBE906Af95660033e478D59EFe831fED;
    address internal constant LEGACY_FRXETH = 0xF010a7c8877043681D59AD125EbF575633505942;
    /// @dev Legacy FPI is retired outright (dust supply), so it is not in legacyOfts().
    address public constant LEGACY_FPI = 0x6Eca253b102D41B6B69AC815B9CC6bD47eF1979d;

    function endpoint() public pure virtual returns (address);
    function blockedLibrary() public pure virtual returns (address);
    function sendUln302() public pure virtual returns (address);
    function receiveUln302() public pure virtual returns (address);

    function _sever(address _oft, uint32 _eid, bool _clearPeer, bool _clearEnforcedOptions) internal {
        IMessageLibManager(endpoint()).setSendLibrary(_oft, _eid, blockedLibrary());
        if (_clearPeer) IOAppCore(_oft).setPeer(_eid, bytes32(0));
        IMessageLibManager(endpoint()).setReceiveLibrary(_oft, _eid, address(0), 0);
        if (_clearEnforcedOptions) {
            IOAppOptionsType3.EnforcedOptionParam[] memory options = new IOAppOptionsType3.EnforcedOptionParam[](2);
            options[0] = IOAppOptionsType3.EnforcedOptionParam({eid: _eid, msgType: MSG_TYPE_SEND, options: EMPTY_TYPE3_OPTIONS});
            options[1] = IOAppOptionsType3.EnforcedOptionParam({eid: _eid, msgType: MSG_TYPE_SEND_AND_CALL, options: EMPTY_TYPE3_OPTIONS});
            IOAppOptionsType3(_oft).setEnforcedOptions(options);
        }
        _zeroUlnConfig(_oft, _eid);
    }

    /// @dev The five legacy OFTs that keep their Ethereum exit lane (user-held supply).
    function legacyOfts() public pure returns (address[] memory list) {
        list = new address[](5);
        (list[0], list[1], list[2]) = (LEGACY_WFRAX, LEGACY_SFRXUSD, LEGACY_SFRXETH);
        (list[3], list[4]) = (LEGACY_FRXUSD, LEGACY_FRXETH);
    }

    /// @dev Legacy mesh policy: spokes may only bridge INTO Ethereum-legacy (whose send libraries
    ///      are already blocked). Spoke-to-spoke lanes are closed on the SEND side only — peers and
    ///      receive config stay — so a spoke that has executed can no longer send, but still
    ///      receives anything a not-yet-executed spoke sends. Zeroing a peer here would instead open
    ///      a one-way burn until the other spoke's Safe executes. Metis is not executed (its Safe
    ///      UI is unavailable): it keeps sending to Blast/Base, which keep receiving — still safe.
    function _blockLegacySpokeLanes(uint32 _spokeEidA, uint32 _spokeEidB) internal {
        address[] memory ofts = legacyOfts();
        uint32[] memory eids = new uint32[](2);
        (eids[0], eids[1]) = (_spokeEidA, _spokeEidB);
        for (uint256 i = 0; i < ofts.length; i++) {
            _blockSends(ofts[i], eids);
        }
    }

    /// @dev Send-side freeze: outbound to `_eids` goes through BlockedMessageLib; peers, receive
    ///      libraries and DVN config are untouched, so inbound (and anything in flight) still lands.
    function _blockSends(address _oft, uint32[] memory _eids) internal {
        for (uint256 i = 0; i < _eids.length; i++) {
            IMessageLibManager(endpoint()).setSendLibrary(_oft, _eids[i], blockedLibrary());
        }
    }

    /// @dev Full retirement of a route, the state the 2026-08-26 batch left the non-canonical FPI
    ///      adapter's EVM lanes in: nothing can be sent, nothing can be received, no peer.
    ///      `_blockSend` is false where the send library is already BlockedMessageLib (LZ_SameValue).
    function _retireRoutes(address _oft, uint32[] memory _eids, bool _blockSend) internal {
        for (uint256 i = 0; i < _eids.length; i++) {
            if (_blockSend) IMessageLibManager(endpoint()).setSendLibrary(_oft, _eids[i], blockedLibrary());
            IOAppCore(_oft).setPeer(_eids[i], bytes32(0));
            IMessageLibManager(endpoint()).setReceiveLibrary(_oft, _eids[i], blockedLibrary(), 0);
        }
    }

    /// @dev NIL_DVN_COUNT: "no optional DVNs" (0 would mean "use the default optional set").
    uint8 internal constant NIL_DVN_COUNT = type(uint8).max;

    /// @dev Pin the required DVN set of one route on one ULN302 library (`_dvns` ascending, unique).
    function _setRequiredDvns(address _oft, uint32 _eid, address _lib, uint64 _confirmations, address[] memory _dvns)
        internal
    {
        for (uint256 i = 1; i < _dvns.length; i++) {
            require(_dvns[i] > _dvns[i - 1], "DVNs must be ascending");
        }
        IMessageLibManager.SetConfigParam[] memory params = new IMessageLibManager.SetConfigParam[](1);
        params[0] = IMessageLibManager.SetConfigParam({
            eid: _eid,
            configType: CONFIG_TYPE_ULN,
            config: abi.encode(
                UlnConfig({
                    confirmations: _confirmations,
                    requiredDVNCount: uint8(_dvns.length),
                    optionalDVNCount: NIL_DVN_COUNT,
                    optionalDVNThreshold: 0,
                    requiredDVNs: _dvns,
                    optionalDVNs: new address[](0)
                })
            )
        });
        IMessageLibManager(endpoint()).setConfig(_oft, _lib, params);
    }

    function _eids3(uint32 _a, uint32 _b, uint32 _c) internal pure returns (uint32[] memory eids) {
        eids = new uint32[](3);
        (eids[0], eids[1], eids[2]) = (_a, _b, _c);
    }

    function _zeroUlnConfig(address _oft, uint32 _eid) internal {
        IMessageLibManager.SetConfigParam[] memory params = new IMessageLibManager.SetConfigParam[](1);
        params[0] = IMessageLibManager.SetConfigParam({
            eid: _eid,
            configType: CONFIG_TYPE_ULN,
            config: abi.encode(
                UlnConfig({
                    confirmations: 0,
                    requiredDVNCount: 0,
                    optionalDVNCount: 0,
                    optionalDVNThreshold: 0,
                    requiredDVNs: new address[](0),
                    optionalDVNs: new address[](0)
                })
            )
        });
        IMessageLibManager(endpoint()).setConfig(_oft, sendUln302(), params);
        IMessageLibManager(endpoint()).setConfig(_oft, receiveUln302(), params);
    }
}
