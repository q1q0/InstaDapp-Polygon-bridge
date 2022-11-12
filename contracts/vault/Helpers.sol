// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract Helpers {
    using Math for uint256;

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
}
