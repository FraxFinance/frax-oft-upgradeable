pragma solidity ^0.8.0;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";


// Set peers to address(0) on fraxtal and broadcasted chain
contract DeprecateChain is DeployFraxOFTProtocol {
    using Strings for uint256;
    using stdJson for string;

    L0Config public fraxtalConfig;
    L0Config public peerConfig;

    function setUp() public override {
        super.setUp();
        
        for (uint256 i = 0; i < proxyConfigs.length; i++) {
            if (proxyConfigs[i].chainid == 252) {
                fraxtalConfig = proxyConfigs[i];
                break;
            }
        }
    }

    // Write filename like: `Deprecate-{BroadcastedChainId}-{PeerChainId}.json`.  Meaning, submit 
    // the crafted json to the broadcasted chain
    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        string memory name = string.concat(
            root,
            "/scripts/ops/DeprecateChain/txs/Deprecate-",
            simulateConfig.chainid.toString(),
            "-",
            peerConfig.chainid.toString(),
            ".json"
        );
        return name;
    }

    function run() public override {    
        // we start with simulating the broadcast config and resetting the fraxtal peer
        setEvmPeers({
            _simulateConfig: broadcastConfig,
            _peerConfig: fraxtalConfig
        });

        // then we simulate fraxtal and reset the broadcasted chain peer
        setEvmPeers({
            _simulateConfig: fraxtalConfig,
            _peerConfig: broadcastConfig
        });
    }

    function setEvmPeers(
        L0Config memory _simulateConfig,
        L0Config memory _peerConfig
    ) public simulateAndWriteTxs(_simulateConfig) {
        // connectedOFTs are populated via simulateAndWriteTxs- this is a sanity check
        require(connectedOfts.length == 6, "Missing connected OFTs");

        peerConfig = _peerConfig;

        // For each OFT
        for (uint256 o=0; o<connectedOfts.length; o++) {
            setPeer({
                _config: _peerConfig,
                _connectedOft: connectedOfts[o],
                _peerOftAsBytes32: addressToBytes32(address(0))
            });
        }
    }
}