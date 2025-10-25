// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../src/BinaryMarketCPMM.sol";
import "../../src/OutcomeToken.sol";
import "../mocks/MockERC20.sol";

/// @title TestSetup
/// @notice Helper contract to properly deploy CPMM and OutcomeToken with correct circular reference
abstract contract TestSetup is Test {
    function deploySystem(address usdc, address scheduler) 
        internal 
        returns (BinaryMarketCPMM cpmm, OutcomeToken outcomeToken) 
    {
        // Predict CPMM address based on current nonce
        address predictedCPMM = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);
        
        // Deploy OutcomeToken with predicted CPMM address
        outcomeToken = new OutcomeToken(predictedCPMM);
        
        // Deploy CPMM (must be next deployment to match prediction)
        cpmm = new BinaryMarketCPMM(usdc, address(outcomeToken), scheduler);
        
        require(address(cpmm) == predictedCPMM, "Address prediction failed");
        
        // Set test contract as marketFactory for testing
        cpmm.setMarketFactory(address(this));
    }
}

