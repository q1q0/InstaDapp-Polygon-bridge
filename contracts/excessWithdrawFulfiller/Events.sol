// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

contract Events {
    /// @notice emitted whenever fulfillExcessWithdraw is executed
    event ExcessWithdrawFulfilled(uint256 indexed amountMoved);
}
