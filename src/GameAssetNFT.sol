// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

/**
 * @title GameAssetNFT
 * @dev ERC721 contract for unique game assets (characters, land, etc.)
 * Upgradeable via UUPS proxy pattern
 */
contract GameAssetNFT is 
    Initializable, 
    ERC721Upgradeable, 
    ERC721EnumerableUpgradeable, 
    ERC721URIStorageUpgradeable, 
    ERC721PausableUpgradeable, 
    OwnableUpgradeable, 
    AccessControlUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant GAME_ROLE = keccak256("GAME_ROLE");

    uint256 private _nextTokenId;
    
    // Asset type enumeration
    enum AssetType { CHARACTER, LAND, WEAPON, ARMOR, ACCESSORY }
    
    // Asset metadata structure
    struct AssetMetadata {
        AssetType assetType;
        uint256 level;
        uint256 rarity; // 1-5 scale
        uint256 createdAt;
        bool isStaked;
    }
    
    // Mapping from token ID to asset metadata
    mapping(uint256 => AssetMetadata) public assetMetadata;
    
    // Events
    event AssetMinted(address indexed to, uint256 indexed tokenId, AssetType assetType, uint256 rarity);
    event AssetStaked(uint256 indexed tokenId, bool staked);
    event AssetLevelUp(uint256 indexed tokenId, uint256 newLevel);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initialize the contract
     * @param initialOwner The initial owner of the contract
     * @param name The name of the NFT collection
     * @param symbol The symbol of the NFT collection
     */
    function initialize(
        address initialOwner,
        string memory name,
        string memory symbol
    ) initializer public {
        __ERC721_init(name, symbol);
        __ERC721Enumerable_init();
        __ERC721URIStorage_init();
        __ERC721Pausable_init();
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
     * @dev Mint a new asset NFT
     * @param to The address to mint the NFT to
     * @param assetType The type of asset being minted
     * @param rarity The rarity level (1-5)
     * @param uri The metadata URI for the NFT
     */
    function mintAsset(
        address to,
        AssetType assetType,
        uint256 rarity,
        string memory uri
    ) public onlyRole(MINTER_ROLE) nonReentrant returns (uint256) {
        require(rarity >= 1 && rarity <= 5, "Invalid rarity level");
        
        uint256 tokenId = _nextTokenId++;
        
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);
        
        assetMetadata[tokenId] = AssetMetadata({
            assetType: assetType,
            level: 1,
            rarity: rarity,
            createdAt: block.timestamp,
            isStaked: false
        });
        
        emit AssetMinted(to, tokenId, assetType, rarity);
        
        return tokenId;
    }

    /**
     * @dev Level up an asset (game logic)
     * @param tokenId The token ID to level up
     */
    function levelUpAsset(uint256 tokenId) public onlyRole(GAME_ROLE) {
        require(_ownerOf(tokenId) != address(0), "Asset does not exist");
        
        assetMetadata[tokenId].level++;
        
        emit AssetLevelUp(tokenId, assetMetadata[tokenId].level);
    }

    /**
     * @dev Set staking status for an asset
     * @param tokenId The token ID to update
     * @param staked Whether the asset is staked
     */
    function setStakingStatus(uint256 tokenId, bool staked) public onlyRole(GAME_ROLE) {
        require(_ownerOf(tokenId) != address(0), "Asset does not exist");
        
        assetMetadata[tokenId].isStaked = staked;
        
        emit AssetStaked(tokenId, staked);
    }

    /**
     * @dev Get asset metadata
     * @param tokenId The token ID to query
     */
    function getAssetMetadata(uint256 tokenId) public view returns (AssetMetadata memory) {
        require(_ownerOf(tokenId) != address(0), "Asset does not exist");
        return assetMetadata[tokenId];
    }

    /**
     * @dev Get all tokens owned by an address
     * @param owner The address to query
     */
    function getTokensByOwner(address owner) public view returns (uint256[] memory) {
        uint256 tokenCount = balanceOf(owner);
        uint256[] memory tokens = new uint256[](tokenCount);
        
        for (uint256 i = 0; i < tokenCount; i++) {
            tokens[i] = tokenOfOwnerByIndex(owner, i);
        }
        
        return tokens;
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

    function _beforeTokenTransfer(address from, address to, uint256 firstTokenId, uint256 batchSize)
        internal
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable, ERC721PausableUpgradeable)
    {
        super._beforeTokenTransfer(from, to, firstTokenId, batchSize);
    }

    function _burn(uint256 tokenId)
        internal
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable)
    {
        super._burn(tokenId);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable, ERC721URIStorageUpgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}

