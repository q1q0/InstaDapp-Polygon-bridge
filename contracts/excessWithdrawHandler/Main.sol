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
    /// @param _maxPenaltyFee maximum penalty fee the owner is willing to accept, as an absolute amount
    ///                      Frontend / integrators have to convert percentage amount and input the absolute here.
    function queueExcessWithdraw(
        uint256 _assets,
        address _receiver,
        uint256 _maxPenaltyFee
    ) external {
        uint256 shares = vault.previewWithdraw(_assets);
        _queueExcessWithdrawRequest(shares, _assets, _receiver, _maxPenaltyFee);
    }

    /// @notice queues an excess redeem
    /// @param _shares amount of shares to redeem (inclusive of fee)
    /// @param _receiver the receiver of the assets
    /// @param _maxPenaltyFee maximum penalty fee the owner is willing to accept, as an absolute amount
    ///                      Frontend / integrators have to convert percentage amount and input the absolute here.
    function queueExcessRedeem(
        uint256 _shares,
        address _receiver,
        uint256 _maxPenaltyFee
    ) external {
        uint256 assets = vault.previewRedeem(_shares);
        _queueExcessWithdrawRequest(_shares, assets, _receiver, _maxPenaltyFee);
    }

    /// @notice executes a queued withdraw
    /// @param _excessWithdrawId the bytes32 id of the excess withdraw request (as listed in excessWithdrawIds for receiver)
    function executeExcessWithdraw(bytes32 _excessWithdrawId) external {
        ExcessWithdraw
            memory excessWithdrawRequest = _validateExecuteExcessWithdraw(
                _excessWithdrawId
            );

        // update state
        uint256 assets = vault.previewRedeem(excessWithdrawRequest.shares);
        queuedAmount -= assets;

        // delete mappings to free up space and get gas refunds
        delete excessWithdraws[_excessWithdrawId];
        if (
            _deleteExcessWithdrawId(
                _excessWithdrawId,
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
            _excessWithdrawId,
            excessWithdrawRequest.receiver,
            excessWithdrawRequest.shares,
            assets
        );
    }

    /***********************************|
    |          FEE SETTER ONLY          |
    |__________________________________*/

    /// @notice feeSetter can set the penaltyFee for an ExcessWithdraw
    /// @param _excessWithdrawId the bytes32 id of the excess withdraw request (as listed in excessWithdrawIds for receiver)
    function setPenaltyFee(bytes32 _excessWithdrawId, uint256 _penaltyFee)
        external
        onlyAllowedFeeSetter
    {
        ExcessWithdraw memory excessWithdrawRequest = excessWithdraws[
            _excessWithdrawId
        ];

        if (excessWithdrawRequest.shares == 0 || _penaltyFee == 0) {
            revert ExcessWithdrawHandler__InvalidParams();
        }

        // penaltyFee must not exceed maximum penalty fee as set by user
        if (_penaltyFee > excessWithdrawRequest.maxPenaltyFee) {
            revert ExcessWithdrawHandler__InvalidParams();
        }

        excessWithdraws[_excessWithdrawId].penaltyFee = _penaltyFee;

        emit PenaltyFeeSet(_excessWithdrawId, _penaltyFee);
    }

    /***********************************|
    |             OWNER ONLY            |
    |__________________________________*/

    /// @notice owner can add or remove allowed feeSetters
    /// @param _feeSetter the address for the feeSetter to set the flag for
    /// @param _allowed flag for if rebalancer is allowed or not
    function setFeeSetter(address _feeSetter, bool _allowed)
        external
        onlyOwner
    {
        allowedFeeSetters[_feeSetter] = _allowed;
    }

    /***********************************|
    |              INTERNAL             |
    |__________________________________*/

    /// @dev deletes an excessWithdrawId from excessWithdrawIds mapping for receiver to free up storage and get gas refund
    /// @param _excessWithdrawId the bytes32 id of the excess withdraw request (as listed in excessWithdrawIds for receiver)
    /// @param _receiver the receiver of the assets
    /// @return flag for if excessWithdrawId was found and deleted for receiver (true if yes)
    function _deleteExcessWithdrawId(
        bytes32 _excessWithdrawId,
        address _receiver
    ) internal returns (bool) {
        bytes32[] memory receiverExcessWithdrawIds = excessWithdrawIds[
            _receiver
        ];
        for (uint256 i = 0; i < receiverExcessWithdrawIds.length; ++i) {
            if (receiverExcessWithdrawIds[i] == _excessWithdrawId) {
                excessWithdrawIds[_receiver][i] = receiverExcessWithdrawIds[
                    receiverExcessWithdrawIds.length - 1
                ];
                excessWithdrawIds[_receiver].pop();
                return true;
            }
        }
        return false;
    }

    /// @dev handles an excess withdraw: validates, updates state, locks iTokens and emits ExcessWithdrawRequested
    /// @param _shares amount of shares to redeem (inclusive of fee)
    /// @param _assets amount of assets to withdraw (inclusive of fee)
    /// @param _receiver the receiver of the assets
    /// @param _maxPenaltyFee maximum penalty fee the owner is willing to accept, as an absolute amount
    function _queueExcessWithdrawRequest(
        uint256 _shares,
        uint256 _assets,
        address _receiver,
        uint256 _maxPenaltyFee
    ) internal {
        _validateExcessWithdrawRequest(
            _shares,
            _assets,
            _receiver,
            _maxPenaltyFee
        );

        // increase total queued amount of assets
        queuedAmount += _assets;

        // create and store excess withdraw data in mappings at unique id
        bytes32 excessWithdrawId = _createExcessWithdrawId(
            _shares,
            _assets,
            _receiver,
            _maxPenaltyFee,
            msg.sender
        );

        excessWithdrawIds[_receiver].push(excessWithdrawId);
        excessWithdraws[excessWithdrawId] = ExcessWithdraw({
            maxPenaltyFee: _maxPenaltyFee,
            penaltyFee: 0,
            shares: _shares,
            receiver: _receiver
        });

        // lock iTokens
        vault.safeTransferFrom(msg.sender, address(this), _shares);

        emit ExcessWithdrawRequested(
            excessWithdrawId,
            msg.sender,
            _receiver,
            _shares,
            _assets
        );
    }

    /// @dev validates a execute excess withdraw
    /// @param _excessWithdrawId the bytes32 id of the excess withdraw request (as listed in excessWithdrawIds for receiver)
    /// @return the excess withdraw request for the excess withdraw Id
    function _validateExecuteExcessWithdraw(bytes32 _excessWithdrawId)
        internal
        view
        returns (ExcessWithdraw memory)
    {
        ExcessWithdraw memory excessWithdrawRequest = excessWithdraws[
            _excessWithdrawId
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
    /// @param _shares amount of shares to redeem (inclusive of fee)
    /// @param _assets amount of assets to withdraw (inclusive of fee)
    /// @param _receiver the receiver of the assets
    /// @param _maxPenaltyFee maximum penalty fee the owner is willing to accept, as an absolute amount
    function _validateExcessWithdrawRequest(
        uint256 _shares,
        uint256 _assets,
        address _receiver,
        uint256 _maxPenaltyFee
    ) internal pure {
        if (
            _shares == 0 ||
            _assets == 0 ||
            _receiver == address(0) ||
            _maxPenaltyFee == 0
        ) {
            revert ExcessWithdrawHandler__InvalidParams();
        }
    }

    /// @dev creates a unique id for an excess withdraw based on input data and block time to prevent collision
    /// @param _shares amount of shares to redeem (inclusive of fee)
    /// @param _assets amount of assets to withdraw (inclusive of fee)
    /// @param _receiver the receiver of the assets
    /// @param _maxPenaltyFee maximum penalty fee the owner is willing to accept, as an absolute amount
    /// @param _owner the owner of the assets to be withdrawn
    /// @return the excessWithdrawId
    function _createExcessWithdrawId(
        uint256 _shares,
        uint256 _assets,
        address _receiver,
        uint256 _maxPenaltyFee,
        address _owner
    ) internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    _shares,
                    _assets,
                    _receiver,
                    _maxPenaltyFee,
                    _owner,
                    block.timestamp
                )
            );
    }
}
