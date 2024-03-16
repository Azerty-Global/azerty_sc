// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.23 <0.9.0;

import { PRBTest } from "@prb/test/src/PRBTest.sol";
import { console2 } from "forge-std/src/console2.sol";
import { StdCheats } from "forge-std/src/StdCheats.sol";

import { EUReVault } from "../src/EUReVault.sol";
import { IStrategyToken } from "../src/interfaces/IStrategyToken.sol";
import { IStrategy } from "../src/interfaces/IStrategy.sol";
import { ERC20 } from "@solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "@solmate/src/utils/SafeTransferLib.sol";

contract StrategyToken is ERC20 {
    address public _POOL;

    constructor(address _pool) ERC20("StrategyToken", "sEURe", 18) {
        _POOL = _pool;
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external {
        _burn(account, amount);
    }

    function POOL() external view returns (address) {
        return _POOL;
    }
}

contract Strategy is IStrategy {
    using SafeTransferLib for ERC20;

    mapping(address => address) public _reserves;

    function addReserve(address asset, address strategy_token) external {
        _reserves[asset] = strategy_token;
    }

    event Log(string message, address value);
    event Log2(string message, uint256 value);

    function withdraw(address asset, uint256 amount, address to) external override returns (uint256) {
        emit Log("POOL", IStrategyToken(asset).POOL());
        emit Log("this", address(this));
        require(IStrategyToken(asset).POOL() == address(this), "Invalid asset");
        uint256 balance = ERC20(asset).balanceOf(address(this));
        require(balance >= amount, "Insufficient balance");
        IStrategyToken(asset).burn(address(this), amount);
        return amount;
    }

    function deposit(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external override {
        address strategy_token = _reserves[asset];
        require(IStrategyToken(strategy_token).POOL() == address(this), "Invalid asset");
        emit Log2("amount", amount);
        ERC20(asset).safeTransferFrom(onBehalfOf, address(this), amount);
        IStrategyToken(strategy_token).mint(onBehalfOf, amount);
    }
}

contract EUReToken is ERC20 {
    constructor(string memory name, string memory symbol, uint8 decimals) ERC20(name, symbol, decimals) { }
}

contract EUReVaultTest is PRBTest, StdCheats {
    EUReVault internal eurEVault;
    StrategyToken internal strategy_token;
    Strategy internal strategy;
    ERC20 internal EURe;

    address public depositUser = address(110_010);

    /// @dev A function invoked before each test case is run.
    function setUp() public virtual {
        // Instantiate the contract-under-test.
        EURe = new EUReToken("Monerium Euro", "EURe", 18);
        strategy = new Strategy();
        strategy_token = new StrategyToken(address(strategy));
        strategy.addReserve(address(EURe), address(strategy_token));
        eurEVault = new EUReVault(address(EURe), "EURe Vault", "eurEV", 10 ** 8, 100_000, address(strategy_token));
    }

    function test_contract_set() external {
        uint256 x = 100_000 * 10 ** 18;
        assertEq(eurEVault.minCapitalInVault(), x, "value mismatch");
    }

    function testFuzz_Deposit_OnlyToCapital() external {
        vm.startPrank(depositUser);
        deal(address(EURe), depositUser, type(uint128).max, true);
        EURe.approve(address(eurEVault), type(uint128).max);
        uint256 shares = eurEVault.deposit(100_000 * 10 ** 18, address(0));
        vm.stopPrank();
        assertEq(shares, 100_000 * 10 ** 18, "value mismatch");
        uint256 civ = eurEVault.capitalInVault();
        assertEq(civ, 100_000 * 10 ** 18, "value mismatch");
        uint256 cis = eurEVault.capitalInStrategy();
        assertEq(cis, 0, "value mismatch");
    }

    function testFuzz_Deposit_SomeGoesToStrategy() external {
        vm.startPrank(depositUser);
        deal(address(EURe), depositUser, type(uint128).max, true);
        EURe.approve(address(eurEVault), type(uint128).max);
        // First deposited values goes to vault reserve
        uint256 shares = eurEVault.deposit(100_000 * 10 ** 18, address(0));
        vm.stopPrank();
        assertEq(shares, 100_000 * 10 ** 18, "value mismatch");
        uint256 civ = eurEVault.capitalInVault();
        assertEq(civ, 100_000 * 10 ** 18, "value mismatch");
        uint256 cis = eurEVault.capitalInStrategy();
        assertEq(cis, 0, "value mismatch");

        vm.warp(block.timestamp + 1 minutes);
        // More value deposited goes to Strategy
        vm.startPrank(depositUser);
        uint256 newShares = eurEVault.deposit(100_000 * 10 ** 18, address(0));
        vm.stopPrank();
        assertEq(newShares, 100_000 * 10 ** 18, "value mismatch");
        uint256 newCiv = eurEVault.capitalInVault();
        // Should not change since we have not withdrawn
        assertEq(newCiv, 100_000 * 10 ** 18, "value mismatch");
        uint256 newCis = eurEVault.capitalInStrategy();
        assertEq(newCis, 100_000 * 10 ** 18, "value mismatch");
    }

    //    function testFuzz_Example(uint256 x) external {
    //        vm.assume(x != 0); // or x = bound(x, 1, 100)
    //        assertEq(foo.id(x), x, "value mismatch");
    //    }
    //
    //    /// @dev Fork test that runs against an Ethereum Mainnet fork. For this to work, you need to set
    // `API_KEY_ALCHEMY`
    //    /// in your environment You can get an API key for free at https://alchemy.com.
    //    function testFork_Example() external {
    //        // Silently pass this test if there is no API key.
    //        string memory alchemyApiKey = vm.envOr("API_KEY_ALCHEMY", string(""));
    //        if (bytes(alchemyApiKey).length == 0) {
    //            return;
    //        }
    //
    //        // Otherwise, run the test against the mainnet fork.
    //        vm.createSelectFork({ urlOrAlias: "mainnet", blockNumber: 16_428_000 });
    //        address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    //        address holder = 0x7713974908Be4BEd47172370115e8b1219F4A5f0;
    //        uint256 actualBalance = IERC20(usdc).balanceOf(holder);
    //        uint256 expectedBalance = 196_307_713.810457e6;
    //        assertEq(actualBalance, expectedBalance);
    //    }
}
