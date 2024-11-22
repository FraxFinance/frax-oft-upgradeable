// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "../DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import { FraxOFTAdapterUpgradeable } from "contracts/FraxOFTAdapterUpgradeable.sol";
import { IMessageLibManager } from "@fraxfinance/layerzero-v2-upgradeable/protocol/contracts/interfaces/IMessageLibManager.sol";

/// @dev Deploy the frxUSD and sfrxUSD adapters, connect them to Mode, sei, x-layer
/*
source .env && forge script scripts/UpgradeFrax/5_DeployFraxtalAdapter.s.sol --rpc-url https://rpc.frax.com \
    --verifier-url $FRAXSCAN_API_URL --etherscan-api-key $FRAXSCAN_API_KEY
*/
contract DeployFraxtalAdapterOFT is DeployFraxOFTProtocol {
    using OptionsBuilder for bytes;
    using stdJson for string;
    using Strings for uint256;

    address[] public oldProxyOfts;
    address public frxUsd = 0xFc00000000000000000000000000000000000001;
    address public sfrxUsd = 0xfc00000000000000000000000000000000000008;

    /// @dev setup oldProxyOfts to point new adapter proxy OFTs to
    /// @dev note that proxyOfts will within this contract point to the adapters
    constructor() {
        oldProxyOfts.push(0x80Eede496655FB9047dd39d9f418d5483ED600df); // FRAX
        oldProxyOfts.push(0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0); // sFRAX
    }

    /// @dev override to alter file save location
    modifier simulateAndWriteTxs(L0Config memory _config) override {
        // Clear out arrays
        delete enforcedOptionsParams;
        delete setConfigParams;
        delete serializedTxs;

        vm.createSelectFork(_config.RPC);
        chainid = _config.chainid;
        vm.startPrank(_config.delegate);
        _;
        vm.stopPrank();

        // create filename and save
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/UpgradeFrax/txs/");
        string memory filename = string.concat("5_DeployFraxtalAdapter-", _config.chainid.toString());
        filename = string.concat(filename, ".json");

        new SafeTxUtil().writeTxs(serializedTxs, string.concat(root, filename));
    }

    /// @dev skip setting legacy OFTs, config with oldProxyOfts, set send recieve lib
    function setupSource() public override broadcastAs(configDeployerPK) {
        setEnforcedOptions({
            _connectedOfts: proxyOfts,
            _configs: configs
        });

        setDVNs({
            _connectedConfig: activeConfig,
            _connectedOfts: proxyOfts,
            _configs: configs
        });

        // setPeers({
        //     _connectedOfts: proxyOfts,
        //     _peerOfts: legacyOfts,
        //     _configs: legacyConfigs
        // });

        setPeers({
            _connectedOfts: proxyOfts,
            _peerOfts: oldProxyOfts,
            // _peerOfts: proxyOfts,
            _configs: proxyConfigs
        });

        setSendReceiveLibs({
            _connectedConfig: activeConfig,
            _connectedOfts: proxyOfts,
            _configs: proxyConfigs
        });

        setPriviledgedRoles();
    }

    function setSendReceiveLibs(
        L0Config memory _connectedConfig,
        address[] memory _connectedOfts,
        L0Config[] memory _configs
    ) public {
        // For each connected oft
        for (uint256 o=0; o<_connectedOfts.length; o++) {
            // set the sendReceive library per chain
            for (uint256 c=0; c<_configs.length; c++) {
                setSendReceiveLib({
                    _connectedConfig: _connectedConfig,
                    _connectedOft: _connectedOfts[o],
                    _config: _configs[c]
                });
            }
        }
    }

    function setSendReceiveLib(
        L0Config memory _connectedConfig,
        address _connectedOft,
        L0Config memory _config
    ) public {
        // skip setting libs for self
        if (_connectedConfig.eid == _config.eid) return;
        
        // set sendLib to default
        IMessageLibManager(_connectedConfig.endpoint).setSendLibrary({
            _oapp: _connectedOft,
            _eid: uint32(_config.eid),
            _newLib: _connectedConfig.sendLib302
        });

        // set receiveLib to default
        IMessageLibManager(_connectedConfig.endpoint).setReceiveLibrary({
            _oapp: _connectedOft,
            _eid: uint32(_config.eid),
            _newLib: _connectedConfig.receiveLib302,
            _gracePeriod: 0
        });
    }
    
    /// @dev only setup proxy destinations
    function setupDestinations() public override {
        // setupLegacyDestinations();
        setupProxyDestinations();
    }

    /// @dev set the peer config to the new contracts (enforced options, dvns already set for chain)
    function setupDestination(
        L0Config memory _connectedConfig,
        address[] memory _connectedOfts
    ) public override simulateAndWriteTxs(_connectedConfig) {
        // setEnforcedOptions({
        //     _connectedOfts: _connectedOfts,
        //     _configs: activeConfigArray
        // });

        // setDVNs({
        //     _connectedConfig: _connectedConfig,
        //     _connectedOfts: _connectedOfts,
        //     _configs: activeConfigArray
        // });

        setPeers({
            // _connectedOfts: _connectedOfts,
            _connectedOfts: oldProxyOfts,
            _peerOfts: proxyOfts,
            _configs: activeConfigArray
        });
    }


    /// @dev simple checks override
    function postDeployChecks() public override view {
        require(fraxOft != address(0));
        require(sFraxOft != address(0));
    }

    /// @dev only deploy the FRAX and sFRAX adapters, as config deployer to maintain semi-determinstic-ness of oftDeployerPK
    function deployFraxOFTUpgradeablesAndProxies() /* broadcastAs(oftDeployerPK) */ broadcastAs(configDeployerPK) public override {
        // already deployed
        proxyAdmin = 0x223a681fc5c5522c85C96157c0efA18cd6c5405c;
        implementationMock = 0x8f1B9c1fd67136D525E14D96Efb3887a33f16250;

        // deploy frax
        (, fraxOft) = deployFraxOFTUpgradeableAndProxy({
            _name: "Frax USD",
            _symbol: "frxUSD",
            _token: frxUsd
        });

        // deploy sFrax
        (, sFraxOft) = deployFraxOFTUpgradeableAndProxy({
            _name: "Staked Frax USD",
            _symbol: "sfrxUSD",
            _token: sfrxUsd
        });
    }

    /// @dev override the bytecode to the OFTAdapter and init
   function deployFraxOFTUpgradeableAndProxy(
        string memory _name,
        string memory _symbol,
        address _token
    ) public returns (address implementation, address proxy) {
        /// @dev override here
        bytes memory bytecode = bytes.concat(
            abi.encodePacked(type(FraxOFTAdapterUpgradeable).creationCode),
            // abi.encode(activeConfig.endpoint)
            abi.encode(_token, activeConfig.endpoint)
        );
        assembly {
            implementation := create(0, add(bytecode, 0x20), mload(bytecode))
            if iszero(extcodesize(implementation)) {
                revert(0, 0)
            }
        }
        /// @dev as we're deploying from the config addr, set as the owner
        proxy = address(new TransparentUpgradeableProxy(implementationMock, /* vm.addr(oftDeployerPK) */ vm.addr(configDeployerPK) , ""));

        /// @dev override
        bytes memory initializeArgs = abi.encodeWithSelector(
            FraxOFTAdapterUpgradeable.initialize.selector,
            // _name,
            // _symbol,
            vm.addr(configDeployerPK)
        );
        TransparentUpgradeableProxy(payable(proxy)).upgradeToAndCall({
            newImplementation: implementation,
            data: initializeArgs
        });
        TransparentUpgradeableProxy(payable(proxy)).changeAdmin(proxyAdmin);
        proxyOfts.push(proxy);

        // State checks
        // require(
        //     isStringEqual(FraxOFTUpgradeable(proxy).name(), _name),
        //     "OFT name incorrect"
        // );
        // require(
        //     isStringEqual(FraxOFTUpgradeable(proxy).symbol(), _symbol),
        //     "OFT symbol incorrect"
        // );
        require(
            address(FraxOFTUpgradeable(proxy).endpoint()) == activeConfig.endpoint,
            "OFT endpoint incorrect"
        );
        require(
            EndpointV2(activeConfig.endpoint).delegates(proxy) == vm.addr(configDeployerPK),
            "Endpoint delegate incorrect"
        );
        require(
            FraxOFTUpgradeable(proxy).owner() == vm.addr(configDeployerPK),
            "OFT owner incorrect"
        );
    }

    /// @dev proxy admin already deployed - do not transfer ownership
    function setPriviledgedRoles() public override {
        for (uint256 o=0; o<proxyOfts.length; o++) {
            address proxyOft = proxyOfts[o];
            FraxOFTUpgradeable(proxyOft).setDelegate(activeConfig.delegate);
            Ownable(proxyOft).transferOwnership(activeConfig.delegate);
        }

        // Ownable(proxyAdmin).transferOwnership(activeConfig.delegate);
    }
}