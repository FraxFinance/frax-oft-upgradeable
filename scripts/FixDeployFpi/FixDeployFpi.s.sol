// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "../DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

/*
Intro:
FPI OFT Adapter was incorrectly deployed with FRAX as collateral.

Goal:
Deploy FPI upgradeable OFTs to Mode, Sei, Fraxtal, XLayer
*/

contract FixDeployFpi is DeployFraxOFTProtocol {
    using OptionsBuilder for bytes;
    using stdJson for string;
    using Strings for uint256;

    function version() public virtual override pure returns (uint256, uint256, uint256) {
        return (1, 0, 0);
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
        root = string.concat(root, "/scripts/FixDeployFpi/txs/");
        string memory filename = string.concat(activeConfig.chainid.toString(), "-");
        filename = string.concat(filename, _config.chainid.toString());
        filename = string.concat(filename, ".json");

        new SafeTxUtil().writeTxs(serializedTxs, string.concat(root, filename));
    }


    function setUp() public override {
        super.setUp();

        // clear out legacyOfts
        delete legacyOfts;
        delete proxyOfts;

        // set legacy OFTs with correct FPI
        legacyOfts.push(0x6Eca253b102D41B6B69AC815B9CC6bD47eF1979d);
    }

    /// @dev no need for post-deploy checks
    function deploySource() public virtual override {
        preDeployChecks();
        deployFraxOFTUpgradeablesAndProxies();
        // postDeployChecks();
    }

    /// @dev Only setup legacy destinations - proxy destinations are setup through deploySource()
    function setupDestinations() public virtual override {
        setupLegacyDestinations();
        // setupProxyDestinations();
    }

    function deployFraxOFTUpgradeablesAndProxies() broadcastAs(oftDeployerPK) public virtual override {
        // Implementation and proxy admin have already been deployed
        implementationMock = 0x8f1B9c1fd67136D525E14D96Efb3887a33f16250;
        proxyAdmin = 0x223a681fc5c5522c85C96157c0efA18cd6c5405c;

        // deploy FPI
        (, address proxy) = deployFraxOFTUpgradeableAndProxy({
            _name: "Frax Price Index",
            _symbol: "FPI"
        });
        require(proxy == 0x90581eCa9469D8D7F5D3B60f4715027aDFCf7927, "FPI address wrong");
    }

    /// @dev override as the proxyAdmin ownership is already properly set
    function setPriviledgedRoles() public virtual override {
        for (uint256 o=0; o<proxyOfts.length; o++) {
            address proxyOft = proxyOfts[o];
            FraxOFTUpgradeable(proxyOft).setDelegate(activeConfig.delegate);
            Ownable(proxyOft).transferOwnership(activeConfig.delegate);
        }

        /// @dev transfer ownership of ProxyAdmin
        // Ownable(proxyAdmin).transferOwnership(activeConfig.delegate);
    }

}
