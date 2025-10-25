// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/GameAssetNFT.sol";

contract GameAssetNFTTest is Test {
    GameAssetNFT public nft;
    GameAssetNFT public implementation;
    
    address public owner = address(0x1);
    address public minter = address(0x2);
    address public user1 = address(0x3);
    address public user2 = address(0x4);
    
    string constant NFT_NAME = "Aetherium Assets";
    string constant NFT_SYMBOL = "ASSET";
    
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event AssetMinted(address indexed to, uint256 indexed tokenId, GameAssetNFT.AssetType assetType, uint256 rarity);
    
    function setUp() public {
        // Deploy implementation
        implementation = new GameAssetNFT();
        
        // Deploy proxy with initialization
        bytes memory initData = abi.encodeWithSelector(
            GameAssetNFT.initialize.selector,
            owner,
            NFT_NAME,
            NFT_SYMBOL
        );
        
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        nft = GameAssetNFT(address(proxy));
        
        // Grant minter role
        vm.startPrank(owner);
        nft.grantRole(nft.MINTER_ROLE(), minter);
        vm.stopPrank();
    }
    
    function testInitialization() public {
        assertEq(nft.name(), NFT_NAME);
        assertEq(nft.symbol(), NFT_SYMBOL);
        assertEq(nft.totalSupply(), 0);
        assertTrue(nft.hasRole(nft.DEFAULT_ADMIN_ROLE(), owner));
        assertTrue(nft.hasRole(nft.MINTER_ROLE(), owner));
        assertTrue(nft.hasRole(nft.GAME_ROLE(), owner));
    }
    
    function test_RevertWhen_InitializeTwice() public {
        vm.expectRevert("Initializable: contract is already initialized");
        nft.initialize(owner, NFT_NAME, NFT_SYMBOL);
    }
    
    function testMintAsset() public {
        vm.startPrank(minter);
        
        string memory tokenURI = "https://api.example.com/asset/1";
        
        vm.expectEmit(true, true, true, true);
        emit AssetMinted(user1, 1, GameAssetNFT.AssetType.WEAPON, 3);
        
        uint256 tokenId = nft.mintAsset(
            user1,
            GameAssetNFT.AssetType.WEAPON,
            3,
            tokenURI
        );
        
        assertEq(tokenId, 1);
        assertEq(nft.ownerOf(tokenId), user1);
        assertEq(nft.tokenURI(tokenId), tokenURI);
        assertEq(nft.balanceOf(user1), 1);
        assertEq(nft.totalSupply(), 1);
        
        // Check metadata
        GameAssetNFT.AssetMetadata memory metadata = nft.getAssetMetadata(tokenId);
        
        assertEq(uint256(metadata.assetType), uint256(GameAssetNFT.AssetType.WEAPON));
        assertEq(metadata.level, 1); // Default level
        assertEq(metadata.rarity, 3);
        assertEq(metadata.createdAt, block.timestamp);
        assertFalse(metadata.isStaked);
        
        vm.stopPrank();
    }
    
    function test_RevertWhen_MintWithoutRole() public {
        vm.startPrank(user1);
        
        vm.expectRevert();
        nft.mintAsset(
            user1,
            GameAssetNFT.AssetType.WEAPON,
            1,
            "https://api.example.com/asset/1"
        );
        
        vm.stopPrank();
    }
    
    function testLevelUpAsset() public {
        // First mint an asset
        vm.startPrank(minter);
        uint256 tokenId = nft.mintAsset(
            user1,
            GameAssetNFT.AssetType.WEAPON,
            1,
            "https://api.example.com/asset/1"
        );
        vm.stopPrank();
        
        // Level up the asset (using GAME_ROLE)
        vm.startPrank(owner); // owner has GAME_ROLE
        nft.levelUpAsset(tokenId);
        
        GameAssetNFT.AssetMetadata memory metadata = nft.getAssetMetadata(tokenId);
        assertEq(metadata.level, 2);
        
        vm.stopPrank();
    }
    
    function test_RevertWhen_LevelUpNonexistentAsset() public {
        vm.startPrank(owner);
        
        vm.expectRevert("Asset does not exist");
        nft.levelUpAsset(999);
        
        vm.stopPrank();
    }
    
    function testSetStakingStatus() public {
        // Mint asset
        vm.startPrank(minter);
        uint256 tokenId = nft.mintAsset(
            user1,
            GameAssetNFT.AssetType.WEAPON,
            1,
            "https://api.example.com/asset/1"
        );
        vm.stopPrank();
        
        // Stake asset
        vm.startPrank(owner);
        nft.setStakingStatus(tokenId, true);
        
        GameAssetNFT.AssetMetadata memory metadata = nft.getAssetMetadata(tokenId);
        assertTrue(metadata.isStaked);
        
        // Unstake asset
        nft.setStakingStatus(tokenId, false);
        metadata = nft.getAssetMetadata(tokenId);
        assertFalse(metadata.isStaked);
        
        vm.stopPrank();
    }
    
    function testGetTokensByOwner() public {
        vm.startPrank(minter);
        
        // Mint multiple assets to user1
        nft.mintAsset(user1, GameAssetNFT.AssetType.WEAPON, 1, "uri1");
        nft.mintAsset(user1, GameAssetNFT.AssetType.ARMOR, 2, "uri2");
        nft.mintAsset(user2, GameAssetNFT.AssetType.CHARACTER, 3, "uri3");
        
        vm.stopPrank();
        
        uint256[] memory user1Assets = nft.getTokensByOwner(user1);
        uint256[] memory user2Assets = nft.getTokensByOwner(user2);
        
        assertEq(user1Assets.length, 2);
        assertEq(user1Assets[0], 1);
        assertEq(user1Assets[1], 2);
        
        assertEq(user2Assets.length, 1);
        assertEq(user2Assets[0], 3);
    }
    
    function testPauseUnpause() public {
        // Mint an asset first
        vm.startPrank(minter);
        uint256 tokenId = nft.mintAsset(
            user1,
            GameAssetNFT.AssetType.WEAPON,
            1,
            "https://api.example.com/asset/1"
        );
        vm.stopPrank();
        
        vm.startPrank(owner);
        
        // Pause the contract
        nft.pause();
        assertTrue(nft.paused());
        
        // Try to transfer while paused (should fail)
        vm.stopPrank();
        vm.startPrank(user1);
        vm.expectRevert("ERC721Pausable: token transfer while paused");
        nft.transferFrom(user1, user2, tokenId);
        vm.stopPrank();
        
        // Unpause
        vm.startPrank(owner);
        nft.unpause();
        assertFalse(nft.paused());
        vm.stopPrank();
        
        // Should work after unpause
        vm.startPrank(user1);
        nft.transferFrom(user1, user2, tokenId);
        assertEq(nft.ownerOf(tokenId), user2);
        vm.stopPrank();
    }
    
    function testSupportsInterface() public {
        // Test ERC721 interface - using bytes4 directly since interface might not be available
        assertTrue(nft.supportsInterface(0x80ac58cd)); // ERC721 interface ID
        // Test AccessControl interface
        assertTrue(nft.supportsInterface(0x7965db0b)); // AccessControl interface ID
    }
    
    function testTokenByIndex() public {
        vm.startPrank(minter);
        
        uint256 tokenId1 = nft.mintAsset(user1, GameAssetNFT.AssetType.WEAPON, 1, "uri1");
        uint256 tokenId2 = nft.mintAsset(user1, GameAssetNFT.AssetType.ARMOR, 2, "uri2");
        
        vm.stopPrank();
        
        assertEq(nft.tokenByIndex(0), tokenId1);
        assertEq(nft.tokenByIndex(1), tokenId2);
    }
    
    function testTokenOfOwnerByIndex() public {
        vm.startPrank(minter);
        
        uint256 tokenId1 = nft.mintAsset(user1, GameAssetNFT.AssetType.WEAPON, 1, "uri1");
        uint256 tokenId2 = nft.mintAsset(user1, GameAssetNFT.AssetType.ARMOR, 2, "uri2");
        
        vm.stopPrank();
        
        assertEq(nft.tokenOfOwnerByIndex(user1, 0), tokenId1);
        assertEq(nft.tokenOfOwnerByIndex(user1, 1), tokenId2);
    }
    
    function testFuzzMintAsset(uint8 assetTypeRaw, uint8 rarity) public {
        vm.assume(uint256(assetTypeRaw) <= 4); // 0-4 are valid AssetType values
        vm.assume(rarity > 0 && rarity <= 5);
        
        GameAssetNFT.AssetType assetType = GameAssetNFT.AssetType(assetTypeRaw);
        
        vm.startPrank(minter);
        
        uint256 tokenId = nft.mintAsset(
            user1,
            assetType,
            rarity,
            "test-uri"
        );
        
        assertEq(nft.ownerOf(tokenId), user1);
        GameAssetNFT.AssetMetadata memory metadata = nft.getAssetMetadata(tokenId);
        assertEq(metadata.rarity, rarity);
        
        vm.stopPrank();
    }
    
    function test_RevertWhen_LevelUpWithoutRole() public {
        // Mint asset first
        vm.startPrank(minter);
        uint256 tokenId = nft.mintAsset(
            user1,
            GameAssetNFT.AssetType.WEAPON,
            1,
            "https://api.example.com/asset/1"
        );
        vm.stopPrank();
        
        vm.startPrank(user1);
        
        vm.expectRevert();
        nft.levelUpAsset(tokenId);
        
        vm.stopPrank();
    }
}