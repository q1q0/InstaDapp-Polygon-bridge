// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/interfaces/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

error LiteVault__InvalidParams();
error LiteVault__Unauthorized();
error LiteVault__MinimumThreshold();

/// @title LiteVault
/// @notice ERC4626 compatible vault taking ERC20 asset and investing it via bridge on mainnet
contract LiteVault is ERC4626Upgradeable, OwnableUpgradeable {
    using Math for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /***********************************|
    |             CONSTANTS             |
    |__________________________________*/

    /// @notice upper limit of percentage values
    /// with 1e6 as base for percentage values 1e8 is 100%
    uint256 maximumPercentageRange = 1e8;

    /***********************************|
    |           STATE VARIABLES         |
    |__________________________________*/

    /// @notice list of addresses that are allowed to access toMainnet and fromMainnet functions
    /// modifiable by owner
    mapping(address => bool) allowedRebalancers;

    /// @notice percentage of token in 1e6 that should remain in the vault when transferring to mainnet.
    /// this number is given in 1e6, i.e. 1% would equal 1_000_000, 10% would be 10_000_000 etc.
    /// e.g.: if the threshold is 10% and the vault’s TVL is 1M USDC,
    /// then 900k USDC will be transferred to the mainnet iToken vaul
    /// and 100k USDC will sit idle here for instant withdrawals for users.
    /// modifiable by owner
    uint256 minimumThresholdPercentage;

    /// @notice address that receives the withdrawal fee
    /// modifiable by owner
    address withdrawalFeeReceiver;

    /// @notice withdrawal fee is either amount in percentage or absolute minimum. This var defines the percentage in 1e6
    /// this number is given in 1e6, i.e. 1% would equal 1_000_000, 10% would be 10_000_000 etc.
    /// modifiable by owner
    uint256 withdrawalFeePercentage;
    /// @notice withdrawal fee is either amount in percentage or absolute minimum. This var defines the absolute minimum
    /// this number is given in decimals for the respective asset of the vault.
    /// modifiable by owner
    uint256 withdrawalFeeAbsoluteMin;

    /// @notice bridge address to which funds will be transferred to when calling toMainnet
    /// modifiable by owner
    address bridgeAddress;

    /// @notice exchange price in asset.decimals
    /// modifiable by rebalancers
    uint256 mainnetExchangePrice;

    /// @notice total (original) raw amount of assets currently committed to invest via bridge
    /// updated in fromMainnet and toMainnet
    uint256 internal investedAssets;

    /***********************************|
    |               EVENTS              |
    |__________________________________*/

    /// @notice emitted whenever a user withdraws assets and a fee for withdrawalFeeReceiver is collected
    event WithdrawalFeeCollected(address indexed receiver, uint256 indexed fee);

    /***********************************|
    |              MODIFIERS            |
    |__________________________________*/

    /// @notice checks if an address is not 0x000...
    modifier validAddress(address _address) {
        if (_address == address(0)) {
            revert LiteVault__InvalidParams();
        }
        _;
    }

    /// @notice checks if a percentage value is within the maximumPercentageRange
    modifier validPercentage(uint256 percentage) {
        if (percentage > maximumPercentageRange) {
            revert LiteVault__InvalidParams();
        }
        _;
    }

    /// @notice checks if msg.sender is an allowed rebalancer
    modifier onlyAllowedRebalancer() {
        if (!allowedRebalancers[msg.sender]) {
            revert LiteVault__Unauthorized();
        }
        _;
    }

    /***********************************|
    |    CONSTRUCTOR / INITIALIZERS     |
    |__________________________________*/

    /// @notice initializes the contract with owner_ for Ownable and asset_ for the ERC4626 vault
    /// @param owner_ the Ownable address for this contract
    /// @param asset_ the ERC20 asset for the ERC4626 vault
    function initialize(address owner_, IERC20Upgradeable asset_)
        public
        initializer
        validAddress(owner_)
    {
        __Ownable_init();
        transferOwnership(owner_);

        __ERC4626_init(asset_);
    }

    /***********************************|
    |           PUBLIC API              |
    |__________________________________*/

    /// @notice calculates the withdrawal fee: max between the percentage amount or the absolute amount
    /// @param sharesAmount the amount of shares being withdrawn
    /// @return the withdrawal fee amount in assets (not shares!)
    function getRedeemFee(uint256 sharesAmount) public view returns (uint256) {
        uint256 shares = convertToAssets(sharesAmount);
        return getWithdrawalFee(shares);
    }

    /// @notice calculates the withdrawal fee: max between the percentage amount or the absolute amount
    /// @param assetsAmount the amount of assets being withdrawn
    /// @return the withdrawal fee amount in assets
    function getWithdrawalFee(uint256 assetsAmount)
        public
        view
        returns (uint256)
    {
        uint256 withdrawalFee = _getPercentageAmount(
            assetsAmount,
            withdrawalFeePercentage,
            Math.Rounding.Up
        );

        return Math.max(withdrawalFee, withdrawalFeeAbsoluteMin);
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
        uint256 assetsAfterFee = _collectWithdrawalFee(assets, owner_);
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
        uint256 assetsAfterFee = _collectWithdrawalFee(assets, owner_);
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
    }

    /// @notice moves amountToMove from bridge to this contract
    /// @param amountToMove (raw) amount of assets to transfer from bridge
    function fromMainnet(uint256 amountToMove) external onlyAllowedRebalancer {
        // transferFrom rebalancer
        IERC20Upgradeable(asset()).safeTransferFrom(
            msg.sender,
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
    |             OWNER ONLY            |
    |__________________________________*/

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

    /// @notice owner can set the withdrawalFeeAbsoluteMin
    /// @param _withdrawalFeeAbsoluteMin the new withdrawalFeeAbsoluteMin
    function setWithdrawalFeeAbsoluteMin(uint256 _withdrawalFeeAbsoluteMin)
        external
        onlyOwner
    {
        withdrawalFeeAbsoluteMin = _withdrawalFeeAbsoluteMin;
    }

    /// @notice owner can set the withdrawalFeePercentage
    /// @param _withdrawalFeePercentage the new withdrawalFeePercentage
    function setWithdrawalFeePercentage(uint256 _withdrawalFeePercentage)
        external
        onlyOwner
        validPercentage(_withdrawalFeePercentage)
    {
        withdrawalFeePercentage = _withdrawalFeePercentage;
    }

    /// @notice owner can set the withdrawalFeeReceiver
    /// @param _withdrawalFeeReceiver the new withdrawalFeeReceiver
    function setWithdrawalFeeReceiver(address _withdrawalFeeReceiver)
        external
        onlyOwner
        validAddress(_withdrawalFeeReceiver)
    {
        withdrawalFeeReceiver = _withdrawalFeeReceiver;
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

    /***********************************|
    |              INTERNAL             |
    |__________________________________*/

    /// @dev calculates a percentage amount of a number based on the 1e6 decimals expected
    /// @param amount the amount to calculate the percentage on
    /// @param percentage the desired percentage in 1e6
    /// @param rounding the rounding flag from Openzeppelin Math library, either Up or Down
    /// @return the percentage amount
    function _getPercentageAmount(
        uint256 amount,
        uint256 percentage,
        Math.Rounding rounding
    ) internal pure returns (uint256) {
        return
            amount.mulDiv(
                percentage,
                1e8, // percentage is in 1e6( 1% is 1_000_000) here we want to have 100% as denominator
                rounding
            );
    }

    /// @dev collects the withdrawal fee on assetsAmount and emits WithdrawalFeeCollected
    /// @param assetsAmount the amount of assets being withdrawn
    /// @param owner_ the owner of the assets
    /// @return the withdrawal assetsAmount amount AFTER deducting the fee
    function _collectWithdrawalFee(uint256 assetsAmount, address owner_)
        internal
        returns (uint256)
    {
        uint256 withdrawalFee = getWithdrawalFee(assetsAmount);

        IERC20Upgradeable(asset()).safeTransfer(
            withdrawalFeeReceiver,
            withdrawalFee
        );

        emit WithdrawalFeeCollected(owner_, withdrawalFee);

        return assetsAmount - withdrawalFee;
    }
}
