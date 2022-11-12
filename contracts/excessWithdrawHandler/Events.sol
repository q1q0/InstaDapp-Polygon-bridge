// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

contract Events {
    /// @notice emitted when owner requests an excess withdraw for receiver
    event ExcessWithdrawRequested(
        bytes32 indexed excessWithdrawId,
        address indexed owner,
        address indexed receiver,
        uint256 shares,
        uint256 assets
    );

    /// @notice emitted when anyone triggers an execute withdraw to receiver
    event ExcessWithdrawExecuted(
        bytes32 indexed excessWithdrawId,
        address indexed receiver,
        uint256 shares,
        uint256 assets
    );

    /// @notice emitted when a feeSetter sets the penalty fee for an excess withdraw request
    event PenaltyFeeSet(bytes32 indexed excessWithdrawId, uint256 penaltyFee);
}
