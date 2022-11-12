// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/interfaces/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Variables} from "./Variables.sol";
import {Modifiers} from "./Modifiers.sol";
import {Events} from "./Events.sol";
import "./Errors.sol";

/// @title AdminActions
/// @dev handles all admin actions, like setters for state variables
abstract contract AdminActions is
    ERC4626Upgradeable,
    OwnableUpgradeable,
    Modifiers
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @notice owner can set the minimumThresholdPercentage
    /// @param _minimumThresholdPercentage the new minimumThresholdPercentage
    function setMinimumThresholdPercentage(uint32 _minimumThresholdPercentage)
        external
        onlyOwner
        validPercentage(_minimumThresholdPercentage)
    {
        minimumThresholdPercentage = _minimumThresholdPercentage;
    }

    /// @notice owner can add or remove allowed rebalancers
    /// @param _rebalancer the address for the rebalancer to set the flag for
    /// @param _allowed flag for if rebalancer is allowed or not
    function setRebalancer(address _rebalancer, bool _allowed)
        external
        onlyOwner
    {
        allowedRebalancers[_rebalancer] = _allowed;
    }

    /// @notice owner can set the withdrawFeeAbsoluteMin
    /// @param _withdrawFeeAbsoluteMin the new withdrawFeeAbsoluteMin
    function setWithdrawFeeAbsoluteMin(uint256 _withdrawFeeAbsoluteMin)
        external
        onlyOwner
    {
        withdrawFeeAbsoluteMin = _withdrawFeeAbsoluteMin;
    }

    /// @notice owner can set the withdrawFeePercentage
    /// @param _withdrawFeePercentage the new withdrawFeePercentage
    function setWithdrawFeePercentage(uint32 _withdrawFeePercentage)
        external
        onlyOwner
        validPercentage(_withdrawFeePercentage)
    {
        withdrawFeePercentage = _withdrawFeePercentage;
    }

    /// @notice owner can set the bridgeAddress
    /// @param _bridgeAddress the new bridgeAddress
    function setBridgeAddress(address _bridgeAddress)
        external
        onlyOwner
        validAddress(_bridgeAddress)
    {
        bridgeAddress = _bridgeAddress;
    }

    /// @notice owner can withdraw the collected withdraw fees
    /// @param _withdrawFeeReceiver the receiver address for the fees transfer
    function withdrawFees(address _withdrawFeeReceiver) internal onlyOwner {
        IERC20Upgradeable(asset()).safeTransfer(
            _withdrawFeeReceiver,
            collectedFees
        );
    }
}

/// @title BridgeActions
/// @dev actions executable by bridge only
abstract contract BridgeActions is Modifiers {
    /// @notice rebalancer can set the mainnetExchangePrice
    /// @param _mainnetExchangePrice the new mainnetExchangePrice in 1e18
    function updateMainnetExchangePrice(uint256 _mainnetExchangePrice)
        external
        onlyBridge
    {
        mainnetExchangePrice = _mainnetExchangePrice;
    }
}

