// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

/// @title OutcomeToken
/// @notice ERC-1155 token representing YES/NO outcome shares for prediction markets
/// @dev Token ID encodes both marketId and outcome: (marketId << 1) | outcome
contract OutcomeToken is ERC1155 {
    // Constants for outcome types
    uint8 public constant YES = 0;
    uint8 public constant NO = 1;

    // Only the CPMM contract can mint/burn outcome tokens
    address public immutable cpmm;

    error UnauthorizedMinter();

    modifier onlyCPMM() {
        if (msg.sender != cpmm) revert UnauthorizedMinter();
        _;
    }

    constructor(address _cpmm) ERC1155("https://api.prediction.protocol/metadata/{id}") {
        cpmm = _cpmm;
    }

    /// @notice Encode marketId and outcome into a token ID
    /// @param marketId The unique identifier for the market
    /// @param outcome Either YES (0) or NO (1)
    /// @return tokenId The encoded token ID
    function encodeTokenId(bytes32 marketId, uint8 outcome) public pure returns (uint256) {
        // Hash-based encoding to avoid bit-shifting issues
        // This ensures unique token IDs for each market-outcome pair
        return uint256(keccak256(abi.encodePacked(marketId, outcome)));
    }

    /// @notice Decode a token ID back into marketId and outcome
    /// @dev Note: This function cannot actually decode - it's for interface compatibility
    /// @dev In practice, the contract tracks which tokens belong to which markets
    /// @param tokenId The encoded token ID
    /// @return marketId Zero (cannot decode from hash)
    /// @return outcome Zero (cannot decode from hash)
    function decodeTokenId(uint256 tokenId) public pure returns (bytes32 marketId, uint8 outcome) {
        // Cannot decode from a hash - return zeros
        // This function exists for interface compatibility but should not be relied upon
        marketId = bytes32(0);
        outcome = 0;
    }

    /// @notice Mint outcome tokens (only callable by CPMM contract)
    /// @param to The address to mint tokens to
    /// @param tokenId The token ID (encoded marketId + outcome)
    /// @param amount The amount of tokens to mint
    function mint(address to, uint256 tokenId, uint256 amount) external onlyCPMM {
        _mint(to, tokenId, amount, "");
    }

    /// @notice Burn outcome tokens (only callable by CPMM contract)
    /// @param from The address to burn tokens from
    /// @param tokenId The token ID (encoded marketId + outcome)
    /// @param amount The amount of tokens to burn
    function burn(address from, uint256 tokenId, uint256 amount) external onlyCPMM {
        _burn(from, tokenId, amount);
    }

    /// @notice Batch mint outcome tokens
    /// @param to The address to mint tokens to
    /// @param tokenIds Array of token IDs
    /// @param amounts Array of amounts
    function mintBatch(address to, uint256[] calldata tokenIds, uint256[] calldata amounts) external onlyCPMM {
        _mintBatch(to, tokenIds, amounts, "");
    }

    /// @notice Batch burn outcome tokens
    /// @param from The address to burn tokens from
    /// @param tokenIds Array of token IDs
    /// @param amounts Array of amounts
    function burnBatch(address from, uint256[] calldata tokenIds, uint256[] calldata amounts) external onlyCPMM {
        _burnBatch(from, tokenIds, amounts);
    }
}

