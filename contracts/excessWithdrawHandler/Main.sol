// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ILiteVault} from "../vault/Interfaces.sol";

import {Variables} from "./Variables.sol";
import {Modifiers} from "./Modifiers.sol";
import {Events} from "./Events.sol";
import "./Errors.sol";

/// @title ExcessWithdrawHandler
/// @notice Handles excess withdraws for LiteVaults. I.e. users can request withdraws here that surpass
/// the minimumThreshold from the LiteVault by locking their iTokens here
contract ExcessWithdrawHandler is Ownable, Variables, Modifiers, Events {
    using Math for uint256;
    using SafeERC20Upgradeable for ILiteVault;

    /***********************************|
    |           CONSTRUCTOR             |
    |__________________________________*/

    constructor(ILiteVault _vault) Ownable() Variables(_vault) {}

    /***********************************|
    |           PUBLIC API              |
    |__________________________________*/

    /// @notice queues an excess withdraw
    /// @param _assets amount of assets to withdraw (inclusive of fee)
    /// @param _receiver the receiver of the assets
    /// @param _maxPenaltyFeePercentage maximum penalty fee the owner is willing to accept in percentage
    function queueExcessWithdraw(
        uint256 _assets,
        address _receiver,
        uint32 _maxPenaltyFeePercentage
    ) external isGtePenaltyFee(_maxPenaltyFeePercentage) {
        uint256 shares = vault.previewWithdraw(_assets);
        _queueExcessWithdrawRequest(shares, _assets, _receiver);
    }

    /// @notice queues an excess redeem
    /// @param _shares amount of shares to redeem (inclusive of fee)
    /// @param _receiver the receiver of the assets
    /// @param _maxPenaltyFeePercentage maximum penalty fee the owner is willing to accept in percentage
    function queueExcessRedeem(
        uint256 _shares,
        address _receiver,
        uint32 _maxPenaltyFeePercentage
    ) external isGtePenaltyFee(_maxPenaltyFeePercentage) {
        uint256 assets = vault.previewRedeem(_shares);
        _queueExcessWithdrawRequest(_shares, assets, _receiver);
    }

    /// @notice executes a queued withdraw (withdraws funds)
    /// @param _receiver the receiver of the assets
    function executeExcessWithdraw(address _receiver) external {
        // check if receiver has any queued withdrawals
        uint256 assets = queuedWithdrawAmounts[_receiver];
        if (assets == 0) {
            return;
        }

        // update state
        uint256 shares = vault.convertToAssets(assets);
        totalQueuedAmount -= assets;
        queuedWithdrawAmounts[_receiver] -= assets;

        // redeem shares from vault (burns them) and sends assets to receiver
        vault.redeem(shares, _receiver, address(this));

        emit ExcessWithdrawExecuted(_receiver, shares, assets);
    }

    /***********************************|
    |          FEE SETTER ONLY          |
    |__________________________________*/

    /// @notice feeSetter can set the current penaltyFeePercentage
    /// @param _penaltyFeePercentage the new penaltyFeePercentage
    function setPenaltyFee(uint32 _penaltyFeePercentage)
        external
        onlyAllowedFeeSetter
    {
        penaltyFeePercentage = _penaltyFeePercentage;

        emit PenaltyFeeSet(_penaltyFeePercentage);
    }

    /***********************************|
    |             OWNER ONLY            |
    |__________________________________*/

    /// @notice owner can add or remove allowed feeSetters
    /// @param _feeSetter the address for the feeSetter to set the flag for
    /// @param _allowed flag for if feeSetter is allowed or not
    function setFeeSetter(address _feeSetter, bool _allowed)
        external
        onlyOwner
    {
        allowedFeeSetters[_feeSetter] = _allowed;
    }

    /***********************************|
    |              INTERNAL             |
    |__________________________________*/

    /// @dev handles an excess withdraw: validates, updates state, locks iTokens and emits ExcessWithdrawRequested
    /// @param _shares amount of shares to redeem (inclusive of fee)
    /// @param _assets amount of assets to withdraw (inclusive of fee)
    /// @param _receiver the receiver of the assets
    function _queueExcessWithdrawRequest(
        uint256 _shares,
        uint256 _assets,
        address _receiver
    ) internal {
        _validateExcessWithdrawRequest(_shares, _assets, _receiver);

        // get amount to queue AFTER penalty fee
        uint256 queueAmount = _assets.mulDiv(
            penaltyFeePercentage,
            1e8 // percentage is in 1e6( 1% is 1_000_000) here we want to have 100% as denominator
        );

        // increase total queued amount of assets
        totalQueuedAmount += queueAmount;

        // increase receiver withdrawable amount
        queuedWithdrawAmounts[_receiver] += queueAmount;

        // lock iTokens
        vault.safeTransferFrom(msg.sender, address(this), _shares);

        emit ExcessWithdrawRequested(msg.sender, _receiver, _shares, _assets);
    }

    /// @dev validates an excess withdraw request input params & amount
    /// @param _shares amount of shares to redeem (inclusive of fee)
    /// @param _assets amount of assets to withdraw (inclusive of fee)
    /// @param _receiver the receiver of the assets
    function _validateExcessWithdrawRequest(
        uint256 _shares,
        uint256 _assets,
        address _receiver
    ) internal pure {
        if (_shares == 0 || _assets == 0 || _receiver == address(0)) {
            revert ExcessWithdrawHandler__InvalidParams();
        }
    }
}
