// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { OFTUpgradeable } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/OFTUpgradeable.sol";
import { IOFT } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";
import { SerializedTx } from "scripts/SafeBatchSerialize.sol";

// Setup destination with a hub model vs. a spoke model where the only peer is Fraxtal
abstract contract SetupDestinationFraxOFTFraxtalHub is DeployFraxOFTProtocol {
    L0Config[] public tempConfigs;
    SerializedTx[] public serializedTxsWfrax;
    SerializedTx[] public serializedTxssfrxUsd;
    SerializedTx[] public serializedTxssfrxEth;
    SerializedTx[] public serializedTxsfrxUsd;
    SerializedTx[] public serializedTxsfrxEth;
    SerializedTx[] public serializedTxsfpi;

    function run() public virtual override {
        require(
            OFTUpgradeable(wfraxOft).isPeer(30255, addressToBytes32(fraxtalFraxLockbox)),
            "fraxtal is not connected to wfraxOft"
        );
        require(
            OFTUpgradeable(sfrxUsdOft).isPeer(30255, addressToBytes32(fraxtalSFrxUsdLockbox)),
            "fraxtal is not connected to sfrxusdoft"
        );
        require(
            OFTUpgradeable(sfrxEthOft).isPeer(30255, addressToBytes32(fraxtalSFrxEthLockbox)),
            "fraxtal is not connected to sfrxethoft"
        );
        require(
            OFTUpgradeable(frxUsdOft).isPeer(30255, addressToBytes32(fraxtalFrxUsdLockbox)),
            "frxusdoft is not connected to fraxtal"
        );
        require(
            OFTUpgradeable(frxEthOft).isPeer(30255, addressToBytes32(fraxtalFrxEthLockbox)),
            "frxethoft is not connected to fraxtal"
        );
        require(
            OFTUpgradeable(fpiOft).isPeer(30255, addressToBytes32(fraxtalFpiLockbox)),
            "frxethoft is not connected to fraxtal"
        );

        for (uint256 i; i < proxyConfigs.length; i++) {
            // Set up destinations for Fraxtal lockboxes only
            if (proxyConfigs[i].chainid == 252 || proxyConfigs[i].chainid == broadcastConfig.chainid) {
                tempConfigs.push(proxyConfigs[i]);
            }
        }

        require(tempConfigs.length == 2, "Incorrect tempConfigs array");

        delete proxyConfigs;
        for (uint256 i = 0; i < tempConfigs.length; i++) {
            proxyConfigs.push(tempConfigs[i]);
        }
        delete tempConfigs;

        setupDestinations();
    }

    modifier simulateAndWriteTxs(L0Config memory _simulateConfig) override {
        // Clear out any previous txs
        delete enforcedOptionParams;
        delete serializedTxs;

        // store for later referencing
        simulateConfig = _simulateConfig;

        // Use the correct OFT addresses given the chain we're simulating
        _populateConnectedOfts();

        // Simulate fork as delegate (aka msig) as we're crafting txs within the modified function
        vm.createSelectFork(_simulateConfig.RPC);
        vm.startPrank(_simulateConfig.delegate);
        _;
        vm.stopPrank();

        // serialized txs were pushed within the modified function- write to storage
        if (serializedTxsWfrax.length > 0) {
            new SafeTxUtil().writeTxs(serializedTxsWfrax, string.concat(filename(), "-wfrax.json"));
        }
        if (serializedTxssfrxUsd.length > 0) {
            new SafeTxUtil().writeTxs(serializedTxssfrxUsd, string.concat(filename(), "-sfrxusd.json"));
        }
        if (serializedTxssfrxEth.length > 0) {
            new SafeTxUtil().writeTxs(serializedTxssfrxEth, string.concat(filename(), "-sfrxeth.json"));
        }
        if (serializedTxsfrxUsd.length > 0) {
            new SafeTxUtil().writeTxs(serializedTxsfrxUsd, string.concat(filename(), "-frxusd.json"));
        }
        if (serializedTxsfrxEth.length > 0) {
            new SafeTxUtil().writeTxs(serializedTxsfrxEth, string.concat(filename(), "-frxeth.json"));
        }
        if (serializedTxsfpi.length > 0) {
            new SafeTxUtil().writeTxs(serializedTxsfpi, string.concat(filename(), "-fpi.json"));
        }
    }

    function pushSerializedTx(string memory _name, address _to, uint256 _value, bytes memory _data) public virtual override {
        string memory _tokenName;
        bytes memory sliced = new bytes(_data.length - 4);
        for (uint256 i = 0; i < sliced.length; i++) {
            sliced[i] = _data[i + 4];
        }

        SerializedTx memory _txObj = SerializedTx({ name: _name, to: _to, value: _value, data: _data });

        if (isStringEqual(_name, "setPeer") || isStringEqual(_name, "setEnforcedOptions")) {
            address _token = IOFT(_to).token();
            _tokenName = IERC20Metadata(_token).symbol();
        } else if (isStringEqual(_name, "setSendLibrary")) {
            (address _oapp, , ) = abi.decode(sliced, (address, uint32, address));
            address _token = IOFT(_oapp).token();
            _tokenName = IERC20Metadata(_token).symbol();
        } else if (isStringEqual(_name, "setReceiveLibrary")) {
            (address _oapp, , , ) = abi.decode(sliced, (address, uint32, address, uint256));
            address _token = IOFT(_oapp).token();
            _tokenName = IERC20Metadata(_token).symbol();
        } else if (isStringEqual(_name, "setConfig")) {
            (address _oapp, , ) = abi.decode(sliced, (address, address, bytes));
            address _token = IOFT(_oapp).token();
            _tokenName = IERC20Metadata(_token).symbol();
        } else {
            revert("Transaction name not found");
        }

        if (isStringEqual(_tokenName, "frxUSD")) {
            serializedTxsfrxUsd.push(_txObj);
        } else if (isStringEqual(_tokenName, "sfrxUSD")) {
            serializedTxssfrxUsd.push(_txObj);
        } else if (isStringEqual(_tokenName, "frxETH")) {
            serializedTxsfrxEth.push(_txObj);
        } else if (isStringEqual(_tokenName, "sfrxETH")) {
            serializedTxssfrxEth.push(_txObj);
        } else if (isStringEqual(_tokenName, "WFRAX")) {
            serializedTxsWfrax.push(_txObj);
        } else if (isStringEqual(_tokenName, "FPI")) {
            serializedTxsfpi.push(_txObj);
        } else {
            revert("TokenName name not found");
        }
    }
}