/// @title RebalancerActions
/// @dev actions executable by allowed rebalancers only
abstract contract RebalancerActions is ERC4626Upgradeable, Modifiers, Events {
    using Math for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    function minimumThresholdAmount() public view virtual returns (uint256);

    /// @notice moves amountToMove assets to the bridgeAddress
    /// @param _amountToMove (raw) amount of assets to transfer to bridge
    function toMainnet(uint256 _amountToMove) external onlyAllowedRebalancer {
        // amount of principal left must cover at least minimumThresholdAmount
        uint256 principalLeft = IERC20Upgradeable(asset()).balanceOf(
            address(this)
        ) - _amountToMove;
        if (principalLeft < minimumThresholdAmount()) {
            revert LiteVault__ExceedMinimumThreshold();
        }

        // send amountToMove to bridge
        IERC20Upgradeable(asset()).safeTransfer(bridgeAddress, _amountToMove);

        // update the amount of bridged principal (raw amount)
        // bridgedAmount = amountToMove / mainnetExchangePrice
        // e.g. with an mainnetExchangePrice 2 (1 unit on Mainnet is worth 2 raw tokens on Polygon)
        // (because asset on bridge has appreciated in value through yield over time)
        // 100 / 2 = 50;
        investedAssets += _amountToMove.mulDiv(
            1e18, // mainnetExchangePrice is in 1e18
            mainnetExchangePrice
        );

        emit ToMainnet(bridgeAddress, _amountToMove);
    }

    /// @notice moves amountToMove from bridge to this contract
    /// @param _amountToMove (raw) amount of assets to transfer from bridge
    function fromMainnet(uint256 _amountToMove) external onlyAllowedRebalancer {
        // transferFrom rebalancer
        IERC20Upgradeable(asset()).safeTransferFrom(
            bridgeAddress,
            address(this),
            _amountToMove
        );

        // update the amount of bridged principal (raw amount)
        // bridgedAmount = amountToMove / mainnetExchangePrice
        // e.g. with an mainnetExchangePrice 2 (1 unit on Mainnet is worth 2 raw tokens on Polygon)
        // (because asset on bridge has appreciated in value through yield over time)
        // 100 / 2 = 50;
        investedAssets -= _amountToMove.mulDiv(1e18, mainnetExchangePrice);

        emit FromMainnet(bridgeAddress, _amountToMove);
    }
}

