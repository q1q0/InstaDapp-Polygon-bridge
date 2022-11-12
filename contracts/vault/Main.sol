// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/interfaces/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Helpers} from "./Helpers.sol";
import {Variables} from "./Variables.sol";
import {Modifiers} from "./Modifiers.sol";
import {Events} from "./Events.sol";
import "./Errors.sol";

/// @title AdminActions
/// @dev handles all admin actions, like setters for state variables
abstract contract AdminActions is OwnableUpgradeable, Modifiers {
    /// @notice owner can set the minimumThresholdPercentage
    /// @param _minimumThresholdPercentage the new minimumThresholdPercentage
    function setMinimumThresholdPercentage(uint256 _minimumThresholdPercentage)
        external
        onlyOwner
        validPercentage(_minimumThresholdPercentage)
    {
        minimumThresholdPercentage = _minimumThresholdPercentage;
    }

    /// @notice owner can add or remove allowed rebalancers
    /// @param rebalancer the address for the rebalancer to set the flag for
    /// @param allowed flag for if rebalancer is allowed or not
    function setRebalancer(address rebalancer, bool allowed)
        external
        onlyOwner
    {
        allowedRebalancers[rebalancer] = allowed;
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
    function setWithdrawFeePercentage(uint256 _withdrawFeePercentage)
        external
        onlyOwner
        validPercentage(_withdrawFeePercentage)
    {
        withdrawFeePercentage = _withdrawFeePercentage;
    }

    /// @notice owner can set the withdrawFeeReceiver
    /// @param _withdrawFeeReceiver the new withdrawFeeReceiver
    function setWithdrawFeeReceiver(address _withdrawFeeReceiver)
        external
        onlyOwner
        validAddress(_withdrawFeeReceiver)
    {
        withdrawFeeReceiver = _withdrawFeeReceiver;
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
}

/// @title LiteVault
/// @notice ERC4626 compatible vault taking ERC20 asset and investing it via bridge on mainnet
contract LiteVault is ERC4626Upgradeable, AdminActions, Helpers, Events {
    using Math for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /***********************************|
    |    CONSTRUCTOR / INITIALIZERS     |
    |__________________________________*/

    /// @notice initializes the contract with owner_ for Ownable and asset_ for the ERC4626 vault
    /// @param owner_ the Ownable address for this contract
    /// @param asset_ the ERC20 asset for the ERC4626 vault
    /// @param _minimumThresholdPercentage initial minimumThresholdPercentage
    /// @param _withdrawFeeReceiver initial withdrawFeeReceiver
    /// @param _withdrawFeePercentage initial withdrawFeePercentage
    /// @param _withdrawFeeAbsoluteMin initial withdrawFeeAbsoluteMin
    /// @param _bridgeAddress initial bridgeAddress
    /// @param _mainnetExchangePrice initial mainnetExchangePrice
    function initialize(
        address owner_,
        IERC20Upgradeable asset_,
        uint256 _minimumThresholdPercentage,
        address _withdrawFeeReceiver,
        uint256 _withdrawFeePercentage,
        uint256 _withdrawFeeAbsoluteMin,
        address _bridgeAddress,
        uint256 _mainnetExchangePrice
    ) public initializer validAddress(owner_) {
        __Ownable_init();
        transferOwnership(owner_);

        __ERC4626_init(asset_);

        minimumThresholdPercentage = _minimumThresholdPercentage;
        withdrawFeeReceiver = _withdrawFeeReceiver;
        withdrawFeePercentage = _withdrawFeePercentage;
        withdrawFeeAbsoluteMin = _withdrawFeeAbsoluteMin;
        bridgeAddress = _bridgeAddress;
        mainnetExchangePrice = _mainnetExchangePrice;
    }

    /***********************************|
    |           PUBLIC API              |
    |__________________________________*/

    /// @notice calculates the withdraw fee: max between the percentage amount or the absolute amount
    /// @param sharesAmount the amount of shares being withdrawn
    /// @return the withdraw fee amount in assets (not shares!)
    function getRedeemFee(uint256 sharesAmount) public view returns (uint256) {
        uint256 assetsAmount = previewRedeem(sharesAmount);
        return getWithdrawFee(assetsAmount);
    }

    /// @notice calculates the withdraw fee: max between the percentage amount or the absolute amount
    /// @param assetsAmount the amount of assets being withdrawn
    /// @return the withdraw fee amount in assets
    function getWithdrawFee(uint256 assetsAmount)
        public
        view
        returns (uint256)
    {
        uint256 withdrawFee = _getPercentageAmount(
            assetsAmount,
            withdrawFeePercentage,
            Math.Rounding.Up
        );

        return Math.max(withdrawFee, withdrawFeeAbsoluteMin);
    }

    /// @notice calculates the minimum threshold amount of asset that must stay in the contract
    /// @return minimumThresholdAmount
    function minimumThresholdAmount() public view returns (uint256) {
        return
            _getPercentageAmount(
                investedAssets,
                minimumThresholdPercentage,
                Math.Rounding.Up
            );
    }

    /// @notice returns the total amount of assets managed by the vault, combining idle + active (bridged)
    /// @return amount of assets managed by vault
    /** @dev See {IERC4626-totalAssets}. */
    function totalAssets() public view override returns (uint256) {
        return
            IERC20Upgradeable(asset()).balanceOf(address(this)) + // assets in contract (idle)
            totalInvestedAssets(); // plus assets invested through bridge (active)
    }

    /// @notice calculates the total invested assets that are bridged
    /// @return amount of invested assets (currently bridged) adjusted for exchangePrice
    function totalInvestedAssets() public view returns (uint256) {
        // e.g. with mainnetExchangePrice is 2 (1 unit on Mainnet is worth 2 raw tokens on Polygon)
        // (because asset on bridge has appreciated in value through yield over time)
        // 100 * 2 = 200;
        return
            investedAssets.mulDiv(
                mainnetExchangePrice,
                decimals(),
                Math.Rounding.Down
            );
    }

    /** @dev See {IERC4626-withdraw}. */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner_
    ) public override returns (uint256) {
        // Logic below adapted from OpenZeppelin ERC4626Upgradeable: added logic for fee
        require(
            assets <= maxWithdraw(owner_),
            "ERC4626: withdraw more than max"
        );

        // burn full shares but only withdraw assetsAfterFee
        uint256 shares = previewWithdraw(assets);
        uint256 assetsAfterFee = _collectWithdrawFee(assets, owner_);
        _withdraw(_msgSender(), receiver, owner_, assetsAfterFee, shares);

        return shares;
    }

    /** @dev See {IERC4626-redeem}. */
    function redeem(
        uint256 shares,
        address receiver,
        address owner_
    ) public override returns (uint256) {
        // Logic below adapted from OpenZeppelin ERC4626Upgradeable: added logic for fee
        require(shares <= maxRedeem(owner_), "ERC4626: redeem more than max");

        uint256 assets = previewRedeem(shares);
        // burn full shares but only withdraw assetsAfterFee
        uint256 assetsAfterFee = _collectWithdrawFee(assets, owner_);
        _withdraw(_msgSender(), receiver, owner_, assetsAfterFee, shares);

        return assetsAfterFee;
    }

    /// @notice checks if a certain address is an allowed rebalancer
    /// @param rebalancer address to check
    /// @return flag true or false if allowed
    function isAllowedRebalancer(address rebalancer)
        external
        view
        returns (bool)
    {
        return allowedRebalancers[rebalancer];
    }

    /***********************************|
    |          REBALANCER ONLY          |
    |__________________________________*/

    /// @notice moves amountToMove assets to the bridgeAddress
    /// @param amountToMove (raw) amount of assets to transfer to bridge
    function toMainnet(uint256 amountToMove) external onlyAllowedRebalancer {
        // amount of principal left must cover at least minimumThresholdAmount
        uint256 principalLeft = investedAssets - amountToMove;
        if (principalLeft < minimumThresholdAmount()) {
            revert LiteVault__MinimumThreshold();
        }

        // send amountToMove to bridge
        IERC20Upgradeable(asset()).safeTransfer(bridgeAddress, amountToMove);

        // update the amount of bridged principal (raw amount)
        // bridgedAmount = amountToMove / mainnetExchangePrice
        // e.g. with an mainnetExchangePrice 2 (1 unit on Mainnet is worth 2 raw tokens on Polygon)
        // (because asset on bridge has appreciated in value through yield over time)
        // 100 / 2 = 50;
        investedAssets += amountToMove.mulDiv(
            decimals(),
            mainnetExchangePrice,
            Math.Rounding.Down
        );

        emit ToMainnet(bridgeAddress, amountToMove);
    }

    /// @notice moves amountToMove from bridge to this contract
    /// @param amountToMove (raw) amount of assets to transfer from bridge
    function fromMainnet(uint256 amountToMove) external onlyAllowedRebalancer {
        // transferFrom rebalancer
        IERC20Upgradeable(asset()).safeTransferFrom(
            bridgeAddress,
            address(this),
            amountToMove
        );

        // update the amount of bridged principal (raw amount)
        // bridgedAmount = amountToMove / mainnetExchangePrice
        // e.g. with an mainnetExchangePrice 2 (1 unit on Mainnet is worth 2 raw tokens on Polygon)
        // (because asset on bridge has appreciated in value through yield over time)
        // 100 / 2 = 50;
        investedAssets -= amountToMove.mulDiv(
            decimals(),
            mainnetExchangePrice,
            Math.Rounding.Down
        );

        emit FromMainnet(bridgeAddress, amountToMove);
    }

    /// @notice rebalancer can set the mainnetExchangePrice
    /// @param _mainnetExchangePrice the new mainnetExchangePrice
    function updateMainnetExchangePrice(uint256 _mainnetExchangePrice)
        external
        onlyAllowedRebalancer
    {
        mainnetExchangePrice = _mainnetExchangePrice;
    }

    /***********************************|
    |              INTERNAL             |
    |__________________________________*/

    /// @dev collects the withdraw fee on assetsAmount and emits WithdrawFeeCollected
    /// @param assetsAmount the amount of assets being withdrawn
    /// @param owner_ the owner of the assets
    /// @return the withdraw assetsAmount amount AFTER deducting the fee
    function _collectWithdrawFee(uint256 assetsAmount, address owner_)
        internal
        returns (uint256)
    {
        uint256 withdrawFee = getWithdrawFee(assetsAmount);

        IERC20Upgradeable(asset()).safeTransfer(
            withdrawFeeReceiver,
            withdrawFee
        );

        emit WithdrawFeeCollected(owner_, withdrawFee);

        return assetsAmount - withdrawFee;
    }
}
