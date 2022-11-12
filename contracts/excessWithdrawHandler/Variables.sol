// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;
import {ILiteVault} from "../vault/Interfaces.sol";

contract Variables {
    struct ExcessWithdraw {
        // fee to cover any cost for e.g. unwinding, slippages, deleveraging etc. on mainnet
        // set and updated by bot according to observations, as an absolute amount
        uint256 penaltyFee;
        // amount of locked vault tokens (shares) until withdraw is executed
        uint256 shares;
        // maximum penaltyFee for the withdraw as set by user as an absolute amount
        uint256 maxPenaltyFee;
        // receiver of the tokens at execute withdraw time
        address receiver;
    }

    /***********************************|
    |           STATE VARIABLES         |
    |__________________________________*/

    /// @notice the LiteVault that this ExcessWithdrawHandler interacts with
    ILiteVault public immutable vault;

    /// @notice the total amount of assets (raw) that is currently queued for excess withdraw
    /// @dev useful for the off-chain bot to keep the vault balance high enough
    /// balance in vault should be ExcessWithdrawHandler.queuedAmount + LiteVault.minimumThreshold
    /// This is inclusive of any withdraw fee
    uint256 public queuedAmount;

    /// @notice maps a user address to all the ids for excess withdraws this user has currently queued up
    /// @dev all queued withdraw ids for a user can be fetched through this mapping and fed into the getter of excessWithdraws mapping
    mapping(address => bytes32[]) public excessWithdrawIds;

    /// @notice maps an excess withdraw id to the data struct for that ExcessWithdraw request
    mapping(bytes32 => ExcessWithdraw) public excessWithdraws;

    /// @notice list of addresses that are allowed to set the penalty fees for ExcessWithdraws
    /// modifiable by owner
    mapping(address => bool) public allowedFeeSetters;

    /***********************************|
    |           CONSTRUCTOR             |
    |__________________________________*/

    constructor(ILiteVault _vault) {
        vault = _vault;
    }
}
