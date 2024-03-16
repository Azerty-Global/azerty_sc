pragma solidity ^0.8.20;

import "solmate/src/tokens/ERC20.sol";

/**
 * @title IStrategyToken
 * @author AZERTY
 * @notice Defines the basic interface for an IStrategyToken.
 */
interface IStrategyToken {
    function POOL() external view returns (address);
    function balanceOf(address account) external view returns (uint256);
    function safeTransferFrom(address from, address to, uint256 amount) external;
    function safeTransfer(address to, uint256 amount) external;
    function mint(address account, uint256 amount) external;
    function burn(address account, uint256 amount) external;
}
