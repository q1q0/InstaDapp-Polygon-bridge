// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ILiteVault} from "./interfaces/ILiteVault.sol";

error ExcessWithdrawHandler__NotExcess();

/// @title ExcessWithdrawHandler
/// @notice Handles excess withdrawals for LiteVaults. I.e. users can request withdrawals here that surpass
/// the minimumThreshold from the LiteVault by locking their iTokens here
contract ExcessWithdrawHandler {
    using Math for uint256;
    using SafeERC20Upgradeable for ILiteVault;

    /***********************************|
    |             CONSTANTS             |
    |__________________________________*/

    /// @notice the percentage of the minimumThresholdAmount in the vault that a
    /// withdrawal amount has to exceed to count as ExcessWithdrawal.
    /// e.g. the minimumThresholdAmount in the vault is 100_000_000; the minimumExcessPercentage here is 90%;
    /// then a user would have to withdraw at least 90_000_000 to be able to queue an excess withdrawal
    uint256 public constant minimumExcessPercentage = 90_000_000; // percentage amount 90% with 1e6 decimals

    /***********************************|
    |           STATE VARIABLES         |
    |__________________________________*/

    /// @notice locked vault tokens (shares) for users until withdraw is executed
    mapping(address => uint256) lockedShares;

    /// @notice the LiteVault that this ExcessWithdrawHandler interacts with
    ILiteVault public immutable vault;

    /// @notice the total amount of assets (raw) that is currently queued for excess withdraw
    /// @dev useful for the off-chain bot to keep the vault balance high enough
    /// balance in vault should be ExcessWithdrawHandler.queuedAmount + LiteVault.minimumThreshold
    /// This is inclusive of any withdrawal fee
    uint256 queuedAmount;

    /***********************************|
    |               EVENTS              |
    |__________________________________*/

    /// @notice emitted when owner requests an excess withdrawal for receiver
    event ExcessWithdrawRequested(
        address indexed owner,
        address indexed receiver,
        uint256 shares,
        uint256 assets
    );

    /// @notice emitted when anyone triggers an execute withdrawal to receiver
    event ExcessWithdrawExecuted(
        address indexed receiver,
        uint256 shares,
        uint256 assets
    );

    /***********************************|
    |           CONSTRUCTOR             |
    |__________________________________*/

    constructor(ILiteVault _vault) {
        vault = _vault;
    }

    /***********************************|
    |           PUBLIC API              |
    |__________________________________*/

    /// @notice queues an excess withdrawal
    /// @param assets amount of assets to withdraw (inclusive of fee)
    /// @param receiver the receiver of the assets
    function queueExcessWithdraw(uint256 assets, address receiver) external {
        uint256 shares = vault.convertToShares(assets);
        _handleExcessWithdrawal(shares, assets, receiver);
    }

    /// @notice queues an excess redeem
    /// @param shares amount of shares to redeem (inclusive of fee)
    /// @param receiver the receiver of the assets
    function queueExcessRedeem(uint256 shares, address receiver) external {
        uint256 assets = vault.convertToAssets(shares);
        _handleExcessWithdrawal(shares, assets, receiver);
    }

    /// @notice executes a queued withdrawal
    /// @param receiver the receiver of the withdrawal for which a queue entry must exist
    function executeExcessWithdraw(address receiver) external {
        // check if receiver has any queued withdrawals
        uint256 shares = lockedShares[receiver];
        if (shares == 0) {
            return;
        }

        // update state
        uint256 assets = vault.convertToAssets(shares);
        queuedAmount -= assets;
        lockedShares[receiver] -= shares;

        // redeem shares from vault (burns them) and sends assets to receiver
        vault.redeem(shares, receiver, address(this));

        emit ExcessWithdrawExecuted(receiver, shares, assets);
    }

    /***********************************|
    |              INTERNAL             |
    |__________________________________*/

    /// @dev handles an excess withdrawal: validates, updates state, locks iTokens and emits ExcessWithdrawRequested
    /// @param shares amount of shares to redeem (inclusive of fee)
    /// @param assets amount of assets to withdraw (inclusive of fee)
    /// @param receiver the receiver of the assets
    function _handleExcessWithdrawal(
        uint256 shares,
        uint256 assets,
        address receiver
    ) internal {
        _validateExcessWithdrawal(assets);

        queuedAmount += assets;
        lockedShares[receiver] += shares;

        // lock iTokens
        vault.safeTransferFrom(msg.sender, address(this), shares);

        emit ExcessWithdrawRequested(msg.sender, receiver, shares, assets);
    }

    /// @dev validates that an amount of assets is sufficient to count as excess withdrawal
    /// @param assets amount of assets to withdraw (inclusive of fee)
    function _validateExcessWithdrawal(uint256 assets) internal view {
        uint256 minimumThresholdAmount = vault.minimumThresholdAmount();

        uint256 minimumExcessAmount = minimumThresholdAmount.mulDiv(
            minimumExcessPercentage,
            1e8, // percentage is in 1e6( 1% is 1_000_000) here we want to have 100% as denominator
            Math.Rounding.Up
        );

        if (assets < minimumExcessAmount) {
            revert ExcessWithdrawHandler__NotExcess();
        }
    }
}
