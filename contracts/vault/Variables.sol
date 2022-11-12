// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

contract Variables {
    /***********************************|
    |             CONSTANTS             |
    |__________________________________*/

    /// @notice upper limit of percentage values
    /// with 1e6 as base for percentage values 1e8 is 100%
    uint256 public constant maximumPercentageRange = 1e8;

    /***********************************|
    |           STATE VARIABLES         |
    |__________________________________*/

    /// @notice list of addresses that are allowed to access toMainnet and fromMainnet functions
    /// modifiable by owner
    mapping(address => bool) public allowedRebalancers;

    /// @notice percentage of token in 1e6 that should remain in the vault when transferring to mainnet.
    /// this number is given in 1e6, i.e. 1% would equal 1_000_000, 10% would be 10_000_000 etc.
    /// e.g.: if the threshold is 10% and the vault’s TVL is 1M USDC,
    /// then 900k USDC will be transferred to the mainnet iToken vaul
    /// and 100k USDC will sit idle here for instant withdraws for users.
    /// modifiable by owner
    uint256 public minimumThresholdPercentage;

    /// @notice address that receives the withdraw fee
    /// modifiable by owner
    address public withdrawFeeReceiver;

    /// @notice withdraw fee is either amount in percentage or absolute minimum. This var defines the percentage in 1e6
    /// this number is given in 1e6, i.e. 1% would equal 1_000_000, 10% would be 10_000_000 etc.
    /// modifiable by owner
    uint256 public withdrawFeePercentage;
    /// @notice withdraw fee is either amount in percentage or absolute minimum. This var defines the absolute minimum
    /// this number is given in decimals for the respective asset of the vault.
    /// modifiable by owner
    uint256 public withdrawFeeAbsoluteMin;

    /// @notice bridge address to which funds will be transferred to when calling toMainnet
    /// modifiable by owner
    address public bridgeAddress;

    /// @notice exchange price in asset.decimals
    /// modifiable by rebalancers
    uint256 public mainnetExchangePrice;

    /// @notice total (original) raw amount of assets currently committed to invest via bridge
    /// updated in fromMainnet and toMainnet
    uint256 internal investedAssets;
}
