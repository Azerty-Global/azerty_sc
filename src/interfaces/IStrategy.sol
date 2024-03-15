pragma solidity ^0.8.20;

/**
 * @title IStrategy
 * @author AZERTY
 * @notice Defines the basic interface for an IStrategy
 */
interface IStrategy {
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;

    function supplyWithPermit(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode,
        uint256 deadline,
        uint8 permitV,
        bytes32 permitR,
        bytes32 permitS
    )
        external;

    function withdraw(address asset, uint256 amount, address to) external returns (uint256);

    function borrow(
        address asset,
        uint256 amount,
        uint256 interestRateMode,
        uint16 referralCode,
        address onBehalfOf
    )
        external;

    function deposit(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
}
