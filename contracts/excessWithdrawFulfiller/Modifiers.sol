// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import {Variables} from "./Variables.sol";
import "./Errors.sol";

abstract contract Modifiers is Variables {
    /// @notice checks if msg.sender is an allowed rebalancer on vault
    modifier onlyAllowedVaultRebalancer() {
        if (vault.allowedRebalancers(msg.sender) != true) {
            revert ExcessWithdrawFulfiller__Unauthorized();
        }
        _;
    }

    /// @notice checks if msg.sender is an allowed fulfiller on excessWithdrawHandler
    modifier onlyAllowedWithdrawHandlerFulfiller() {
        if (withdrawHandler.allowedFulfiller(msg.sender) != true) {
            revert ExcessWithdrawFulfiller__Unauthorized();
        }
        _;
    }
}
