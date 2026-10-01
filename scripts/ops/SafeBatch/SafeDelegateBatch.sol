// SPDX-License-Identifier: ISC
pragma solidity ^0.8.22;

/// @notice Base for a Safe batch whose calls live in deployed, verified source instead of calldata.
///
///         Why: hardware wallets cannot sign the multi-kilobyte EIP-712 `data` a MultiSend batch
///         produces, so any operation that needs many admin calls is shipped as a contract with the
///         calls hardcoded. The Safe queues ONE transaction — `execute()`, four bytes — with
///         operation = 1 (DELEGATECALL), the same mechanism the Safe uses for MultiSend itself, so
///         every inner call is made by the Safe and passes `onlyOwner` / `onlyDelegate` checks.
///         Signers review the verified source, not hex.
///
///         Rules for subclasses, because their code runs inside the Safe's storage context:
///           - constants only: no storage variables, no constructor, no immutables;
///           - no selfdestruct, delegatecall, callcode or create;
///           - typed interface calls with named constants, so reviewers read Solidity;
///           - pin the Safe via `safe()`. `execute()` reverts anywhere else, and a direct call
///             would not carry the Safe's authority anyway;
///           - let inner reverts bubble: with safeTxGas == 0 the Safe turns them into GS013, so the
///             batch is all-or-nothing and a failure never consumes a nonce.
///
///         Operations: deploy + verify, then EXTRACT — the Safe signing UI refuses operation = 1 to
///         untrusted targets, so a batch is never queued directly. It is the reviewable spec:
///         scripts/ops/DeprecateChain/DeprecateFromSafeBatch.s.sol replays it through the real Safe
///         on a fork and writes its calls as per-route Tx Builder payloads, and a fork test proves
///         those payloads change exactly the storage this contract would, slot for slot.
///
///         Test with SafeBatchTest in test/foundry/scripts/ops/SafeBatch/ (real Safe
///         execTransaction on a fork, before/after state, replay -> GS013, opcode scan).
abstract contract SafeDelegateBatch {
    /// @notice The only Safe this batch may run in.
    function safe() public pure virtual returns (address);

    /// @notice The only chain this batch may run on (checked by the extractor and the tests).
    function chainId() public pure virtual returns (uint256);

    function execute() external {
        require(address(this) == safe(), "SafeDelegateBatch: must be delegatecalled by the pinned Safe");
        _run();
    }

    /// @dev The hardcoded calls, in order.
    function _run() internal virtual;
}
