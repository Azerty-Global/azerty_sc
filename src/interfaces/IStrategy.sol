pragma solidity ^0.8.20;

/**
 * @title IStrategy
 * @author AZERTY
 * @notice Defines the basic interface for an IStrategy
 */
interface IStrategy {
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
    function deposit(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
}
