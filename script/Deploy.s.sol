// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.22 <0.9.0;

import { PRBTest } from "@prb/test/src/PRBTest.sol";
import { CreditModule } from "../src/CreditModule.sol";

contract Deploy is PRBTest {
    CreditModule public creditModule;
    address public oracleDAI = 0x678df3415fc31947dA4324eC63212874be5a82f8;
    address public oracleEURe = 0xab70BCB260073d036d1660201e9d5405F5829b7a;
    address public sDAI = 0xaf204776c7245bF4147c2612BF6e5972Ee483701;
    address public EURe = 0xcB444e90D8198415266c6a2724b7900fb12FC56E;
    
    function run() public {
        vm.startBroadcast(vm.envUint("TEST_PRIVATE_KEY"));
        creditModule = new CreditModule(oracleDAI, oracleEURe, sDAI, EURe);
        creditModule.setEureVault(0x1F7673Af4859f0ACD66bB01eda90a2694Ed271DB);
        vm.stopBroadcast();
    }
}
