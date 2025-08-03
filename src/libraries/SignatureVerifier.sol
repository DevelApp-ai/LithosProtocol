// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

/**
 * @title SignatureVerifier
 * @dev Library for verifying EIP-712 signatures for off-chain game actions
 * Enables gas optimization by allowing players to sign actions off-chain
 */
contract SignatureVerifier is EIP712 {
    using ECDSA for bytes32;

    // Type hashes for different action types
    bytes32 public constant QUEST_ACTION_TYPEHASH = keccak256(
        "QuestAction(address player,uint256 questId,uint256 nonce,uint256 deadline)"
    );
    
    bytes32 public constant CRAFT_ACTION_TYPEHASH = keccak256(
        "CraftAction(address player,uint256 itemId,uint256 quantity,uint256 nonce,uint256 deadline)"
    );
    
    bytes32 public constant PVP_ACTION_TYPEHASH = keccak256(
        "PvPAction(address player,address opponent,bool victory,uint256 nonce,uint256 deadline)"
    );

    // Nonces for replay protection
    mapping(address => uint256) public nonces;

    // Events
    event NonceUsed(address indexed player, uint256 nonce);

    constructor() EIP712("LithosProtocol", "1") {}

    /**
     * @dev Verify a quest action signature
     * @param player The player address
     * @param questId The quest identifier
     * @param deadline Signature expiration timestamp
     * @param signature The EIP-712 signature
     */
    function verifyQuestAction(
        address player,
        uint256 questId,
        uint256 deadline,
        bytes memory signature
    ) external returns (bool) {
        require(block.timestamp <= deadline, "Signature expired");
        
        uint256 nonce = nonces[player];
        bytes32 structHash = keccak256(
            abi.encode(QUEST_ACTION_TYPEHASH, player, questId, nonce, deadline)
        );
        
        bytes32 hash = _hashTypedDataV4(structHash);
        address signer = hash.recover(signature);
        
        require(signer == player, "Invalid signature");
        
        nonces[player]++;
        emit NonceUsed(player, nonce);
        
        return true;
    }

    /**
     * @dev Verify a crafting action signature
     * @param player The player address
     * @param itemId The item to craft
     * @param quantity Number of items to craft
     * @param deadline Signature expiration timestamp
     * @param signature The EIP-712 signature
     */
    function verifyCraftAction(
        address player,
        uint256 itemId,
        uint256 quantity,
        uint256 deadline,
        bytes memory signature
    ) external returns (bool) {
        require(block.timestamp <= deadline, "Signature expired");
        
        uint256 nonce = nonces[player];
        bytes32 structHash = keccak256(
            abi.encode(CRAFT_ACTION_TYPEHASH, player, itemId, quantity, nonce, deadline)
        );
        
        bytes32 hash = _hashTypedDataV4(structHash);
        address signer = hash.recover(signature);
        
        require(signer == player, "Invalid signature");
        
        nonces[player]++;
        emit NonceUsed(player, nonce);
        
        return true;
    }

    /**
     * @dev Verify a PvP result signature
     * @param player The player address
     * @param opponent The opponent address
     * @param victory Whether the player won
     * @param deadline Signature expiration timestamp
     * @param signature The EIP-712 signature
     */
    function verifyPvPAction(
        address player,
        address opponent,
        bool victory,
        uint256 deadline,
        bytes memory signature
    ) external returns (bool) {
        require(block.timestamp <= deadline, "Signature expired");
        
        uint256 nonce = nonces[player];
        bytes32 structHash = keccak256(
            abi.encode(PVP_ACTION_TYPEHASH, player, opponent, victory, nonce, deadline)
        );
        
        bytes32 hash = _hashTypedDataV4(structHash);
        address signer = hash.recover(signature);
        
        require(signer == player, "Invalid signature");
        
        nonces[player]++;
        emit NonceUsed(player, nonce);
        
        return true;
    }

    /**
     * @dev Get the current nonce for a player
     * @param player The player address
     * @return The current nonce
     */
    function getNonce(address player) external view returns (uint256) {
        return nonces[player];
    }

    /**
     * @dev Get the domain separator for this contract
     * @return The EIP-712 domain separator
     */
    function getDomainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }
}

