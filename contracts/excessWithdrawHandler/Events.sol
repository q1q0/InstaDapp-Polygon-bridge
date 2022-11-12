// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

contract Events {
    /// @notice emitted when owner requests an excess withdraw for receiver
    event ExcessWithdrawRequested(
        address indexed owner,
        address indexed receiver,
        uint256 shares,
        uint256 assets
    );

    /// @notice emitted when anyone triggers an execute withdraw to receiver
    event ExcessWithdrawExecuted(
        address indexed receiver,
        uint256 shares,
        uint256 assets
    );

    /// @notice emitted when a feeSetter updates the current penalty fee
    event PenaltyFeeSet(uint32 penaltyFeePercentage);

    /// @notice emitted whenever fromVault is executed
    event FromVault(uint256 indexed amountMoved, uint256 indexed sharesBurned);
}