/// @title LiteVault
/// @notice ERC4626 compatible vault taking ERC20 asset and investing it via bridge on mainnet
contract LiteVault is AdminActions, BridgeActions, RebalancerActions {
    using Math for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /***********************************|
    |    CONSTRUCTOR / INITIALIZERS     |
    |__________________________________*/

    /// @notice initializes the contract with owner_ for Ownable and asset_ for the ERC4626 vault
    /// @param _owner the Ownable address for this contract
    /// @param _asset the ERC20 asset for the ERC4626 vault
    /// @param _minimumThresholdPercentage initial minimumThresholdPercentage
    /// @param _withdrawFeePercentage initial withdrawFeePercentage
    /// @param _withdrawFeeAbsoluteMin initial withdrawFeeAbsoluteMin
    /// @param _bridgeAddress initial bridgeAddress
    /// @param _mainnetExchangePrice initial mainnetExchangePrice
    function initialize(
        address _owner,
        IERC20Upgradeable _asset,
        uint32 _minimumThresholdPercentage,
        uint32 _withdrawFeePercentage,
        uint256 _withdrawFeeAbsoluteMin,
        address _bridgeAddress,
        uint256 _mainnetExchangePrice
    ) public initializer validAddress(_owner) {
        __Ownable_init();
        transferOwnership(_owner);

        __ERC4626_init(_asset);

        minimumThresholdPercentage = _minimumThresholdPercentage;
        withdrawFeePercentage = _withdrawFeePercentage;
        withdrawFeeAbsoluteMin = _withdrawFeeAbsoluteMin;
        bridgeAddress = _bridgeAddress;
        mainnetExchangePrice = _mainnetExchangePrice;
    }

    /***********************************|
    |           PUBLIC API              |
    |__________________________________*/

    /// @notice calculates the withdraw fee: max between the percentage amount or the absolute amount
    /// @param _sharesAmount the amount of shares being withdrawn
    /// @return the withdraw fee amount in assets (not shares!)
    function getRedeemFee(uint256 _sharesAmount) public view returns (uint256) {
        uint256 assetsAmount = previewRedeem(_sharesAmount);
        return getWithdrawFee(assetsAmount);
    }

    /// @notice calculates the withdraw fee: max between the percentage amount or the absolute amount
    /// @param _assetsAmount the amount of assets being withdrawn
    /// @return the withdraw fee amount in assets
    function getWithdrawFee(uint256 _assetsAmount)
        public
        view
        returns (uint256)
    {
        uint256 withdrawFee = _assetsAmount.mulDiv(
            withdrawFeePercentage,
            1e8 // percentage is in 1e6( 1% is 1_000_000) here we want to have 100% as denominator
        );

        return Math.max(withdrawFee, withdrawFeeAbsoluteMin);
    }

    /// @notice calculates the minimum threshold amount of asset that must stay in the contract
    /// @return minimumThresholdAmount
    function minimumThresholdAmount() public view override returns (uint256) {
        uint256 _totalAssets = totalAssets();
        if (_totalAssets == 0) {
            return 0;
        }
        return
            _totalAssets.mulDiv(
                minimumThresholdPercentage,
                1e8 // percentage is in 1e6( 1% is 1_000_000) here we want to have 100% as denominator
            );
    }

    /// @notice returns the total amount of assets managed by the vault, combining idle + active (bridged)
    /// @return amount of assets managed by vault
    /** @dev See {IERC4626-totalAssets}. */
    function totalAssets() public view override returns (uint256) {
        return
            IERC20Upgradeable(asset()).balanceOf(address(this)) + // assets in contract (idle)
            totalInvestedAssets() - // plus assets invested through bridge (active)
            collectedFees; // minus already collected Fees just sitting in the vault until withdraw by admin
    }

    /// @notice calculates the total invested assets that are bridged
    /// @return amount of invested assets (currently bridged) adjusted for exchangePrice
    function totalInvestedAssets() public view returns (uint256) {
        if (investedAssets == 0) {
            return 0;
        }
        // e.g. with mainnetExchangePrice is 2 (1 unit on Mainnet is worth 2 raw tokens on Polygon)
        // (because asset on bridge has appreciated in value through yield over time)
        // 100 * 2 = 200;
        return
            investedAssets.mulDiv(
                mainnetExchangePrice, // mainnetExchangePrice is in 1e18
                1e18
            );
    }

    /** @dev See {IERC4626-withdraw}. */
    function withdraw(
        uint256 _assets,
        address _receiver,
        address _owner
    ) public override returns (uint256) {
        // Logic below adapted from OpenZeppelin ERC4626Upgradeable: added logic for fee
        require(
            _assets <= maxWithdraw(_owner),
            "ERC4626: withdraw more than max"
        );

        // burn full shares but only withdraw assetsAfterFee
        uint256 shares = previewWithdraw(_assets);
        uint256 assetsAfterFee = _collectWithdrawFee(_assets, _owner);
        _withdraw(msg.sender, _receiver, _owner, assetsAfterFee, shares);

        return shares;
    }

    /** @dev See {IERC4626-redeem}. */
    function redeem(
        uint256 _shares,
        address _receiver,
        address _owner
    ) public override returns (uint256) {
        // Logic below adapted from OpenZeppelin ERC4626Upgradeable: added logic for fee
        require(_shares <= maxRedeem(_owner), "ERC4626: redeem more than max");

        uint256 assets = previewRedeem(_shares);
        // burn full shares but only withdraw assetsAfterFee
        uint256 assetsAfterFee = _collectWithdrawFee(assets, _owner);
        _withdraw(msg.sender, _receiver, _owner, assetsAfterFee, _shares);

        return assetsAfterFee;
    }

    /***********************************|
    |              INTERNAL             |
    |__________________________________*/

    /// @dev collects the withdraw fee on assetsAmount and emits WithdrawFeeCollected
    /// @param _assetsAmount the amount of assets being withdrawn
    /// @param _owner the owner of the assets
    /// @return the withdraw assetsAmount amount AFTER deducting the fee
    function _collectWithdrawFee(uint256 _assetsAmount, address _owner)
        internal
        returns (uint256)
    {
        uint256 withdrawFee = getWithdrawFee(_assetsAmount);

        collectedFees += withdrawFee;

        emit WithdrawFeeCollected(_owner, withdrawFee);

        return _assetsAmount - withdrawFee;
    }
}
