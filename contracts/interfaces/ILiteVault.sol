// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import {IERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/interfaces/IERC4626Upgradeable.sol";

interface ILiteVault is IERC4626Upgradeable {
    function minimumThresholdAmount() external view returns (uint256);
}
