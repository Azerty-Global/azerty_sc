pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IStrategyToken.sol";
import "./interfaces/IStrategy.sol";

contract EUReVault is ERC4626, Ownable {
    using Math for uint256;

    // Virtual shares/assets (also ghost shares) prevent against inflation attacks of ERC4626 vaults,
    // https://docs.openzeppelin.com/contracts/4.x/erc4626.
    uint256 internal immutable VAS;

    uint256 public minCapitalInVault;
    uint256 public inVaultPercentage;
    bool internal isBalanced;

    uint32 internal lastSyncedTimestamp;

    address internal immutable CREDIT_MODULE;

    IStrategyToken public immutable STRATEGY_TOKEN;
    IStrategy public immutable STRATEGY;

    constructor(
        address underlyingAsset_,
        uint256 vas,
        uint256 minCapitalInVault_,
        address sittingStrategyToken
    )
        ERC4626(ERC20(underlyingAsset_))
        Ownable(msg.sender)
    {
        VAS = vas;
        _name = string(abi.encodePacked("Safe EURe Vault"));
        _symbol = string(abi.encodePacked("sEURe"));
        minCapitalInVault = minCapitalInVault_;
        STRATEGY_TOKEN = IStrategyToken(sittingStrategyToken);
        STRATEGY = IStrategyToken(sittingStrategyToken).POOL();
        inVaultPercentage = 10_000_000;
        minCapitalInVault = 100_000 * 10 ** decimals();
    }

    modifier onlyCreditModule() {
        require(msg.sender == CREDIT_MODULE, "EUReVault: Only Credit Module can call this function");
        _;
    }

    function _optimisticSync() internal {
        if (lastSyncedTimestamp != uint32(block.timestamp)) {
            uint256 capitalInStrategy_ = capitalInStrategy();
            uint256 capitalInVault_ = capitalInVault();

            // TODO: Add a logic here if the percentage of in vault capital is more than inVaultPercentage
            // and capitalInVault is more than minCapitalInVault then transfer some assets to strategy
            // if capitalInVault is less than minCapitalInVault then transfer some assets from strategy to vault
        }
    }

    function capitalInVault() public view returns (uint256) {
        return IERC20(address(asset)).balanceOf(address(this));
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

        assets = supply == 0 ? shares : shares.mulDivDown(totalAssets() + VAS, supply + VAS);
    }

    //////////////////////////////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////

    function previewDeposit(uint256 assets) public view virtual returns (uint256) {
        return convertToShares(assets);
    }

    function previewMint(uint256 shares) public view override returns (uint256 assets) {
        // Cache totalSupply.
        uint256 supply = totalSupply;

        assets = supply == 0 ? shares : shares.mulDivUp(totalAssets() + VAS, supply + VAS);
    }

    function previewWithdraw(uint256 assets) public view override returns (uint256 shares) {
        // Cache totalSupply.
        uint256 supply = totalSupply;

        shares = supply == 0 ? assets : assets.mulDivUp(supply + VAS, totalAssets() + VAS);
    }

    function previewRedeem(uint256 shares) public view virtual returns (uint256) {
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
    }

    function withdraw(uint256 assets, address receiver, address owner_) public override returns (uint256 shares) {
        shares = previewWithdraw(assets);

        _burn(owner_, shares);

        // implement withdrawing assets
        // Check conditions for withdrawing assets from vault
        // if percentage and minCapitalInVault conditions are met then withdraw assets from vault

        emit Withdraw(msg.sender, receiver, owner_, assets, shares);
    }

    function redeem(uint256 assets, address receiver, address owner_) public override returns (uint256 shares) {
        shares = previewWithdraw(assets);

        _burn(owner_, shares);

        // implement withdrawing assets
        // Check conditions for withdrawing assets from vault
        // if percentage and minCapitalInVault conditions are met then withdraw assets from vault

        emit Withdraw(msg.sender, receiver, owner_, assets, shares);
    }

    function flashCredit(uint256 amount) public onlyCreditModule {
        require(balanceBefore >= amount, "Not enough EURe in the contract");
        asset.safeTransfer(CREDIT_MODULE, amount);
    }
}
