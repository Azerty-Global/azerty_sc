// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.22;

import "./interfaces/IStrategyToken.sol";
import "./interfaces/IStrategy.sol";
import { Owned } from "@solmate/src/auth/Owned.sol";
import { ERC4626 } from "@solmate/src/mixins/ERC4626.sol";
import { ERC20 } from "@solmate/src/tokens/ERC20.sol";
import { FixedPointMathLib } from "@solmate/src/utils/FixedPointMathLib.sol";
import { SafeTransferLib } from "@solmate/src/utils/SafeTransferLib.sol";

contract EUReVault is ERC4626, Owned {
    using FixedPointMathLib for uint256;
    using SafeTransferLib for ERC20;

    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    address internal CREDIT_MODULE;
    IStrategyToken public immutable STRATEGY_TOKEN;
    IStrategy public immutable STRATEGY;

    /* //////////////////////////////////////////////////////////////
                                STORAGE
    ////////////////////////////////////////////////////////////// */

    // Virtual shares/assets (also ghost shares) prevent against inflation attacks of ERC4626 vaults,
    // https://docs.openzeppelin.com/contracts/4.x/erc4626.
    uint256 public minCapitalInVault;
    bool internal isBalanced;

    uint32 internal lastSyncedTimestamp;

    /* //////////////////////////////////////////////////////////////
                                EVENTS
    ////////////////////////////////////////////////////////////// */

    event Log(string message, uint256 value);

    /* //////////////////////////////////////////////////////////////
                                MODIFIERS
    ////////////////////////////////////////////////////////////// */

    modifier onlyCreditModule() {
        require(msg.sender == CREDIT_MODULE, "EUReVault: Only Credit Module can call this function");
        _;
    }

    /* //////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */
    constructor(
        address underlyingAsset_,
        string memory name_,
        string memory symbol_,
        uint256 minCapitalInVault_,
        address strategyToken
    )
        ERC4626(ERC20(underlyingAsset_), name_, symbol_)
        Owned(msg.sender)
    {
        minCapitalInVault = minCapitalInVault_;
        STRATEGY_TOKEN = IStrategyToken(strategyToken);
        STRATEGY = IStrategy(IStrategyToken(strategyToken).POOL());
        minCapitalInVault = 100_000 * 10 ** decimals;
    }

    /* //////////////////////////////////////////////////////////////
                                LOGIC
    ////////////////////////////////////////////////////////////// */

    function capitalInVault() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function capitalInStrategy() public view returns (uint256) {
        return STRATEGY_TOKEN.balanceOf(address(this));
    }

    function totalAssets() public view override returns (uint256 assets) {
        assets = capitalInVault() + capitalInStrategy();
    }

    function setMinCapitalInVault(uint256 minCapital) external onlyOwner {
        minCapitalInVault = minCapital;
    }

    function flashCredit(uint256 amount) public onlyCreditModule {
        asset.safeTransfer(CREDIT_MODULE, amount);
    }

    function setCreditModule(address creditModule) external onlyOwner {
        CREDIT_MODULE = creditModule;
    }

    function _optimisticSync() internal {
        if (lastSyncedTimestamp != uint32(block.timestamp)) {
            uint256 capitalInStrategy_ = capitalInStrategy();
            uint256 capitalInVault_ = capitalInVault();
            uint256 totalAssets_ = totalAssets();
            emit Log("capitalInStrategy_", capitalInStrategy_);
            emit Log("capitalInVault_", capitalInVault_);
            emit Log("totalAssets_", totalAssets_);

            // TODO: Add a logic here if the percentage of in vault capital is more than inVaultPercentage
            // and capitalInVault is more than minCapitalInVault then transfer some assets to strategy
            // if capitalInVault is less than minCapitalInVault then transfer some assets from strategy to vault

            if (capitalInVault_ > minCapitalInVault) {
                uint256 toDeposit = capitalInVault_ - minCapitalInVault;
                ERC20(asset).safeApprove(address(STRATEGY), toDeposit);
                STRATEGY.deposit(address(asset), toDeposit, address(this), 0);
   
            } else if (capitalInStrategy_ > 0 && capitalInVault_ != minCapitalInVault) {
                uint256 missingCapital = minCapitalInVault - capitalInVault_;
                if (missingCapital > capitalInStrategy_) {
                    STRATEGY.withdraw(address(asset), capitalInStrategy_, address(this));
                    isBalanced = false;
                } else {
                    STRATEGY.withdraw(address(asset), missingCapital, address(this));
                    isBalanced = true;
                }
            }
        }
        lastSyncedTimestamp = uint32(block.timestamp);
    }

    //////////////////////////////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////

    function convertToShares(uint256 assets) public view override returns (uint256 shares) {
        // Cache totalSupply.
        uint256 supply = totalSupply;

        shares = supply == 0 ? assets : assets.mulDivDown(supply, totalAssets());
    }

    function convertToAssets(uint256 shares) public view override returns (uint256 assets) {
        // Cache totalSupply.
        uint256 supply = totalSupply;

        assets = supply == 0 ? shares : assets.mulDivDown(supply, totalAssets());
    }

    //////////////////////////////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////

    function previewDeposit(uint256 assets) public view override returns (uint256) {
        return convertToShares(assets);
    }

    function previewMint(uint256 shares) public view override returns (uint256 assets) {
        // Cache totalSupply.
        uint256 supply = totalSupply;

        assets = supply == 0 ? shares : assets.mulDivUp(supply, totalAssets());
    }

    function previewWithdraw(uint256 assets) public view override returns (uint256 shares) {
        // Cache totalSupply.
        uint256 supply = totalSupply;

        shares = supply == 0 ? assets : assets.mulDivUp(supply, totalAssets());
    }

    function previewRedeem(uint256 shares) public view override returns (uint256) {
        return convertToAssets(shares);
    }

    //////////////////////////////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////

    function deposit(uint256 assets, address receiver) public override returns (uint256 shares) {
        require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");

        asset.safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        // afterDeposit hook to balance the inVaultCapital
        _optimisticSync();
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public virtual override returns (uint256 shares) {
        require(STRATEGY_TOKEN.balanceOf(address(this)) >= assets, "Not enough funds in strategy to withdraw");

        // Withdraw from strategy
        STRATEGY.withdraw(address(asset), assets, address(this));

        shares = previewWithdraw(assets); // No need to check for rounding error, previewWithdraw rounds up.

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }

        beforeWithdraw(assets, shares);

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        asset.safeTransfer(receiver, assets);

        // afterDeposit hook to balance the inVaultCapital
        _optimisticSync();
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public virtual override returns (uint256 assets) {
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }

        // Check for rounding error since we round down in previewRedeem.
        require((assets = previewRedeem(shares)) != 0, "ZERO_ASSETS");
        require(STRATEGY_TOKEN.balanceOf(address(this)) >= assets, "Not enough funds in strategy to withdraw");
    
        // Withdraw from strategy
        STRATEGY.withdraw(address(asset), assets, address(this));
        // Recalculate the assets
        assets = previewRedeem(shares);

        beforeWithdraw(assets, shares);

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        asset.safeTransfer(receiver, assets);

        // afterDeposit hook to balance the inVaultCapital
        _optimisticSync();
    }
}
