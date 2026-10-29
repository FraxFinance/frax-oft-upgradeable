// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "./SetupSourceFraxOFTFraxtalHubCelo.s.sol";

/// @notice Celo Safe batch that brings the Celo <> Fraxtal lane from 4 to 5 required DVNs by adding the Frax DVN:
///         one send and one receive ULN setConfig per OFT, confirmations unchanged. The OFTs belong to the Celo Safe
///         since step 2, so this simulates as the delegate and writes a Safe batch instead of broadcasting.
// forge script scripts/FraxtalHub/2_SetupSourceFraxOFTFraxtalHub/SetFraxDVNFraxOFTFraxtalHubCelo.s.sol --rpc-url https://forno.celo.org --ffi
contract SetFraxDVNFraxOFTFraxtalHubCelo is SetupSourceFraxOFTFraxtalHubCelo {
    function run() public override {
        _validateAddrs();

        L0Config[] memory fraxtal = new L0Config[](1);
        for (uint256 i = 0; i < proxyConfigs.length; i++) {
            if (proxyConfigs[i].chainid == 252) fraxtal[0] = proxyConfigs[i];
        }
        require(fraxtal[0].chainid == 252, "Fraxtal config missing");

        _setDVNsAsDelegate(fraxtal);
    }

    function _setDVNsAsDelegate(L0Config[] memory _fraxtal) internal simulateAndWriteTxs(broadcastConfig) {
        setDVNs({ _connectedConfig: broadcastConfig, _connectedOfts: proxyOfts, _configs: _fraxtal });
        require(serializedTxs.length == 2 * proxyOfts.length, "expected a send and a receive setConfig per OFT");
    }

    /// @dev proxyOfts comes from the constructor; connectedOfts is not used here.
    function _populateConnectedOfts() public override {}

    function getFileExtension() internal pure override returns (string memory) {
        return "-frax-dvn.json";
    }
}
