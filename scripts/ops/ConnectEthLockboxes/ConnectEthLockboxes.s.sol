pragma solidity ^0.8.19;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

// connect (s)frxETH, FPI, FXS(?) to proxyOfts
// forge script scripts/ops/ConnectEthLockboxes/ConnectEthLockboxes.s.sol --rpc-url https://ethereum-rpc.publicnode.com
contract ConnectEthLockboxes is DeployFraxOFTProtocol {
    using Strings for uint256;

    address[] ethLockboxes;
    uint256 counter;

    // overwrite to put msig tx in local dir
    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/ops/ConnectEthLockboxes/txs/");
        string memory name = string.concat(counter.toString(), ".json");
        return string.concat(root, name);
    }

    function run() public override {
        // to make setEvmPeers() pass
        frxUsdOft = address(1);
        sfrxUsdOft = address(1);

        // [frxEth, sfrxEth, FXS, FPI]

        // lockboxes - verified
        ethLockboxes.push(0xF010a7c8877043681D59AD125EbF575633505942); // frxETH lockbox
        ethLockboxes.push(0x1f55a02A049033E3419a8E2975cF3F572F4e6E9A); // sfrxETH lockbox
        ethLockboxes.push(0x23432452B720C80553458496D4D9d7C5003280d0); // FXS lockbox
        ethLockboxes.push(0x6Eca253b102D41B6B69AC815B9CC6bD47eF1979d); // FPI

        // OFTs - verified
        proxyOfts.push(0x43eDD7f3831b08FE70B7555ddD373C8bF65a9050); // frxETH oft
        proxyOfts.push(0x3Ec3849C33291a9eF4c5dB86De593EB4A37fDe45); // sfrxETH oft
        proxyOfts.push(0x64445f0aecC51E94aD52d8AC56b7190e764E561a); // FXS oft
        proxyOfts.push(0x90581eCa9469D8D7F5D3B60f4715027aDFCf7927); // FPI oft

        setupDestinations();
    }

    function setupProxyDestinations() public override {
        for (uint256 i=0; i<proxyConfigs.length; i++) {
            // skip if destination == source
            if (proxyConfigs[i].eid == broadcastConfig.eid) continue;

            // skip setup for mode, sei, xlayer, fraxtal as they're already configured
            if (
                proxyConfigs[i].chainid == 34443 || proxyConfigs[i].chainid == 1329 ||
                proxyConfigs[i].chainid == 252 || proxyConfigs[i].chainid == 196
            ) continue;
            counter++;

            setupDestination({
                _connectedConfig: proxyConfigs[i]
            });
        }
    }

    function setupDestination(
        L0Config memory _connectedConfig
    ) public override simulateAndWriteTxs(broadcastConfig) {
        L0Config[] memory configs = new L0Config[](1);
        configs[0] = _connectedConfig;

        setEvmEnforcedOptions({
            _connectedOfts: ethLockboxes,
            _configs: configs
        });

        setEvmPeers({
            _connectedOfts: ethLockboxes,
            _peerOfts: proxyOfts,
            _configs: configs
        });

        setDVNs({
            _connectedConfig: broadcastConfig,
            _connectedOfts: ethLockboxes,
            _configs: configs
        });
    }
}