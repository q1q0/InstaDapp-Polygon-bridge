// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import {ILiteVault} from "../vault/Interfaces.sol";
import {IExcessWithdrawHandler} from "../excessWithdrawHandler/Interfaces.sol";
import {Variables} from "./Variables.sol";
import {Events} from "./Events.sol";
import {Modifiers} from "./Modifiers.sol";
import "./Errors.sol";

/// @title ExcessWithdrawFulfiller
/// @notice fulfills queued excess withdraws by executing fromMainnet on vault and fromVault on excessWithdrawHandler
/// in a single transaction to ensure funds go directly to the withdrawHandler.
/// @dev this contract must be an authorized rebalancer in vault and an authorized fulfiller in the withdrawHandler
contract ExcessWithdrawFulfiller is Variables, Events, Modifiers {
    /***********************************|
    |           CONSTRUCTOR             |
    |__________________________________*/

    constructor(ILiteVault _vault, IExcessWithdrawHandler _withdrawHandler)
        Variables(_vault, _withdrawHandler)
    {}

    /****************************************************************|
    |        VAULT REBALANCER & WITHDRAW HANDLER FULFILLER ONLY      |
    |_______________________________________________________________*/

    /// @notice moves amountToMove from bridge to the vault and then from the vault to the withdrawHandler
    /// @dev executes fromMainnet on vault and fromVault on withdrawHandler
    ///      this contract address must be an authorized rebalancer in vault and an authorized fulfiller in the withdrawHandler
    /// @param _amountToMove (raw) amount of assets to transfer to bridge
    function fulfillExcessWithdraw(uint256 _amountToMove)
        external
        onlyAllowedWithdrawHandlerFulfiller
        onlyAllowedVaultRebalancer
    {
        vault.fromMainnet(_amountToMove);

        withdrawHandler.fromVault(_amountToMove);

        emit ExcessWithdrawFulfilled(_amountToMove);
    }
}
