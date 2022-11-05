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

contract LiteVault is ERC4626Upgradeable, OwnableUpgradeable {
    using Math for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /***********************************|
    |             CONSTANTS             |
    |__________________________________*/
    uint256 maximumPercentageRange = 1e8; // with 1e6 as base for percentage values this is 100%

    /***********************************|
    |           STATE VARIABLES         |
    |__________________________________*/

    /// @notice list of addresses that are allowed to access toMainnet and fromMainnet functions
    mapping(address => bool) allowedRebalancers;

    /// @notice percentage of token in 1e6 that should remain in the vault when transferring to mainnet.
    /// this number is given in 1e6, i.e. 1% would equal 1_000_000, 10% would be 10_000_000 etc.
    /// e.g.: if the threshold is 10% and the vault’s TVL is 1M USDC,
    /// then 900k USDC will be transferred to the mainnet iToken vaul
    /// and 100k USDC will sit idle here for instant withdrawals for users.
    uint256 minimumThresholdPercentage;

    /// @notice address that receives the withdrawal fee
    address withdrawalFeeReceiver;

    /// @notice withdrawal fee is either amount in percentage or absolute minimum. This var defines the percentage in 1e6
    /// this number is given in 1e6, i.e. 1% would equal 1_000_000, 10% would be 10_000_000 etc.
    uint256 withdrawalFeePercentage;
    /// @notice withdrawal fee is either amount in percentage or absolute minimum. This var defines the absolute minimum
    /// this number is given in decimals for the respective asset of the vault.
    uint256 withdrawalFeeAbsoluteMin;

    /// @notice exchange price in asset.decimals
    uint256 mainnetExchangePrice;

    /// @notice total (original) raw amount of assets currently committed to invest via bridge
    uint256 internal investedAssets;

    /***********************************|
    |               EVENTS              |
    |__________________________________*/

    event WithdrawalFeeCollected(address indexed receiver, uint256 indexed fee);

    /***********************************|
    |              MODIFIERS            |
    |__________________________________*/

    modifier validAddress(address _address) {
        if (_address == address(0)) {
            revert LiteVault__InvalidParams();
        }
        _;
    }

    modifier validPercentage(uint256 percentage) {
        if (percentage > maximumPercentageRange) {
            revert LiteVault__InvalidParams();
        }
        _;
    }

    modifier onlyAllowedRebalancer() {
        if (!allowedRebalancers[msg.sender]) {
            revert LiteVault__Unauthorized();
        }
        _;
    }

    /***********************************|
    |    CONSTRUCTOR / INITIALIZERS     |
    |__________________________________*/

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

    function isAllowedRebalancer(address rebalancer) external returns (bool) {
        return allowedRebalancers[rebalancer];
    }

    function minimumThresholdAmount() external returns (uint256) {
        return
            _getPercentageAmount(
                totalPrincipal,
                minimumThresholdPercentage,
                Math.Rounding.Up
            );
    }

    /** @dev See {IERC4626-totalAssets}. */
    function totalAssets() public view override returns (uint256) {
        return _asset.balanceOf(address(this)) + totalInvestedAssets();
    }

    /// @notice amount of invested assets adjusted for exchangePrice
    function totalInvestedAssets() public view override returns (uint256) {
        // e.g. with an exchange price where the bridged assets are worth double by now
        // (because asset on bridge has appreciated in value through yield over time)
        // 100 * 200 / 1e2 = 20_000 / 100 = 200; (assuming decimals is 1e2 for simplicity)
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
    ) public virtual override returns (uint256) {
        // Logic below adapted from OpenZeppelin ERC4626Upgradeable, added logic for fee
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
    ) public virtual override returns (uint256) {
        // Logic below adapted from OpenZeppelin ERC4626Upgradeable, added logic for fee
        require(shares <= maxRedeem(owner_), "ERC4626: redeem more than max");

        uint256 assets = previewRedeem(shares);
        // burn full shares but only withdraw assetsAfterFee
        uint256 assetsAfterFee = _collectWithdrawalFee(assets, owner_);
        _withdraw(_msgSender(), receiver, owner_, assetsAfterFee, shares);

        return assetsAfterFee;
    }

    /***********************************|
    |          REBALANCER ONLY          |
    |__________________________________*/

    // deposit:
    // Create a simple iToken vault on Polygon where the user will deposit token
    // and get iToken in return (iToken = token/exchangePrice).

    function toMainnet(uint256 amountToMove) external onlyAllowedRebalancer {
        // Moving tokens to mainnet. At the time of moving, we need to store the raw token amount
        // that we are moving so we can calculate the overall income anytime.
        // `raw_token_amount = token_amount / mainnet_vault_exchange_price`

        // amount of principal left must cover at least minimumThresholdAmount
        uint256 principalLeft = totalPrincipal - amountToMove;
        if (principalLeft < minimumThresholdAmount()) {
            revert LiteVault__MinimumThreshold();
        }

        // approve amount to rebalancer
        IERC20Upgradeable(asset).safeIncreaseAllowance(
            msg.sender,
            amountToMove
        );

        // update the amount of bridged principal (raw amount)
        investedAssets += amountToMove;

        // the following would calculate the actual value of the amountToMove after bridging...
        // this is however not needed here?
        // e.g. with an exchange price where asset is only worth half after moving to mainnet
        // (because asset on bridge has appreciated in value through yield over time)
        // 100 * 1e2 / 200 = 10_000 / 200 = 50;  (assuming decimals is 1e2 for simplicity)
        // uint256 bridgedAmount = amountToMove.mulDiv(
        //     decimals(),
        //     mainnetExchangePrice,
        //     Math.Rounding.Down
        // );
    }

    function fromMainnet(uint256 amountToMove) external onlyAllowedRebalancer {
        // Getting tokens back from mainnet. Deposit the tokens in the Polygon vault and
        // subtract the amount_raw according to `token_amount / mainnet_vault_exchange_price.`

        // transferFrom rebalancer
        IERC20Upgradeable(asset).safeTransferFrom(
            msg.sender,
            address(this),
            amountToMove
        );

        // update the amount of bridged principal (raw amount)
        investedAssets -= amountToMove;

        // The following has to be done on bridge (rebalancer) and the result bridgedAmount
        // would be the expected amount in this function "amountToMove"
        // e.g. with an exchange price where asset is worth double after moving from mainnet
        // (because asset on bridge has appreciated in value through yield over time)
        // 100 * 200 / 1e2 = 20_000 / 100 = 200; (assuming decimals is 1e2 for simplicity)
        // uint256 bridgedAmount = amountToMove.mulDiv(
        //     mainnetExchangePrice,
        //     decimals(),
        //     Math.Rounding.Down
        // );
    }

    function updateMainnetExchangePrice(uint256 _mainnetExchangePrice)
        external
        onlyAllowedRebalancer
    {
        mainnetExchangePrice = _mainnetExchangePrice;
    }

    /***********************************|
    |             OWNER ONLY            |
    |__________________________________*/

    function setMinimumThresholdPercentage(uint256 _minimumThresholdPercentage)
        external
        onlyOwner
        validPercentage(_minimumThresholdPercentage)
    {
        minimumThresholdPercentage = _minimumThresholdPercentage;
    }

    function setRebalancer(address rebalancer, bool allowed)
        external
        onlyOwner
    {
        allowedRebalancers[rebalancer] = allowed;
    }

    function setWithdrawalFeeAbsoluteMin(uint256 _withdrawalFeeAbsoluteMin)
        external
        onlyOwner
    {
        withdrawalFeeAbsoluteMin = _withdrawalFeeAbsoluteMin;
    }

    function setWithdrawalFeePercentage(uint256 _withdrawalFeePercentage)
        external
        onlyOwner
        validPercentage(_withdrawalFeePercentage)
    {
        withdrawalFeePercentage = _withdrawalFeePercentage;
    }

    function setWithdrawalFeeReceiver(address _withdrawalFeeAddress)
        external
        onlyOwner
        validAddress(_withdrawalFeeAddress)
    {
        withdrawalFeeAddress = _withdrawalFeeAddress;
    }

    /***********************************|
    |              INTERNAL             |
    |__________________________________*/

    function _getWithdrawalFee(uint256 withdrawAmount) returns (uint256) {
        uint256 withdrawalFee = _getPercentageAmount(
            withdrawAmount,
            withdrawalFeePercentage,
            Math.Rounding.Up
        );

        return Math.max(withdrawalFee, withdrawalFeeAbsoluteMin);
    }

    function _getPercentageAmount(
        uint256 amount,
        uint256 percentage,
        Math.Rounding rounding
    ) {
        return
            amount.mulDiv(
                percentage,
                1e8, // percentage is in 1e6( 1% is 1_000_000) here we want to have 100% as denominator
                rounding
            );
    }

    function _collectWithdrawalFee(uint256 assets, address owner_)
        returns (uint256)
    {
        uint256 withdrawalFee = _getWithdrawalFee(assets);

        IERC20Upgradeable(asset).safeTransfer(
            withdrawalFeeReceiver,
            withdrawalFee
        );

        emit WithdrawalFeeCollected(owner_, withdrawalFee);

        return assets - withdrawalFee;
    }
}
