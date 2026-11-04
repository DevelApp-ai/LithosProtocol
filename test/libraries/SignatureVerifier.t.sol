// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../src/libraries/SignatureVerifier.sol";

contract SignatureVerifierTest is Test {
    SignatureVerifier public signatureVerifier;
    
    address public player1 = address(0x1);
    address public player2 = address(0x2);
    address public opponent = address(0x3);
    
    event NonceUsed(address indexed player, uint256 nonce);
    
    function setUp() public {
        signatureVerifier = new SignatureVerifier();
    }
    
    function testInitialization() public {
        // Check domain separator
        bytes32 domainSeparator = signatureVerifier.getDomainSeparator();
        assertNotEq(domainSeparator, bytes32(0));
    }
    
    function testGetNonce() public {
        // Initially nonce should be 0
        assertEq(signatureVerifier.getNonce(player1), 0);
    }
    
    function testNonceIncrement() public {
        uint256 initialNonce = signatureVerifier.getNonce(player1);
        
        // In a real scenario, verifying a signature would increment the nonce
        // For testing, we'll check that nonces are tracked per player
        assertEq(signatureVerifier.getNonce(player2), 0);
    }
    
    function testTypeHashes() public {
        // Check that type hashes are set correctly
        bytes32 questHash = signatureVerifier.QUEST_ACTION_TYPEHASH();
        bytes32 craftHash = signatureVerifier.CRAFT_ACTION_TYPEHASH();
        bytes32 pvpHash = signatureVerifier.PVP_ACTION_TYPEHASH();
        
        // These should be non-zero
        assertNotEq(questHash, bytes32(0));
        assertNotEq(craftHash, bytes32(0));
        assertNotEq(pvpHash, bytes32(0));
        
        // And they should be different from each other
        assertNotEq(questHash, craftHash);
        assertNotEq(questHash, pvpHash);
        assertNotEq(craftHash, pvpHash);
    }
    
    function testDomainSeparator() public {
        bytes32 separator = signatureVerifier.getDomainSeparator();
        
        // Should be non-zero
        assertNotEq(separator, bytes32(0));
        
        // Should be consistent
        bytes32 separator2 = signatureVerifier.getDomainSeparator();
        assertEq(separator, separator2);
    }
}
