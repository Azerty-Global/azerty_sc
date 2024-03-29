// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.22;

interface IVault {
    function flashCredit(uint256 amount) external;
}
