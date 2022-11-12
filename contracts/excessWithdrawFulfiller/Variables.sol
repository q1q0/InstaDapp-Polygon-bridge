// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import {ILiteVault} from "../vault/Interfaces.sol";
import {IExcessWithdrawHandler} from "../excessWithdrawHandler/Interfaces.sol";

contract Variables {
    /***********************************|
    |           STATE VARIABLES         |
    |__________________________________*/

    /// @notice the LiteVault that this ExcessWithdrawFulfiller interacts with
    ILiteVault public immutable vault;

    /// @notice the ExcessWithdrawHandler that this ExcessWithdrawFulfiller interacts with
    IExcessWithdrawHandler public immutable withdrawHandler;

    /***********************************|
    |           CONSTRUCTOR             |
    |__________________________________*/

    constructor(ILiteVault _vault, IExcessWithdrawHandler _withdrawHandler) {
        vault = _vault;
        withdrawHandler = _withdrawHandler;
    }
}
