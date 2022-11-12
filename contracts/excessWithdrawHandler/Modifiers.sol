// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import {Variables} from "./Variables.sol";
import "./Errors.sol";

abstract contract Modifiers is Variables {
    /// @notice checks if msg.sender is an allowed feeSetter
    modifier onlyAllowedFeeSetter() {
        if (!allowedFeeSetters[msg.sender]) {
            revert ExcessWithdrawHandler__Unauthorized();
        }
        _;
    }

    modifier isGtePenaltyFee(uint32 _maxPenaltyFeePercentage) {
        if (_maxPenaltyFeePercentage < penaltyFeePercentage) {
            revert ExcessWithdrawHandler__InvalidParams();
        }
        _;
    }
}
