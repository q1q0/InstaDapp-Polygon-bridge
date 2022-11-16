// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import {IERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/interfaces/IERC4626Upgradeable.sol";

interface ILiteVault is IERC4626Upgradeable {
    function minimumThresholdAmount() external view returns (uint256);

    function allowedRebalancers(address _rebalancer)
        external
        view
        returns (bool);

    function fromMainnet(uint256 _amountToMove) external;

    function toMainnet(uint256 _amountToMove) external;

    function redeemExcess(uint256 _amountToMove, uint256 _sharesToBurn)
        external;
}
