// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import { Script } from "forge-std/Script.sol";
import "forge-std/StdJson.sol";
import "frax-template/src/Constants.sol";

import { SerializedTx, SafeTxUtil } from "scripts/SafeBatchSerialize.sol";
import { FraxOFTUpgradeable } from "contracts/FraxOFTUpgradeable.sol";
import { ImplementationMock } from "contracts/mocks/ImplementationMock.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { MessagingParams, MessagingReceipt, Origin } from "@fraxfinance/layerzero-v2-upgradeable/protocol/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { EndpointV2 } from "@fraxfinance/layerzero-v2-upgradeable/protocol/contracts/EndpointV2.sol";
import { SetConfigParam, IMessageLibManager} from "@fraxfinance/layerzero-v2-upgradeable/protocol/contracts/interfaces/IMessageLibManager.sol";

import { OptionsBuilder } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oapp/libs/OptionsBuilder.sol";
import { EnforcedOptionParam, IOAppOptionsType3 } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oapp/interfaces/IOAppOptionsType3.sol";
import { IOAppCore } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oapp/interfaces/IOAppCore.sol";
import { SendParam, OFTReceipt, MessagingFee, IOFT } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";

import { ProxyAdmin, TransparentUpgradeableProxy } from "@fraxfinance/layerzero-v2-upgradeable/messagelib/contracts/upgradeable/proxy/ProxyAdmin.sol";
import { UlnConfig } from "@fraxfinance/layerzero-v2-upgradeable/messagelib/contracts/uln/UlnBase.sol";
import { Constant } from "@fraxfinance/layerzero-v2-upgradeable/messagelib/test/util/Constant.sol";
    
contract BaseL0Script is Script {

    using OptionsBuilder for bytes;
    using stdJson for string;
    using Strings for uint256;

    uint256 public oftDeployerPK = vm.envUint("PK_OFT_DEPLOYER");
    uint256 public configDeployerPK = vm.envUint("PK_CONFIG_DEPLOYER");
    uint256 public senderDeployerPK = vm.envUint("PK_SENDER_DEPLOYER");

    /// @dev: required to be alphabetical to conform to https://book.getfoundry.sh/cheatcodes/parse-json
    struct L0Config {
        string RPC;
        uint256 chainid;
        address delegate;
        address dvn1;
        address dvn2;
        uint256 eid;
        address endpoint;
        address receiveLib302;
        address sendLib302;
    }
    L0Config[] public legacyConfigs;
    L0Config[] public proxyConfigs;
    L0Config[] public configs; // legacy & proxy configs
    L0Config public activeConfig; // config of actively-connected (broadcasting) chain
    L0Config[] public activeConfigArray; // length of 1 of activeConfig
    bool public activeLegacy; // true if we're broadcasting to legacy chain

    // Mock implementation used to enable pre-determinsitic proxy creation
    address public implementationMock;

    // Deployed proxies
    address public proxyAdmin;
    address public fxsOft;
    address public sFraxOft;
    address public sfrxEthOft;
    address public fraxOft;
    uint256 public numOfts;

    // 1:1 match between these arrays for setting peers
    address[] public legacyOfts;
    address[] public proxyOfts;

    EnforcedOptionParam[] public enforcedOptionsParams;

    SetConfigParam[] public setConfigParams;

    SerializedTx[] serializedTxs;

    uint256 public chainid;

    function version() public virtual pure returns (uint256, uint256, uint256) {
        return (1, 0, 1);
    }

    modifier broadcastAs(uint256 privateKey) {
        vm.startBroadcast(privateKey);
        _;
        vm.stopBroadcast();
    }


    modifier simulateAndWriteTxs(
        L0Config memory _config
    ) virtual {
        // Clear out any previously serialized txs
        delete serializedTxs;

        vm.createSelectFork(_config.RPC);
        chainid = _config.chainid;
        vm.startPrank(_config.delegate);
        _;
        vm.stopPrank();

        // create filename and save
        string memory root = vm.projectRoot();
        root = string.concat(root, '/scripts/DeployFraxOFTProtocol/txs/');
        string memory filename = string.concat(activeConfig.chainid.toString(), "-");
        filename = string.concat(filename, _config.chainid.toString());
        filename = string.concat(filename, ".json");
        
        new SafeTxUtil().writeTxs(serializedTxs, string.concat(root, filename));
    }


    function setUp() public virtual {
        // Set constants based on deployment chain id
        chainid = block.chainid;
        loadJsonConfig();

        /// @dev: this array maintains the same token order as proxyOfts and the addrs are confirmed on eth mainnet, blast, base, and metis.
        legacyOfts.push(0x23432452B720C80553458496D4D9d7C5003280d0); // fxs
        legacyOfts.push(0xe4796cCB6bB5DE2290C417Ac337F2b66CA2E770E); // sFRAX
        legacyOfts.push(0x1f55a02A049033E3419a8E2975cF3F572F4e6E9A); // sfrxETH
        legacyOfts.push(0x909DBdE1eBE906Af95660033e478D59EFe831fED); // FRAX
        numOfts = legacyOfts.length;

        // aray of semi-pre-determined upgradeable OFTs
        proxyOfts.push(0x64445f0aecC51E94aD52d8AC56b7190e764E561a); // fxs
        proxyOfts.push(0x5Bff88cA1442c2496f7E475E9e7786383Bc070c0); // sFRAX
        proxyOfts.push(0x3Ec3849C33291a9eF4c5dB86De593EB4A37fDe45); // sfrxETH
        proxyOfts.push(0x80Eede496655FB9047dd39d9f418d5483ED600df); // FRAX
    }

    function loadJsonConfig() public {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts/L0Config.json");
        string memory json = vm.readFile(path);
        
        // load and write to persistent storage

        // legacy
        L0Config[] memory legacyConfigs_ = abi.decode(json.parseRaw(".Legacy"), (L0Config[]));
        for (uint256 i=0; i<legacyConfigs_.length; i++) {
            L0Config memory config_ = legacyConfigs_[i];
            if (config_.chainid == chainid) {
                activeConfig = config_;
                activeConfigArray.push(config_);
                activeLegacy = true;
            }
            legacyConfigs.push(config_);
            configs.push(config_);
        }

        // proxy (active deployment loaded as activeConfig)
        L0Config[] memory proxyConfigs_ = abi.decode(json.parseRaw(".Proxy"), (L0Config[]));
        for (uint256 i=0; i<proxyConfigs_.length; i++) {
            L0Config memory config_ = proxyConfigs_[i];
            if (config_.chainid == chainid) {
                activeConfig = config_;
                activeConfigArray.push(config_);
            }
            proxyConfigs.push(config_);
            configs.push(config_);
        }
        require(activeConfig.chainid != 0, "L0Config for source not loaded");
        require(activeConfigArray.length == 1, "ActiveConfigArray does not equal 1");
    }

    function isStringEqual(string memory _a, string memory _b) public pure returns (bool) {
        return keccak256(abi.encodePacked(_a)) == keccak256(abi.encodePacked(_b));
    }

    function addressToBytes32(address _addr) public pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }

}