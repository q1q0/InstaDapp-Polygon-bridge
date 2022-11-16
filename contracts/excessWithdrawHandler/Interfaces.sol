// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

interface IExcessWithdrawHandler {
    function allowedFulfillers(address _fulfiller) external view returns (bool);

    function fromVault(uint256 _amountToMove, uint256 _sharesToBurn) external;
}
