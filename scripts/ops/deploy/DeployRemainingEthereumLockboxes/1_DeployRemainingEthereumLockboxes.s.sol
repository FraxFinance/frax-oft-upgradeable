// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import "contracts/FraxOFTAdapterUpgradeable.sol";

/*
GOALS
- Deploy upgradeable (s)frxETH, FXS, FPI lockboxes to Ethereum

TODO
- Connect to Solana OFTs
*/

// forge script scripts/ops/deploy/DeployRemainingEthereumLockboxes/DeployRemainingEthereumLockboxes.s.sol --rpc-url https://ethereum-rpc.publicnode.com
contract DeployRemainingEthereumLockboxes is DeployFraxOFTProtocol {

    using Strings for uint256;
    using stdJson for string;

    address frxEth = 0x5E8422345238F34275888049021821E8E08CAa1f;
    address sfrxEth = 0xac3E018457B222d93114458476f3E3416Abbe38F;
    address fxs = 0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0;
    address fpi = 0x5Ca135cB8527d76e932f34B5145575F9d8cbE08E;
  

    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/ops/deploy/DeployRemainingEthereumLockboxes/txs/");

        string memory name = string.concat(broadcastConfig.chainid.toString(), "-");
        name = string.concat(name, simulateConfig.chainid.toString());
        name = string.concat(name, ".json");
        return string.concat(root, name);
    }

    // Configure destination OFT addresses as they may be different per chain
    // `connectedOfts` is used within DeployfraxOFTProtocol.setupDestination()
    function _populateConnectedOfts() public virtual {
        if (simulateConfig.chainid == 252) {
            connectedOfts[0] = fraxtalLockboxes[0];
            connectedOfts[1] = fraxtalLockboxes[1];
            connectedOfts[2] = fraxtalLockboxes[2];
            connectedOfts[3] = fraxtalLockboxes[3];
        } else {
            connectedOfts[0] = expectedProxyOfts[0];
            connectedOfts[1] = expectedProxyOfts[1];
            connectedOfts[2] = expectedProxyOfts[2];
            connectedOfts[3] = expectedProxyOfts[3];
        }
    }

    function run() public override {
        // set expectedProxyOfts to [frxEthOft, sfrxEthOft, fxsOft, fpiOft]
        delete expectedProxyOfts;
        expectedProxyOfts.push(frxEthOft);
        expectedProxyOfts.push(sfrxEthOft);
        expectedProxyOfts.push(fxsOft);
        expectedProxyOfts.push(fpiOft);

        delete fraxtalLockboxes;
        fraxtalLockboxes.push(fraxtalFrxEthLockbox);
        fraxtalLockboxes.push(fraxtalSFrxEthLockbox);
        fraxtalLockboxes.push(fraxtalFxsLockbox);
        fraxtalLockboxes.push(fraxtalFpiLockbox);

        super.run();
    }

    // Additional deployProxyAdmin to get 0x223 addr for proxyAdmin
    function deploySource() public override {
        preDeployChecks();
        deployFraxOFTUpgradeablesAndProxies();
        // postDeployChecks()
    }

    // Deploy the four lockboxes to any address
    function deployFraxOFTUpgradeablesAndProxies() broadcastAs(configDeployerPK) public override {
        (, frxEthOft) = deployFraxOFTUpgradeableAndProxy({
            _token: frxEth
        });

        (, sfrxEthOft) = deployFraxOFTUpgradeableAndProxy({
            _token: sfrxEth
        });

        (, fxsOft) = deployFraxOFTUpgradeableAndProxy({
            _token: fxs
        });

        (, fpiOft) = deployFraxOFTUpgradeableAndProxy({
            _token: fpi
        });
    }

    function deployFraxOFTUpgradeableAndProxy(address _token) public returns (address implementation, address proxy) {
        proxyAdmin = 0x223a681fc5c5522c85C96157c0efA18cd6c5405c;
        implementationMock = 0x8f1B9c1fd67136D525E14D96Efb3887a33f16250;
        
        // create the implementation
        bytes memory bytecode = bytes.concat(
            abi.encodePacked(type(FraxOFTAdapterUpgradeable).creationCode),
            abi.encode(_token, broadcastConfig.endpoint)
        );
        assembly {
            implementation := create(0, add(bytecode, 0x20), mload(bytecode))
            if iszero(extcodesize(implementation)) {
                revert(0, 0)
            }
        }

        // TODO: shall we init implementation with address(0) ?
        // FraxOFTAdapterUpgradeable(implementation).initialize(address(0));

        // create the proxy
        proxy = address(new TransparentUpgradeableProxy(implementationMock, vm.addr(configDeployerPK), ""));
        proxyOfts.push(proxy);

        // upgrade and init
        bytes memory initializeArgs = abi.encodeWithSelector(
            FraxOFTAdapterUpgradeable.initialize.selector,
            vm.addr(configDeployerPK)
        );
        TransparentUpgradeableProxy(payable(proxy)).upgradeToAndCall({
            newImplementation: implementation,
            data: initializeArgs
        });

        // transfer ownership to config deployer
        TransparentUpgradeableProxy(payable(proxy)).changeAdmin(proxyAdmin);

        require(
            FraxOFTAdapterUpgradeable(proxy).token() == _token,
            "OFT token not set"
        );
        require(
            FraxOFTUpgradeable(proxy).owner() == vm.addr(configDeployerPK),
            "OFT owner incorrect"
        );
    }
}