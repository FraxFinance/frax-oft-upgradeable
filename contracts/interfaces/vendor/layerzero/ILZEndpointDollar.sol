// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title ILZEndpointDollar
 * @notice Interface for the LZEndpointDollar contract - an upgradeable ERC-20 that wraps/unwraps whitelisted USD stablecoins.
 */
interface ILZEndpointDollar {
    /**
     * @notice Wraps underlying tokens into LZEndpointDollar tokens.
     * @dev Only whitelisted tokens can be wrapped.
     * @param _token The underlying token to wrap.
     * @param _to The address to mint wrapped tokens to.
     * @param _amount The amount of tokens to wrap.
     */
    function wrap(address _token, address _to, uint256 _amount) external;

    /**
     * @notice Unwraps LZEndpointDollar tokens back to underlying tokens.
     * @dev Only whitelisted tokens can be unwrapped.
     * @param _token The underlying token to receive.
     * @param _to The address to send underlying tokens to.
     * @param _amount The amount of tokens to unwrap.
     */
    function unwrap(address _token, address _to, uint256 _amount) external;

    /**
     * @notice Checks if a token is whitelisted.
     * @param _token The address of the token to check.
     * @return isWhitelisted True if the token is whitelisted.
     */
    function isWhitelistedToken(address _token) external view returns (bool isWhitelisted);

    /**
     * @notice Returns the number of decimals used by the token.
     * @return The number of decimals.
     */
    function decimals() external view returns (uint8);

    /**
     * @notice Returns the list of whitelisted tokens.
     * @dev The whitelisted tokens array is unbounded.
     * @return An array of addresses representing the whitelisted tokens.
     */
    function getWhitelistedTokens() external view returns (address[] memory);
}
