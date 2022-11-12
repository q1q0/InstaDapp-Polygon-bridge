// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;
import {ILiteVault} from "../vault/Interfaces.sol";

contract Variables {
    /***********************************|
    |             CONSTANTS             |
    |__________________________________*/

    /// @notice upper limit of percentage values
    /// with 1e6 as base for percentage values 1e8 is 100%
    uint32 public constant maximumPercentageRange = 1e8;

    /***********************************|
    |           STATE VARIABLES         |
    |__________________________________*/

    /// @dev tightly pack uint32 (4 bytes) and address (20 bytes) into one storage slot

    /// @notice the current penaltyFeePercentage applied to any withdraw amount request
    /// this fee is to cover any cost for e.g. unwinding, slippages, deleveraging etc. on mainnet
    /// set and updated by bot (allowedFeeSetter) according to observations, as an absolute amount
    uint32 penaltyFeePercentage; // 4 bytes

    /// @notice the LiteVault that this ExcessWithdrawHandler interacts with
    ILiteVault public immutable vault; // 20 bytes

    /// @notice queued withdraw amounts per receiver, the penaltyFee already subtracted
    mapping(address => uint256) queuedWithdrawAmounts;

    /// @notice the total amount of assets (raw) that is currently queued for excess withdraw, already subtracted the penaltyFee.
    /// @dev useful for the off-chain bot to keep the vault balance high enough
    /// balance in vault should be ExcessWithdrawHandler.queuedAmount + LiteVault.minimumThreshold
    uint256 public totalQueuedAmount;

    /// @notice list of addresses that are allowed to set the penalty fee
    /// modifiable by owner
    mapping(address => bool) public allowedFeeSetters;

    /// @notice list of addresses that are allowed to fulfill withdraws by executing fromVault calls
    /// modifiable by owner
    mapping(address => bool) public allowedFulfillers;

    /***********************************|
    |           CONSTRUCTOR             |
    |__________________________________*/

    constructor(ILiteVault _vault) {
        vault = _vault;
    }
}
