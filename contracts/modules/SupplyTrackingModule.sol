pragma solidity ^0.8.0;

/**
 * @title SupplyTrackingModule
 * @notice Contract module to track circulating supply of an OFT across all destination chains
*/
abstract contract SupplyTrackingModule {

    struct SupplyTrackingStorage {
        uint256 sumTotalTransferFrom;
        uint256 sumTotalTransferTo;
        mapping(uint32 eid => uint256 amount) totalTransferFrom;
        mapping(uint32 eid => uint256 amount) totalTransferTo;
    }

    /// @dev keccak256(abi.encode(uint256(keccak256("frax.storage.SupplyTrackingModule")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant SupplyTrackingStorageLocation = 0x419276e85a544278a01dfd89b03028910afb9d04e0edf9a7b0d319d61e5bb200;

    function _getSupplyTrackingStorage() private pure returns (SupplyTrackingStorage storage $) {
        assembly {
            $.slot := SupplyTrackingStorageLocation
        }
    }

    // Setters

    function _addToTotalTransferFrom(uint32 _eid, uint256 _amount) internal {
        SupplyTrackingStorage storage $ = _getSupplyTrackingStorage();
        $.totalTransferFrom[_eid] += _amount;
        $.sumTotalTransferFrom += _amount;
    }

    function _addToTotalTransferTo(uint32 _eid, uint256 _amount) internal {
        SupplyTrackingStorage storage $ = _getSupplyTrackingStorage();
        $.totalTransferTo[_eid] += _amount;
        $.sumTotalTransferTo += _amount;
    }

    // Views

    /// @notice Get the total amount transferred to all target chains
    /// @return The total amount transferred to all target chains
    function sumTotalTransferTo() external view returns (uint256) {
        SupplyTrackingStorage storage $ = _getSupplyTrackingStorage();
        return $.sumTotalTransferTo;
    }

    /// @notice Get the total amount transferred from all target chains
    /// @return The total amount transferred from all target chains
    function sumTotalTransferFrom() external view returns (uint256) {
        SupplyTrackingStorage storage $ = _getSupplyTrackingStorage();
        return $.sumTotalTransferFrom;
    }

    /// @notice Get the total amount transferred to a given target chain
    /// @param _eid The target chain EID
    /// @return The total amount transferred to the target chain
    function totalTransferFrom(uint32 _eid) external view returns (uint256) {
        SupplyTrackingStorage storage $ = _getSupplyTrackingStorage();
        return $.totalTransferFrom[_eid];
    }

    /// @notice Get the total amount transferred from a given target chain to this chain
    /// @param _eid The target chain EID
    /// @return The total amount transferred from the target chain to this chain
    function totalTransferTo(uint32 _eid) external view returns (uint256) {
        SupplyTrackingStorage storage $ = _getSupplyTrackingStorage();
        return $.totalTransferTo[_eid];
    }
}