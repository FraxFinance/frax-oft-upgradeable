// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

// resumes deployment as it froze after proxyAdmin deployment
// forge script scripts/ops/deploy/DeployMetis/1_ResumeDeploy.s.sol --rpc-url https://metis-mainnet.public.blastapi.io --broadcast
contract ResumeDeploy is DeployFraxOFTProtocol {
        function deployFraxOFTUpgradeablesAndProxies() broadcastAs(oftDeployerPK) public override {

        // Proxy admin (0x223a681fc5c5522c85C96157c0efA18cd6c5405c if predeterministic)
        // proxyAdmin = address(new FraxProxyAdmin(vm.addr(configDeployerPK)));
        proxyAdmin = 0x223a681fc5c5522c85C96157c0efA18cd6c5405c;

        // Implementation mock (0x8f1B9c1fd67136D525E14D96Efb3887a33f16250 if predeterministic)
        // implementationMock = address(new ImplementationMock());
        implementationMock = 0x8f1B9c1fd67136D525E14D96Efb3887a33f16250;

        // / @dev: follows deployment order of legacy OFTs found at https://etherscan.io/address/0xded884435f2db0169010b3c325e733df0038e51d
        // Deploy FXS
        (,fxsOft) = deployFraxOFTUpgradeableAndProxy({
            _name: "Frax Share",
            _symbol: "FXS"
        });

        // Deploy sfrxUSD
        (,sfrxUsdOft) = deployFraxOFTUpgradeableAndProxy({
            _name: "Staked Frax USD",
            _symbol: "sfrxUSD"
        });

        // Deploy sfrxETH
        (,sfrxEthOft) = deployFraxOFTUpgradeableAndProxy({
            _name: "Staked Frax Ether",
            _symbol: "sfrxETH"
        });

        // Deploy frxUSD
        (,frxUsdOft) = deployFraxOFTUpgradeableAndProxy({
            _name: "Frax USD",
            _symbol: "frxUSD"
        });

        // Deploy frxETH
        (,frxEthOft) = deployFraxOFTUpgradeableAndProxy({
            _name: "Frax Ether",
            _symbol: "frxETH"
        });

        // Deploy broken FPI
        deployFraxOFTUpgradeableAndProxy({
            _name: "Mock Frax Price Index",
            _symbol: "Mock FPI"
        });
        // pop off pushed proxy addr as it's the broken FPI
        proxyOfts.pop();

        // Deploy correct FPI
        (, fpiOft) = deployFraxOFTUpgradeableAndProxy({
            _name: "Frax Price Index",
            _symbol: "FPI"
        });

        require(fpiOft == proxyFpiOft, "FPI OFT address mismatch");
    }

}