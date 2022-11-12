// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import {Variables} from "./Variables.sol";
import "./Errors.sol";

abstract contract Modifiers is Variables {
    /// @notice checks if msg.sender is an allowed feeSetter
    modifier onlyAllowedFeeSetter() {
        if (allowedFeeSetters[msg.sender] != true) {
            revert ExcessWithdrawHandler__Unauthorized();
        }
        _;
    }

    /// @notice checks if msg.sender is an allowed fulfiller
    modifier onlyAllowedFulfiller() {
        if (allowedFulfillers[msg.sender] != true) {
            revert ExcessWithdrawHandler__Unauthorized();
        }
        _;
    }

    /// @notice checks that a percentage is higher than or equal the current penaltyFeePercentage
    modifier isGtePenaltyFee(uint32 _maxPenaltyFeePercentage) {
        if (_maxPenaltyFeePercentage < penaltyFeePercentage) {
            revert ExcessWithdrawHandler__InvalidParams();
        }
        _;
    }
}
