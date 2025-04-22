// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import { Script } from "forge-std/Script.sol";
import { FraxDVN } from "contracts/FraxDVN.sol";
import { console } from "frax-std/FraxTest.sol";
import { OptionsBuilder } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oapp/libs/OptionsBuilder.sol";
import "forge-std/StdJson.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

abstract contract BaseL0FraxDVNScript is Script {
    using OptionsBuilder for bytes;
    using stdJson for string;
    using Strings for uint256;

    uint256 public dvnDeployerPK = vm.envUint("PK_DVN_DEPLOYER");

    /// @dev: required to be alphabetical to conform to https://book.getfoundry.sh/cheatcodes/parse-json
    struct L0DVNConfig {
        string RPC;
        address[] admins;
        uint256 chainid;
        uint32 eid;
        address[] messageLibs;
        address priceFeed;
        uint64 quorum;
        address[] signers;
        uint32 vid;
    }

    L0DVNConfig public dvnConfig;

    string public json;

    modifier broadcastAs(uint256 privateKey) {
        vm.startBroadcast(privateKey);
        _;
        vm.stopBroadcast();
    }

    function setUp() public virtual {
        // Set constants based on deployment chain id
        loadJsonConfig();
    }

    function loadJsonConfig() public virtual {
        string memory path = _getDVNConfigPath();
        json = vm.readFile(path);

        L0DVNConfig[] memory _dvnConfigs = abi.decode(json.parseRaw(_getNetworkEnv()), (L0DVNConfig[]));
        for (uint256 i = 0; i < _dvnConfigs.length; i++) {
            L0DVNConfig memory _dvnConfig = _dvnConfigs[i];
            if (_dvnConfig.chainid == block.chainid) {
                dvnConfig = _dvnConfig;
            }
        }
    }

    function _getDVNConfigPath() internal view virtual returns (string memory path) {
        string memory root = vm.projectRoot();
        // L0DVNConfig.json
        path = string.concat(root, "/scripts/L0DVNConfig.json");
    }

    function _getNetworkEnv() internal pure virtual returns (string memory);

    function run() public virtual {
        deploySource();
    }

    function deploySource() public virtual {
        // deployFraxDVNUpgradeablesAndProxies();
        deployFraxDVN();
        // TODO : implement the function to check all
        // six frax assets are deployed or not
        // postDeployChecks();
    }

    function deployFraxDVN() public virtual broadcastAs(dvnDeployerPK) {
        FraxDVN _dvn = new FraxDVN(
            dvnConfig.eid,
            dvnConfig.vid,
            dvnConfig.messageLibs,
            dvnConfig.priceFeed,
            dvnConfig.signers,
            dvnConfig.quorum,
            dvnConfig.admins
        );
    }
}
