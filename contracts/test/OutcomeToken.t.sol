// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/OutcomeToken.sol";

contract OutcomeTokenTest is Test {
    OutcomeToken public token;
    address public cpmm;
    address public user1;
    address public user2;

    bytes32 constant MARKET_ID = keccak256("test-market");

    function setUp() public {
        cpmm = makeAddr("cpmm");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        token = new OutcomeToken(cpmm);
    }

    function test_ConstructorSetsImmutables() public view {
        assertEq(token.cpmm(), cpmm);
        assertEq(token.YES(), 0);
        assertEq(token.NO(), 1);
    }

    function test_EncodeTokenId() public view {
        uint256 yesTokenId = token.encodeTokenId(MARKET_ID, token.YES());
        uint256 noTokenId = token.encodeTokenId(MARKET_ID, token.NO());

        // Tokens should be different hashes
        assertTrue(yesTokenId != noTokenId);
        assertGt(yesTokenId, 0);
        assertGt(noTokenId, 0);
    }

    function test_EncodeIsConsistent() public view {
        // Same inputs should produce same outputs
        uint256 tokenId1 = token.encodeTokenId(MARKET_ID, token.YES());
        uint256 tokenId2 = token.encodeTokenId(MARKET_ID, token.YES());
        assertEq(tokenId1, tokenId2);

        // Different outcomes should produce different tokens
        uint256 yesToken = token.encodeTokenId(MARKET_ID, token.YES());
        uint256 noToken = token.encodeTokenId(MARKET_ID, token.NO());
        assertTrue(yesToken != noToken);
    }

    function test_DifferentMarketsProduceDifferentTokens() public view {
        bytes32 market1 = keccak256("market1");
        bytes32 market2 = keccak256("market2");

        uint256 market1Yes = token.encodeTokenId(market1, token.YES());
        uint256 market2Yes = token.encodeTokenId(market2, token.YES());

        assertTrue(market1Yes != market2Yes);
    }

    function test_MintFromCPMM() public {
        uint256 tokenId = token.encodeTokenId(MARKET_ID, token.YES());
        uint256 amount = 100e6;

        vm.prank(cpmm);
        token.mint(user1, tokenId, amount);

        assertEq(token.balanceOf(user1, tokenId), amount);
    }

    function test_MintRevertsFromNonCPMM() public {
        uint256 tokenId = token.encodeTokenId(MARKET_ID, token.YES());

        vm.prank(user1);
        vm.expectRevert(OutcomeToken.UnauthorizedMinter.selector);
        token.mint(user1, tokenId, 100e6);
    }

    function test_BurnFromCPMM() public {
        uint256 tokenId = token.encodeTokenId(MARKET_ID, token.NO());
        uint256 amount = 50e6;

        // Mint first
        vm.prank(cpmm);
        token.mint(user1, tokenId, amount);

        // Then burn
        vm.prank(cpmm);
        token.burn(user1, tokenId, amount);

        assertEq(token.balanceOf(user1, tokenId), 0);
    }

    function test_BurnRevertsFromNonCPMM() public {
        uint256 tokenId = token.encodeTokenId(MARKET_ID, token.NO());

        vm.prank(cpmm);
        token.mint(user1, tokenId, 100e6);

        vm.prank(user1);
        vm.expectRevert(OutcomeToken.UnauthorizedMinter.selector);
        token.burn(user1, tokenId, 50e6);
    }

    function test_BatchMint() public {
        bytes32 market1 = keccak256("market1");
        bytes32 market2 = keccak256("market2");

        uint256[] memory tokenIds = new uint256[](3);
        tokenIds[0] = token.encodeTokenId(market1, token.YES());
        tokenIds[1] = token.encodeTokenId(market1, token.NO());
        tokenIds[2] = token.encodeTokenId(market2, token.YES());

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 100e6;
        amounts[1] = 200e6;
        amounts[2] = 300e6;

        vm.prank(cpmm);
        token.mintBatch(user1, tokenIds, amounts);

        assertEq(token.balanceOf(user1, tokenIds[0]), amounts[0]);
        assertEq(token.balanceOf(user1, tokenIds[1]), amounts[1]);
        assertEq(token.balanceOf(user1, tokenIds[2]), amounts[2]);
    }

    function test_BatchBurn() public {
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = token.encodeTokenId(MARKET_ID, token.YES());
        tokenIds[1] = token.encodeTokenId(MARKET_ID, token.NO());

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100e6;
        amounts[1] = 200e6;

        // Mint first
        vm.startPrank(cpmm);
        token.mintBatch(user1, tokenIds, amounts);

        // Then burn
        token.burnBatch(user1, tokenIds, amounts);
        vm.stopPrank();

        assertEq(token.balanceOf(user1, tokenIds[0]), 0);
        assertEq(token.balanceOf(user1, tokenIds[1]), 0);
    }

    function test_ERC1155Transfer() public {
        uint256 tokenId = token.encodeTokenId(MARKET_ID, token.YES());

        vm.prank(cpmm);
        token.mint(user1, tokenId, 100e6);

        // User1 transfers to user2
        vm.prank(user1);
        token.safeTransferFrom(user1, user2, tokenId, 30e6, "");

        assertEq(token.balanceOf(user1, tokenId), 70e6);
        assertEq(token.balanceOf(user2, tokenId), 30e6);
    }

    function test_MultipleMarketsDoNotConflict() public {
        bytes32 market1 = keccak256("market1");
        bytes32 market2 = keccak256("market2");

        uint256 market1Yes = token.encodeTokenId(market1, token.YES());
        uint256 market2Yes = token.encodeTokenId(market2, token.YES());

        // Ensure different markets produce different token IDs even for same outcome
        assertTrue(market1Yes != market2Yes);

        vm.startPrank(cpmm);
        token.mint(user1, market1Yes, 100e6);
        token.mint(user1, market2Yes, 200e6);
        vm.stopPrank();

        assertEq(token.balanceOf(user1, market1Yes), 100e6);
        assertEq(token.balanceOf(user1, market2Yes), 200e6);
    }

    function testFuzz_EncodeIsConsistent(bytes32 marketId, uint8 rawOutcome) public view {
        // Bound outcome to 0 or 1
        uint8 outcome = rawOutcome % 2;

        // Same inputs should always produce same token ID
        uint256 tokenId1 = token.encodeTokenId(marketId, outcome);
        uint256 tokenId2 = token.encodeTokenId(marketId, outcome);

        assertEq(tokenId1, tokenId2);

        // Different outcomes should produce different token IDs
        uint8 otherOutcome = outcome == 0 ? 1 : 0;
        uint256 otherTokenId = token.encodeTokenId(marketId, otherOutcome);
        assertTrue(tokenId1 != otherTokenId);
    }
}

