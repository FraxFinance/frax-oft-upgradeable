// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { Test } from "forge-std/Test.sol";
import { ITIP20 } from "tempo-std/interfaces/ITIP20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { MessagingFee, MessagingReceipt, MessagingParams } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

/// @notice Mock LZEndpointDollar for testing - wraps whitelisted stablecoins into a synthetic USD token
contract MockLZEndpointDollar {
    string public name = "LZ Endpoint Dollar";
    string public symbol = "LZUSD";
    uint8 public constant decimals = 6;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => bool) private _whitelistedTokens;
    address[] private _whitelistedTokensList;
    uint256 public totalSupply;

    address public owner;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event TokenWhitelisted(address indexed token, bool whitelisted);
    event TokenWrapped(address indexed token, address indexed from, address indexed to, uint256 amount);
    event TokenUnwrapped(address indexed token, address indexed from, address indexed to, uint256 amount);

    constructor() {
        owner = msg.sender;
    }

    function whitelistToken(address token) external {
        require(msg.sender == owner, "Only owner");
        require(!_whitelistedTokens[token], "Already whitelisted");
        _whitelistedTokens[token] = true;
        _whitelistedTokensList.push(token);
        emit TokenWhitelisted(token, true);
    }

    function isWhitelistedToken(address token) external view returns (bool) {
        return _whitelistedTokens[token];
    }

    function getWhitelistedTokens() external view returns (address[] memory) {
        return _whitelistedTokensList;
    }

    function wrap(address token, address to, uint256 amount) external {
        require(_whitelistedTokens[token], "Not whitelisted");
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
        emit TokenWrapped(token, msg.sender, to, amount);
    }

    function unwrap(address token, address to, uint256 amount) external {
        require(_whitelistedTokens[token], "Not whitelisted");
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        totalSupply -= amount;
        IERC20(token).transfer(to, amount);
        emit Transfer(msg.sender, address(0), amount);
        emit TokenUnwrapped(token, msg.sender, to, amount);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
}

/// @notice Minimal OZ4-compatible EndpointV2Alt mock (ERC20 native) for tests
contract EndpointV2AltMockOz4 {
    uint32 public immutable eid;
    uint64 public nonce;
    uint256 public lastNativeFee;
    mapping(address => address) public delegates;

    MockLZEndpointDollar public immutable nativeErc20;

    constructor(uint32 _eid, address _altToken) {
        eid = _eid;
        // Deploy MockLZEndpointDollar and whitelist the provided token
        nativeErc20 = new MockLZEndpointDollar();
        nativeErc20.whitelistToken(_altToken);
    }

    function setDelegate(address _delegate) external {
        delegates[msg.sender] = _delegate;
    }

    function send(MessagingParams calldata, address) external payable returns (MessagingReceipt memory) {
        require(msg.value == 0, "LZ_OnlyAltToken");
        nonce++;
        lastNativeFee = nativeErc20.balanceOf(address(this));
        return
            MessagingReceipt({
                guid: bytes32(uint256(nonce)),
                nonce: nonce,
                fee: MessagingFee({ nativeFee: lastNativeFee, lzTokenFee: 0 })
            });
    }

    /// @dev Mock quote function returning a fixed nativeFee for testing
    uint256 public mockNativeFee = 10e6;

    function setMockNativeFee(uint256 _fee) external {
        mockNativeFee = _fee;
    }

    function quote(MessagingParams calldata, address) external view returns (MessagingFee memory) {
        return MessagingFee({ nativeFee: mockNativeFee, lzTokenFee: 0 });
    }

    function nativeToken() external view returns (address) {
        return address(nativeErc20);
    }
}

/// @notice Lightweight helper to deploy alt endpoints without touching prod contracts
contract LZTestHelperOz4 is Test {
    function createAltEndpoint(uint32 _eid, address _altToken) public returns (EndpointV2AltMockOz4 ep) {
        ep = new EndpointV2AltMockOz4(_eid, _altToken);
    }
}
