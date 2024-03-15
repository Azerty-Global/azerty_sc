pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IStrategyToken
 * @author AZERTY
 * @notice Defines the basic interface for an IStrategyToken.
 */
interface IStrategyToken is IERC20 {
    function POOL() external view returns (address);

    function mintToTreasury(uint256 amount, uint256 index) external;

    function transferUnderlyingTo(address target, uint256 amount) external;

    function UNDERLYING_ASSET_ADDRESS() external view returns (address);

    function RESERVE_TREASURY_ADDRESS() external view returns (address);

    function DOMAIN_SEPARATOR() external view returns (bytes32);
}
