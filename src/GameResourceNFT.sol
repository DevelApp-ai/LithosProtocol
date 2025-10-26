// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155SupplyUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

/**
 * @title GameResourceNFT
 * @dev ERC1155 contract for semi-fungible game resources (crafting materials, potions, etc.)
 * Upgradeable via UUPS proxy pattern
 */
contract GameResourceNFT is 
    Initializable, 
    ERC1155Upgradeable, 
    ERC1155PausableUpgradeable, 
    ERC1155BurnableUpgradeable, 
    ERC1155SupplyUpgradeable,
    OwnableUpgradeable, 
    AccessControlUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant GAME_ROLE = keccak256("GAME_ROLE");

    // Resource type enumeration
    enum ResourceType { CRAFTING_MATERIAL, POTION, CONSUMABLE, CURRENCY_ITEM }
    
    // Resource metadata structure
    struct ResourceMetadata {
        ResourceType resourceType;
        uint256 rarity; // 1-5 scale
        uint256 maxSupply; // 0 for unlimited
        string name;
        string description;
        bool isActive;
    }
    
    // Mapping from token ID to resource metadata
    mapping(uint256 => ResourceMetadata) public resourceMetadata;
    
    // Counter for generating new token IDs
    uint256 private _nextTokenId;
    
    // Events
    event ResourceCreated(uint256 indexed tokenId, ResourceType resourceType, string name, uint256 maxSupply);
    event ResourceMinted(address indexed to, uint256 indexed tokenId, uint256 amount);
    event ResourceBurned(address indexed from, uint256 indexed tokenId, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initialize the contract
     * @param initialOwner The initial owner of the contract
     * @param uri The base URI for token metadata
     */
    function initialize(
        address initialOwner,
        string memory uri
    ) initializer public {
        __ERC1155_init(uri);
        __ERC1155Pausable_init();
        __ERC1155Burnable_init();
        __ERC1155Supply_init();
        __Ownable_init();
        __Pausable_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        _transferOwnership(initialOwner);
        _grantRole(DEFAULT_ADMIN_ROLE, initialOwner);
        _grantRole(MINTER_ROLE, initialOwner);
        _grantRole(GAME_ROLE, initialOwner);
        
        _nextTokenId = 1;
    }

    /**
     * @dev Pause all token transfers
     */
    function pause() public onlyOwner {
        _pause();
    }

    /**
     * @dev Unpause all token transfers
     */
    function unpause() public onlyOwner {
        _unpause();
    }

    /**
     * @dev Create a new resource type
     * @param resourceType The type of resource
     * @param rarity The rarity level (1-5)
     * @param maxSupply Maximum supply (0 for unlimited)
     * @param name The name of the resource
     * @param description The description of the resource
     */
    function createResource(
        ResourceType resourceType,
        uint256 rarity,
        uint256 maxSupply,
        string memory name,
        string memory description
    ) public onlyRole(DEFAULT_ADMIN_ROLE) returns (uint256) {
        require(rarity >= 1 && rarity <= 5, "Invalid rarity level");
        
        uint256 tokenId = _nextTokenId++;
        
        resourceMetadata[tokenId] = ResourceMetadata({
            resourceType: resourceType,
            rarity: rarity,
            maxSupply: maxSupply,
            name: name,
            description: description,
            isActive: true
        });
        
        emit ResourceCreated(tokenId, resourceType, name, maxSupply);
        
        return tokenId;
    }

    /**
     * @dev Mint resources to an address
     * @param to The address to mint to
     * @param tokenId The token ID to mint
     * @param amount The amount to mint
     */
    function mintResource(
        address to,
        uint256 tokenId,
        uint256 amount
    ) public onlyRole(MINTER_ROLE) nonReentrant {
        require(resourceMetadata[tokenId].isActive, "Resource is not active");
        
        // Check max supply if set
        if (resourceMetadata[tokenId].maxSupply > 0) {
            require(totalSupply(tokenId) + amount <= resourceMetadata[tokenId].maxSupply, "Exceeds max supply");
        }
        
        _mint(to, tokenId, amount, "");
        
        emit ResourceMinted(to, tokenId, amount);
    }

    /**
     * @dev Batch mint resources to an address
     * @param to The address to mint to
     * @param tokenIds Array of token IDs to mint
     * @param amounts Array of amounts to mint
     */
    function mintResourceBatch(
        address to,
        uint256[] memory tokenIds,
        uint256[] memory amounts
    ) public onlyRole(MINTER_ROLE) nonReentrant {
        require(tokenIds.length == amounts.length, "Arrays length mismatch");
        
        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(resourceMetadata[tokenIds[i]].isActive, "Resource is not active");
            
            // Check max supply if set
            if (resourceMetadata[tokenIds[i]].maxSupply > 0) {
                require(totalSupply(tokenIds[i]) + amounts[i] <= resourceMetadata[tokenIds[i]].maxSupply, "Exceeds max supply");
            }
        }
        
        _mintBatch(to, tokenIds, amounts, "");
        
        for (uint256 i = 0; i < tokenIds.length; i++) {
            emit ResourceMinted(to, tokenIds[i], amounts[i]);
        }
    }

    /**
     * @dev Game-specific burn function
     * @param from The address to burn from
     * @param tokenId The token ID to burn
     * @param amount The amount to burn
     */
    function gameBurn(
        address from,
        uint256 tokenId,
        uint256 amount
    ) public onlyRole(GAME_ROLE) {
        _burn(from, tokenId, amount);
        
        emit ResourceBurned(from, tokenId, amount);
    }

    /**
     * @dev Game-specific batch burn function
     * @param from The address to burn from
     * @param tokenIds Array of token IDs to burn
     * @param amounts Array of amounts to burn
     */
    function gameBurnBatch(
        address from,
        uint256[] memory tokenIds,
        uint256[] memory amounts
    ) public onlyRole(GAME_ROLE) {
        _burnBatch(from, tokenIds, amounts);
        
        for (uint256 i = 0; i < tokenIds.length; i++) {
            emit ResourceBurned(from, tokenIds[i], amounts[i]);
        }
    }

    /**
     * @dev Set resource active status
     * @param tokenId The token ID to update
     * @param isActive Whether the resource is active
     */
    function setResourceActive(uint256 tokenId, bool isActive) public onlyRole(DEFAULT_ADMIN_ROLE) {
        resourceMetadata[tokenId].isActive = isActive;
    }

    /**
     * @dev Get resource metadata
     * @param tokenId The token ID to query
     */
    function getResourceMetadata(uint256 tokenId) public view returns (ResourceMetadata memory) {
        return resourceMetadata[tokenId];
    }

    /**
     * @dev Get all token balances for an address
     * @param account The address to query
     * @param tokenIds Array of token IDs to check
     */
    function getBalances(address account, uint256[] memory tokenIds) public view returns (uint256[] memory) {
        uint256[] memory balances = new uint256[](tokenIds.length);
        
        for (uint256 i = 0; i < tokenIds.length; i++) {
            balances[i] = balanceOf(account, tokenIds[i]);
        }
        
        return balances;
    }

    /**
     * @dev Set the URI for all tokens
     * @param newuri The new URI
     */
    function setURI(string memory newuri) public onlyOwner {
        _setURI(newuri);
    }

    /**
     * @dev Required by UUPS pattern
     */
    function _authorizeUpgrade(address newImplementation)
        internal
        onlyOwner
        override
    {}

    // The following functions are overrides required by Solidity.

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    )
        internal
        override(ERC1155Upgradeable, ERC1155PausableUpgradeable, ERC1155SupplyUpgradeable)
    {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155Upgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}

