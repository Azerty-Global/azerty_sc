pragma solidity ^0.8.0;

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

    // Virtual shares/assets (also ghost shares) prevent against inflation attacks of ERC4626 vaults,
    // https://docs.openzeppelin.com/contracts/4.x/erc4626.
    uint256 internal immutable VAS;

    uint256 public minCapitalInVault;
    uint256 public inVaultPercentage;
    uint256 internal hundredPercentage = 100_000_000;
    bool internal isBalanced;

    uint32 internal lastSyncedTimestamp;

    address internal immutable CREDIT_MODULE;

    IStrategyToken public immutable STRATEGY_TOKEN;
    IStrategy public immutable STRATEGY;

    constructor(
        address underlyingAsset_,
        string memory name_,
        string memory symbol_,
        uint256 vas,
        uint256 minCapitalInVault_,
        address sittingStrategyToken
    )
        ERC4626(ERC20(underlyingAsset_), name_, symbol_)
        Owned(msg.sender)
    {
        VAS = vas;
        minCapitalInVault = minCapitalInVault_;
        STRATEGY_TOKEN = IStrategyToken(sittingStrategyToken);
        STRATEGY = IStrategy(IStrategyToken(sittingStrategyToken).POOL());
        inVaultPercentage = 10_000_000;
        minCapitalInVault = 100_000 * 10 ** decimals;
    }

    modifier onlyCreditModule() {
        require(msg.sender == CREDIT_MODULE, "EUReVault: Only Credit Module can call this function");
        _;
    }

    event Log(string message, uint256 value);

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
                emit Log("percentage", capitalInVault_);
                uint256 toStrategy = capitalInVault_ - minCapitalInVault;
                STRATEGY.deposit(address(asset), toStrategy, address(this), 0);
                //                emit Log("percentage", percentage);
                //                if (percentage > inVaultPercentage) {
                //                    emit Log("capitalInVault_ > minCapitalInVault", capitalInVault_);
                //                    uint256 necessaryInVaultCapital = inVaultPercentage * totalAssets_ /
                // hundredPercentage;
                //                    emit Log("necessaryInVaultCapital", necessaryInVaultCapital);
                //                    uint256 assetsToTransfer = capitalInVault_ - necessaryInVaultCapital;
                //                    STRATEGY.deposit(address(asset), assetsToTransfer, address(this), uint16(0));
                //                    isBalanced = true;
                //                } else {
                //                    uint256 necessaryInVaultCapital = inVaultPercentage * totalAssets_ /
                // hundredPercentage;
                //                    uint256 assetsToTransfer = necessaryInVaultCapital - capitalInVault_;
                //                    STRATEGY.withdraw(address(asset), assetsToTransfer, address(this));
                //                    isBalanced = true;
                //                }
            } else {
                if (capitalInStrategy_ > 0) {
                    uint256 necessaryInVaultCapital = minCapitalInVault - capitalInVault_;
                    if (necessaryInVaultCapital > capitalInStrategy_) {
                        STRATEGY.withdraw(address(asset), capitalInStrategy_, address(this));
                        isBalanced = false;
                    } else {
                        STRATEGY.withdraw(address(asset), necessaryInVaultCapital, address(this));
                        isBalanced = true;
                    }
                }
            }
            lastSyncedTimestamp = uint32(block.timestamp);
        }
    }

    function capitalInVault() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function capitalInStrategy() public view returns (uint256) {
        return STRATEGY_TOKEN.balanceOf(address(this));
    }

    function totalAssets() public view override returns (uint256 assets) {
        assets = capitalInVault() + capitalInStrategy();
    }

    //////////////////////////////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////

    function convertToShares(uint256 assets) public view override returns (uint256 shares) {
        // Cache totalSupply.
        uint256 supply = totalSupply;

        shares = supply == 0 ? assets : assets.mulDivDown(supply + VAS, totalAssets() + VAS);
    }

    function convertToAssets(uint256 shares) public view override returns (uint256 assets) {
        // Cache totalSupply.
        uint256 supply = totalSupply;

        assets = supply == 0 ? shares : assets.mulDivDown(supply + VAS, totalAssets() + VAS);
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

        assets = supply == 0 ? shares : assets.mulDivUp(supply + VAS, totalAssets() + VAS);
    }

    function previewWithdraw(uint256 assets) public view override returns (uint256 shares) {
        // Cache totalSupply.
        uint256 supply = totalSupply;

        shares = supply == 0 ? assets : assets.mulDivUp(supply + VAS, totalAssets() + VAS);
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
        //        _optimisticSync();
        require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");

        //        IERC20(address(asset())).transferFrom(msg.sender, address(this), assets);
        asset.safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        // afterDeposit hook to balance the inVaultCapital
        _optimisticSync();
    }

    function withdraw(uint256 assets, address receiver, address owner_) public override returns (uint256 shares) {
        require(capitalInVault() - assets > minCapitalInVault, "Not enough capital in vault");
        shares = previewWithdraw(assets);

        _burn(owner_, shares);

        //        IERC20(address(asset())).transfer(receiver, assets);
        asset.safeTransfer(receiver, assets);
        _optimisticSync();

        // implement withdrawing assets
        // Check conditions for withdrawing assets from vault
        // if percentage and minCapitalInVault conditions are met then withdraw assets from vault

        emit Withdraw(msg.sender, receiver, owner_, assets, shares);
    }

    function redeem(uint256 assets, address receiver, address owner_) public override returns (uint256 shares) {
        require(capitalInVault() - assets > minCapitalInVault, "Not enough capital in vault");
        shares = previewWithdraw(assets);

        _burn(owner_, shares);

        //        IERC20(address(asset())).transfer(receiver, assets);
        asset.safeTransfer(receiver, assets);
        _optimisticSync();

        // implement withdrawing assets
        // Check conditions for withdrawing assets from vault
        // if percentage and minCapitalInVault conditions are met then withdraw assets from vault

        emit Withdraw(msg.sender, receiver, owner_, assets, shares);
    }

    function flashCredit(uint256 amount) public onlyCreditModule {
        require(capitalInVault() >= amount, "Not enough EURe in the contract");
        //        IERC20(asset()).transfer(CREDIT_MODULE, amount);
        asset.safeTransfer(CREDIT_MODULE, amount);
    }
}
