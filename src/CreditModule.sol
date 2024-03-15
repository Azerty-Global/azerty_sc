// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.22;

import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IChainlinkData } from "./interfaces/IChainlinkData.sol";
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

    address public eureVault;

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

        vaultBalanceDiscountFactor = 7_000;
    }

    /* //////////////////////////////////////////////////////////////
                                LOGIC
    ////////////////////////////////////////////////////////////// */

    function canSafePay(address safe, uint256 amount) external view returns (bool canPay, address currency) {
        // Pay directly with EURe if enough balance
        if (EUR_E.balanceOf(safe) >= amount) return (true, address(EUR_E));

        // If enough SDAI balance in Safe to repay at current rate and CreditModule holds enough funds =>  CreditModule will advance the EURe.
        uint256 daiBalance = S_DAI.maxWithdraw(safe);
        (, int256 rate,,,) = DAI_USD_ORACLE.latestRoundData();
        uint256 daiToUsd = daiBalance * uint256(rate) / daiOracleDecimals;
        (, rate,,,) = EURE_USD_ORACLE.latestRoundData();
        uint256 usdToEure = daiToUsd * eureOracleDecimals / uint256(rate);

        

        uint256 eureAvailableInVault = EUR_E.balanceOf(eureVault);
        uint256 eureDiscountedAmount = eureAvailableInVault * vaultBalanceDiscountFactor / 10_000;

        if (usdToEure > amount && eureDiscountedAmount >= amount) return (true, address(S_DAI));

        // If none of the above valid, Safe can't pay.
        return (false, address(0));
    }

    function pay(address safe, uint256 amount, address currency, address to) external {
        if (currency == address(EUR_E)) _payThroughSafe(safe, amount, to);
        if (currency == address(S_DAI)) _payThroughCreditModule(safe, amount, to);
    }

    function _payThroughSafe(address safe, uint256 amount, address to) internal {
        EUR_E.safeTransferFrom(safe, to, amount);
    }

    function _payThroughCreditModule(address safe, uint256 amount, address to) internal {
        // Get EURe from the Vault
        IVault(vault).flashCredit(amount);

        // Pay with EURe for the Safe
        EUR_E.transfer(to, amount);

        // Get SDAI from the Safe

    }
}