// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "scripts/DeployFraxOFTProtocol.s.sol";

// forge script scripts/ops/deploy/DeployFraxtalLockboxes/2_ConnectFraxtalLockboxesToEthereum.s.sol --rpc-url https://rpc.frax.com
contract ConnectFraxtalLockboxesToEthereum is DeployFraxOFTProtocol {

    L0Config[] public ethConfigArray;

    function filename() public view override {

    }

    function run() public override {
        // Align two lockboxes to [frxETH, sfrxETH, FXS, FPI]
        delete fraxtalLockboxes;
        fraxtalLockboxes.push(fraxtalFrxEthLockbox);
        fraxtalLockboxes.push(fraxtalSFrxEthLockbox);
        fraxtalLockboxes.push(fraxtalFxsLockbox);
        fraxtalLockboxes.push(fraxtalFpiLockbox);

        delete ethLockboxes;
        ethLockboxes.push(ethFrxEthLockbox);
        ethLockboxes.push(ethSFrxEthLockbox);
        ethLockboxes.push(ethFxsLockbox);
        ethLockboxes.push(ethFpiLockbox);

        // populate ethConfigArray with length 1 of eth config
        for (uint256 c=0; c<legacyConfigs.length; c++) {
            if (legacyConfigs[c].chainid == 1) {
                ethConfigArray.push(legacyConfigs[c]);
            }
        }

        setupSource();
        setupDestinations();
    }

    function setupSource() public override simulateAndWriteTxs(broadcastConfig) {
        setupEvms();

        setDVNs({
            _connectedConfig: broadcastConfig
        })
    }

    function setupEvms() public virtual {
        setEvmEnforcedOptions({
            _connectedOfts: fraxtalLockboxes,
            _configs: ethConfigArray
        });

        /// @dev Upgradeable OFTs maintaining the same address cross-chain.
        setEvmPeers({
            _connectedOfts: fraxtalLockboxes,
            _peerOfts: ethLockboxes,
            _configs: ethConfigArray
        });
    }
}