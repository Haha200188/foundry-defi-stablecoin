//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {Test} from "forge-std/Test.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dscEngine,) = deployer.run();
    }
}
