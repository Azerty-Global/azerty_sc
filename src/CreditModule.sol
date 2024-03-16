// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.22;

import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IChainlinkData } from "./interfaces/IChainlinkData.sol";
import { IVault } from "./interfaces/IVault.sol";
import { IBalancerVault } from "./interfaces/IBalancerVault.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract CreditorModule {
    using SafeERC20 for ERC20;
    /* //////////////////////////////////////////////////////////////
                               CONSTANTS
    ////////////////////////////////////////////////////////////// */

    IChainlinkData public immutable DAI_USD_ORACLE;
    IChainlinkData public immutable EURE_USD_ORACLE;

    uint256 public daiOracleDecimals;
    uint256 public eureOracleDecimals;

    ERC4626 public immutable S_DAI;
    ERC20 public immutable EUR_E;

    address payable public eureVault;
    address public balancerVault = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    /* //////////////////////////////////////////////////////////////
                                STORAGE
    ////////////////////////////////////////////////////////////// */

    uint256 public vaultBalanceDiscountFactor;

    /* //////////////////////////////////////////////////////////////
                                EVENTS
    ////////////////////////////////////////////////////////////// */

    /* //////////////////////////////////////////////////////////////
                                MODIFIERS
    ////////////////////////////////////////////////////////////// */

    /* //////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    constructor(address oracleDAI, address oracleEURe, address sDAI_, address EURe_) {
        DAI_USD_ORACLE = IChainlinkData(oracleDAI);
        EURE_USD_ORACLE = IChainlinkData(oracleEURe);

        daiOracleDecimals = 10 ** DAI_USD_ORACLE.decimals();
        eureOracleDecimals = 10 ** EURE_USD_ORACLE.decimals();

        S_DAI = ERC4626(sDAI_);
        EUR_E = ERC20(EURe_);

        vaultBalanceDiscountFactor = 7000;
    }

    /* //////////////////////////////////////////////////////////////
                                LOGIC
    ////////////////////////////////////////////////////////////// */

    function getConversionRateSDaiToEur() public view returns (uint256 conversionRate) {
        uint256 sdaiToDai = S_DAI.convertToAssets(1e18);
        (, int256 rate,,,) = DAI_USD_ORACLE.latestRoundData();
        uint256 sdaiToUsd = (sdaiToDai * uint256(rate)) / daiOracleDecimals;
        (, rate,,,) = EURE_USD_ORACLE.latestRoundData();
        conversionRate = (sdaiToUsd * eureOracleDecimals) / uint256(rate);
    }

    function canSafePay(
        address safe,
        uint256 amount
    )
        external
        view
        returns (bool canPay, address currency, uint256 conversionRate)
    {
        // Pay directly with EURe if enough balance
        if (EUR_E.balanceOf(safe) >= amount) return (true, address(EUR_E), 0);

        // If enough SDAI balance in Safe to repay at current rate and CreditModule holds enough funds =>  CreditModule
        // will advance the EURe.
        uint256 sdaiBalance = S_DAI.balanceOf(safe);
        uint256 sdaiToEureRate = getConversionRateSDaiToEur();
        uint256 eureAmount = (sdaiBalance * sdaiToEureRate) / 1e18;

        // TODO: Take an extra cut to compensate potential loss of price diff between BalancerV2 & Chainlink

        // TODO : Check quote on Balancer

        // TODO: apply fee
        uint256 eureAvailableInVault = EUR_E.balanceOf(eureVault);
        uint256 eureDiscountedAmount = eureAvailableInVault * vaultBalanceDiscountFactor / 10_000;

        if (eureAmount >= amount && eureDiscountedAmount >= amount) return (true, address(S_DAI), sdaiToEureRate);

        // If none of the above valid, Safe can't pay.
        return (false, address(0), 0);
    }

    function pay(address safe, uint256 amount, address currency, address to, uint256 conversionRate) external {
        if (currency == address(EUR_E)) _payThroughSafe(safe, amount, to);
        if (currency == address(S_DAI)) _payThroughCreditModule(safe, amount, to, conversionRate);
    }

    function _payThroughSafe(address safe, uint256 amount, address to) internal {
        EUR_E.safeTransferFrom(safe, to, amount);
    }

    function _payThroughCreditModule(address safe, uint256 amount, address to, uint256 conversionRate) internal {
        // Get EURe from the Vault
        IVault(eureVault).flashCredit(amount);

        // Pay with EURe for the Safe
        EUR_E.transfer(to, amount);

        // Get SDAI + fee from the Safe
        uint256 eureToSdai = (amount * 1e18) / conversionRate;
        // TODO: fee
        S_DAI.transferFrom(safe, address(this), eureToSdai);

        // Swap SDAI to EURe
        IBalancerVault.SingleSwap memory singleSwap = IBalancerVault.SingleSwap({
            poolId : 0xdd439304a77f54b1f7854751ac1169b279591ef7000000000000000000000064,
            kind : IBalancerVault.SwapKind.GIVEN_IN,
            assetIn : address(S_DAI),
            assetOut : address(EUR_E),
            amount : eureToSdai,
            userData : ""
        });

        // Amount is swapped directly to Vault
        IBalancerVault.FundManagement memory funds = IBalancerVault.FundManagement({
            sender : address(this),
            fromInternalBalance : false,
            recipient : eureVault,
            toInternalBalance : false
        });

        IBalancerVault(balancerVault).swap(singleSwap, funds, 0, block.timestamp);
    }
}
