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
    /// @param assets amount of assets to withdraw (inclusive of fee)
    /// @param receiver the receiver of the assets
    /// @param maxPenaltyFee maximum penalty fee the owner is willing to accept, as an absolute amount
    ///                      Frontend / integrators have to convert percentage amount and input the absolute here.
    function queueExcessWithdraw(
        uint256 assets,
        address receiver,
        uint256 maxPenaltyFee
    ) external {
        uint256 shares = vault.previewWithdraw(assets);
        _queueExcessWithdrawRequest(shares, assets, receiver, maxPenaltyFee);
    }

    /// @notice queues an excess redeem
    /// @param shares amount of shares to redeem (inclusive of fee)
    /// @param receiver the receiver of the assets
    /// @param maxPenaltyFee maximum penalty fee the owner is willing to accept, as an absolute amount
    ///                      Frontend / integrators have to convert percentage amount and input the absolute here.
    function queueExcessRedeem(
        uint256 shares,
        address receiver,
        uint256 maxPenaltyFee
    ) external {
        uint256 assets = vault.previewRedeem(shares);
        _queueExcessWithdrawRequest(shares, assets, receiver, maxPenaltyFee);
    }

    /// @notice executes a queued withdraw
    /// @param excessWithdrawId the bytes32 id of the excess withdraw request (as listed in excessWithdrawIds for receiver)
    function executeExcessWithdraw(bytes32 excessWithdrawId) external {
        ExcessWithdraw
            memory excessWithdrawRequest = _validateExecuteExcessWithdraw(
                excessWithdrawId
            );

        // update state
        uint256 assets = vault.previewRedeem(excessWithdrawRequest.shares);
        queuedAmount -= assets;

        // delete mappings to free up space and get gas refunds
        delete excessWithdraws[excessWithdrawId];
        if (
            _deleteExcessWithdrawId(
                excessWithdrawId,
                excessWithdrawRequest.receiver
            ) == false
        ) {
            revert ExcessWithdrawHandler__InvalidParams();
        }

        // redeem shares from vault (burns them) and sends assets to receiver
        vault.redeem(
            excessWithdrawRequest.shares,
            excessWithdrawRequest.receiver,
            address(this)
        );

        emit ExcessWithdrawExecuted(
            excessWithdrawId,
            excessWithdrawRequest.receiver,
            excessWithdrawRequest.shares,
            assets
        );
    }

    /// @notice checks if a certain address is an allowed feeSetter
    /// @param feeSetter address to check
    /// @return flag true or false if allowed
    function isAllowedFeeSetter(address feeSetter)
        external
        view
        returns (bool)
    {
        return allowedFeeSetters[feeSetter];
    }

    /***********************************|
    |          FEE SETTER ONLY          |
    |__________________________________*/

    /// @notice feeSetter can set the penaltyFee for an ExcessWithdraw
    /// @param excessWithdrawId the bytes32 id of the excess withdraw request (as listed in excessWithdrawIds for receiver)
    function setPenaltyFee(bytes32 excessWithdrawId, uint256 penaltyFee)
        external
        onlyAllowedFeeSetter
    {
        ExcessWithdraw memory excessWithdrawRequest = excessWithdraws[
            excessWithdrawId
        ];

        if (excessWithdrawRequest.shares == 0 || penaltyFee == 0) {
            revert ExcessWithdrawHandler__InvalidParams();
        }

        // penaltyFee must not exceed maximum penalty fee as set by user
        if (penaltyFee > excessWithdrawRequest.maxPenaltyFee) {
            revert ExcessWithdrawHandler__InvalidParams();
        }

        excessWithdraws[excessWithdrawId].penaltyFee = penaltyFee;

        emit PenaltyFeeSet(excessWithdrawId, penaltyFee);
    }

    /***********************************|
    |             OWNER ONLY            |
    |__________________________________*/

    /// @notice owner can add or remove allowed feeSetters
    /// @param feeSetter the address for the feeSetter to set the flag for
    /// @param allowed flag for if rebalancer is allowed or not
    function setFeeSetter(address feeSetter, bool allowed) external onlyOwner {
        allowedFeeSetters[feeSetter] = allowed;
    }

    /***********************************|
    |              INTERNAL             |
    |__________________________________*/

    /// @dev deletes an excessWithdrawId from excessWithdrawIds mapping for receiver to free up storage and get gas refund
    /// @param excessWithdrawId the bytes32 id of the excess withdraw request (as listed in excessWithdrawIds for receiver)
    /// @param receiver the receiver of the assets
    /// @return flag for if excessWithdrawId was found and deleted for receiver (true if yes)
    function _deleteExcessWithdrawId(bytes32 excessWithdrawId, address receiver)
        internal
        returns (bool)
    {
        bytes32[] memory receiverExcessWithdrawIds = excessWithdrawIds[
            receiver
        ];
        for (uint256 i = 0; i < receiverExcessWithdrawIds.length; ++i) {
            if (receiverExcessWithdrawIds[i] == excessWithdrawId) {
                excessWithdrawIds[receiver][i] = receiverExcessWithdrawIds[
                    receiverExcessWithdrawIds.length - 1
                ];
                excessWithdrawIds[receiver].pop();
                return true;
            }
        }
        return false;
    }

    /// @dev handles an excess withdraw: validates, updates state, locks iTokens and emits ExcessWithdrawRequested
    /// @param shares amount of shares to redeem (inclusive of fee)
    /// @param assets amount of assets to withdraw (inclusive of fee)
    /// @param receiver the receiver of the assets
    /// @param maxPenaltyFee maximum penalty fee the owner is willing to accept, as an absolute amount
    function _queueExcessWithdrawRequest(
        uint256 shares,
        uint256 assets,
        address receiver,
        uint256 maxPenaltyFee
    ) internal {
        _validateExcessWithdrawRequest(shares, assets, receiver, maxPenaltyFee);

        // increase total queued amount of assets
        queuedAmount += assets;

        // create and store excess withdraw data in mappings at unique id
        bytes32 excessWithdrawId = _createExcessWithdrawId(
            shares,
            assets,
            receiver,
            maxPenaltyFee,
            msg.sender
        );

        excessWithdrawIds[receiver].push(excessWithdrawId);
        excessWithdraws[excessWithdrawId] = ExcessWithdraw({
            maxPenaltyFee: maxPenaltyFee,
            penaltyFee: 0,
            shares: shares,
            receiver: receiver
        });

        // lock iTokens
        vault.safeTransferFrom(msg.sender, address(this), shares);

        emit ExcessWithdrawRequested(
            excessWithdrawId,
            msg.sender,
            receiver,
            shares,
            assets
        );
    }

    /// @dev validates a execute excess withdraw
    /// @param excessWithdrawId the bytes32 id of the excess withdraw request (as listed in excessWithdrawIds for receiver)
    /// @return the excess withdraw request for the excess withdraw Id
    function _validateExecuteExcessWithdraw(bytes32 excessWithdrawId)
        internal
        view
        returns (ExcessWithdraw memory)
    {
        ExcessWithdraw memory excessWithdrawRequest = excessWithdraws[
            excessWithdrawId
        ];

        if (excessWithdrawRequest.shares == 0) {
            revert ExcessWithdrawHandler__InvalidParams();
        }

        // bot must have set the penalty fee
        if (excessWithdrawRequest.penaltyFee == 0) {
            revert ExcessWithdrawHandler__FeeNotSet();
        }

        return excessWithdrawRequest;
    }

    /// @dev validates an excess withdraw request input params & amount
    /// @param shares amount of shares to redeem (inclusive of fee)
    /// @param assets amount of assets to withdraw (inclusive of fee)
    /// @param receiver the receiver of the assets
    /// @param maxPenaltyFee maximum penalty fee the owner is willing to accept, as an absolute amount
    function _validateExcessWithdrawRequest(
        uint256 shares,
        uint256 assets,
        address receiver,
        uint256 maxPenaltyFee
    ) internal pure {
        if (
            shares == 0 ||
            assets == 0 ||
            receiver == address(0) ||
            maxPenaltyFee == 0
        ) {
            revert ExcessWithdrawHandler__InvalidParams();
        }
    }

    /// @dev creates a unique id for an excess withdraw based on input data and block time to prevent collision
    /// @param shares amount of shares to redeem (inclusive of fee)
    /// @param assets amount of assets to withdraw (inclusive of fee)
    /// @param receiver the receiver of the assets
    /// @param maxPenaltyFee maximum penalty fee the owner is willing to accept, as an absolute amount
    /// @param owner_ the owner of the assets to be withdrawn
    /// @return the excessWithdrawId
    function _createExcessWithdrawId(
        uint256 shares,
        uint256 assets,
        address receiver,
        uint256 maxPenaltyFee,
        address owner_
    ) internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    shares,
                    assets,
                    receiver,
                    maxPenaltyFee,
                    owner_,
                    block.timestamp
                )
            );
    }
}
