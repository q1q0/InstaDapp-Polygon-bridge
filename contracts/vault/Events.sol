// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

contract Events {
    /// @notice emitted whenever a user withdraws assets and a fee is collected
    event WithdrawFeeCollected(address indexed payer, uint256 indexed fee);

    /// @notice emitted whenever fromMainnet is executed
    event FromMainnet(
        address indexed bridgeAddress,
        uint256 indexed amountMoved
    );

    /// @notice emitted whenever toMainnet is executed
    event ToMainnet(address indexed bridgeAddress, uint256 indexed amountMoved);
}
