// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { Test } from "forge-std/Test.sol";
import { ITIP20 } from "tempo-std/interfaces/ITIP20.sol";
import { ITIP20Factory } from "tempo-std/interfaces/ITIP20Factory.sol";
import { ITIP20RolesAuth } from "tempo-std/interfaces/ITIP20RolesAuth.sol";
import { StdPrecompiles } from "tempo-std/StdPrecompiles.sol";
import { StdTokens } from "tempo-std/StdTokens.sol";

/// @title TempoTestHelpers
/// @notice Shared helper functions for Tempo-based tests
abstract contract TempoTestHelpers is Test {
    
    // ---------------------------------------------------
    // TIP20 Token Creation Helpers
    // ---------------------------------------------------
    
    /// @dev Create a TIP20 token via factory with issuer role granted to caller
    /// @param name Token name
    /// @param symbol Token symbol  
    /// @param salt Salt for deterministic deployment
    function _createTIP20(
        string memory name,
        string memory symbol,
        bytes32 salt
    ) internal returns (ITIP20 token) {
        token = ITIP20(
            ITIP20Factory(address(StdPrecompiles.TIP20_FACTORY)).createToken(
                name,
                symbol,
                "USD",
                ITIP20(StdTokens.PATH_USD_ADDRESS),
                address(this),
                salt
            )
        );
        
        // Grant ISSUER_ROLE to test contract for minting
        ITIP20RolesAuth(address(token)).grantRole(token.ISSUER_ROLE(), address(this));
    }
    
    /// @dev Create a TIP20 token with a DEX pair
    function _createTIP20WithDexPair(
        string memory name,
        string memory symbol,
        bytes32 salt
    ) internal returns (ITIP20 token) {
        token = _createTIP20(name, symbol, salt);
        StdPrecompiles.STABLECOIN_DEX.createPair(address(token));
    }
    
    // ---------------------------------------------------
    // DEX Liquidity Helpers
    // ---------------------------------------------------
    
    /// @dev Add liquidity to DEX by placing both bid and ask orders
    /// @notice Places bid order (PATH_USD for token) AND ask order (token for PATH_USD)
    ///         This allows both directions of swaps to work in tests.
    ///         Caller must have PATH_USD issuer role granted before calling.
    function _addDexLiquidity(address token, uint256 amount) internal {
        address liquidityProvider = address(0x1111);
        
        // Mint both PATH_USD and the token for the liquidity provider
        ITIP20(StdTokens.PATH_USD_ADDRESS).mint(liquidityProvider, amount * 2);
        ITIP20(token).mint(liquidityProvider, amount * 2);
        
        vm.startPrank(liquidityProvider);
        
        // Place bid order: buy token with PATH_USD (allows selling token for PATH_USD)
        ITIP20(StdTokens.PATH_USD_ADDRESS).approve(address(StdPrecompiles.STABLECOIN_DEX), amount * 2);
        StdPrecompiles.STABLECOIN_DEX.place(token, uint128(amount), true, 0);
        
        // Place ask order: sell token for PATH_USD (allows buying token with PATH_USD)
        ITIP20(token).approve(address(StdPrecompiles.STABLECOIN_DEX), amount * 2);
        StdPrecompiles.STABLECOIN_DEX.place(token, uint128(amount), false, 0);
        
        vm.stopPrank();
    }
    
    // ---------------------------------------------------
    // TIP Fee Manager Helpers
    // ---------------------------------------------------
    
    /// @dev Set user's gas token via TIP_FEE_MANAGER
    function _setUserGasToken(address user, address token) internal {
        vm.prank(user);
        StdPrecompiles.TIP_FEE_MANAGER.setUserToken(token);
    }
    
    // ---------------------------------------------------
    // Role Management Helpers
    // ---------------------------------------------------
    
    /// @dev Grant ISSUER_ROLE on a TIP20 token to an address
    function _grantIssuerRole(address token, address account) internal {
        bytes32 issuerRole = ITIP20(token).ISSUER_ROLE();
        ITIP20RolesAuth(token).grantRole(issuerRole, account);
    }
    
    /// @dev Grant PATH_USD ISSUER_ROLE to an address
    function _grantPathUsdIssuerRole(address account) internal {
        _grantIssuerRole(StdTokens.PATH_USD_ADDRESS, account);
    }
}
