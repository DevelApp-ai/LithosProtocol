// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/GameResourceNFT.sol";

contract GameResourceNFTTest is Test {
    GameResourceNFT public nft;
    GameResourceNFT public implementation;
    
    address public owner = address(0x1);
    address public minter = address(0x2);
    address public gameContract = address(0x3);
    address public user1 = address(0x4);
    address public user2 = address(0x5);
    
    string constant BASE_URI = "https://api.example.com/metadata/";
    
    event TransferSingle(address indexed operator, address indexed from, address indexed to, uint256 id, uint256 value);
    event ResourceCreated(uint256 indexed resourceId, GameResourceNFT.ResourceType resourceType, string name);
    
    function setUp() public {
        // Deploy implementation
        implementation = new GameResourceNFT();
        
        // Deploy proxy with initialization
        bytes memory initData = abi.encodeWithSelector(
            GameResourceNFT.initialize.selector,
            owner,
            BASE_URI
        );
        
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        nft = GameResourceNFT(address(proxy));
        
        // Grant roles
        vm.startPrank(owner);
        nft.grantRole(nft.MINTER_ROLE(), minter);
        nft.grantRole(nft.GAME_ROLE(), gameContract);
        vm.stopPrank();
    }
    
    function testInitialization() public {
        assertEq(nft.uri(1), BASE_URI);
        assertTrue(nft.hasRole(nft.DEFAULT_ADMIN_ROLE(), owner));
        assertTrue(nft.hasRole(nft.MINTER_ROLE(), owner));
        assertTrue(nft.hasRole(nft.GAME_ROLE(), owner));
    }
    
    function test_RevertWhen_InitializeTwice() public {
        vm.expectRevert("Initializable: contract is already initialized");
        nft.initialize(owner, BASE_URI);
    }
    
    function testCreateResource() public {
        vm.startPrank(owner);
        
        vm.expectEmit(true, false, false, true);
        emit ResourceCreated(1, GameResourceNFT.ResourceType.CRAFTING_MATERIAL, "Iron Ore");
        
        uint256 resourceId = nft.createResource(
            GameResourceNFT.ResourceType.CRAFTING_MATERIAL,
            1,
            1000,
            "Iron Ore",
            "Basic crafting material"
        );
        
        assertEq(resourceId, 1);
        
        // Check metadata using getResourceMetadata function
        GameResourceNFT.ResourceMetadata memory metadata = nft.getResourceMetadata(resourceId);
        
        assertEq(uint256(metadata.resourceType), uint256(GameResourceNFT.ResourceType.CRAFTING_MATERIAL));
        assertEq(metadata.rarity, 1);
        assertEq(metadata.maxSupply, 1000);
        assertEq(metadata.name, "Iron Ore");
        assertEq(metadata.description, "Basic crafting material");
        assertTrue(metadata.isActive);
        
        vm.stopPrank();
    }
    
    function test_RevertWhen_CreateResourceWithoutRole() public {
        vm.startPrank(user1);
        
        vm.expectRevert();
        nft.createResource(
            GameResourceNFT.ResourceType.CRAFTING_MATERIAL,
            1,
            1000,
            "Iron Ore",
            "Basic crafting material"
        );
        
        vm.stopPrank();
    }
    
    function testMintResource() public {
        // First create a resource
        vm.startPrank(owner);
        uint256 resourceId = nft.createResource(
            GameResourceNFT.ResourceType.CRAFTING_MATERIAL,
            1,
            1000,
            "Iron Ore",
            "Basic crafting material"
        );
        vm.stopPrank();
        
        // Mint resource to user
        vm.startPrank(minter);
        
        vm.expectEmit(true, true, true, true);
        emit TransferSingle(minter, address(0), user1, resourceId, 50);
        
        nft.mintResource(user1, resourceId, 50);
        
        assertEq(nft.balanceOf(user1, resourceId), 50);
        assertEq(nft.totalSupply(resourceId), 50);
        
        vm.stopPrank();
    }
    
    function test_RevertWhen_MintResourceWithoutRole() public {
        vm.startPrank(owner);
        uint256 resourceId = nft.createResource(
            GameResourceNFT.ResourceType.CRAFTING_MATERIAL,
            1,
            1000,
            "Iron Ore",
            "Basic crafting material"
        );
        vm.stopPrank();
        
        vm.startPrank(user1);
        
        vm.expectRevert();
        nft.mintResource(user1, resourceId, 50);
        
        vm.stopPrank();
    }
    
    function test_RevertWhen_MintExceedsMaxSupply() public {
        vm.startPrank(owner);
        uint256 resourceId = nft.createResource(
            GameResourceNFT.ResourceType.CRAFTING_MATERIAL,
            1,
            100, // Max supply of 100
            "Rare Gem",
            "Very rare crafting material"
        );
        vm.stopPrank();
        
        vm.startPrank(minter);
        
        // First mint should work
        nft.mintResource(user1, resourceId, 100);
        
        // Second mint should fail
        vm.expectRevert("Exceeds max supply");
        nft.mintResource(user2, resourceId, 1);
        
        vm.stopPrank();
    }
    
    function testMintResourceBatch() public {
        vm.startPrank(owner);
        uint256 resourceId1 = nft.createResource(
            GameResourceNFT.ResourceType.CRAFTING_MATERIAL,
            1,
            1000,
            "Iron Ore",
            "Basic crafting material"
        );
        uint256 resourceId2 = nft.createResource(
            GameResourceNFT.ResourceType.POTION,
            2,
            500,
            "Health Potion",
            "Restores health"
        );
        vm.stopPrank();
        
        vm.startPrank(minter);
        
        uint256[] memory ids = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        
        ids[0] = resourceId1;
        ids[1] = resourceId2;
        amounts[0] = 100;
        amounts[1] = 50;
        
        nft.mintResourceBatch(user1, ids, amounts);
        
        assertEq(nft.balanceOf(user1, resourceId1), 100);
        assertEq(nft.balanceOf(user1, resourceId2), 50);
        
        vm.stopPrank();
    }
    
    function testGameBurnBatch() public {
        // Create and mint resources
        vm.startPrank(owner);
        uint256 resourceId1 = nft.createResource(
            GameResourceNFT.ResourceType.CRAFTING_MATERIAL,
            1,
            1000,
            "Iron Ore",
            "Basic crafting material"
        );
        uint256 resourceId2 = nft.createResource(
            GameResourceNFT.ResourceType.CRAFTING_MATERIAL,
            2,
            500,
            "Steel Ingot",
            "Refined crafting material"
        );
        vm.stopPrank();
        
        vm.startPrank(minter);
        nft.mintResource(user1, resourceId1, 100);
        nft.mintResource(user1, resourceId2, 50);
        vm.stopPrank();
        
        // Burn resources using game contract
        vm.startPrank(gameContract);
        
        uint256[] memory ids = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        
        ids[0] = resourceId1;
        ids[1] = resourceId2;
        amounts[0] = 30;
        amounts[1] = 10;
        
        nft.gameBurnBatch(user1, ids, amounts);
        
        assertEq(nft.balanceOf(user1, resourceId1), 70);
        assertEq(nft.balanceOf(user1, resourceId2), 40);
        
        vm.stopPrank();
    }
    
    function test_RevertWhen_GameBurnWithoutRole() public {
        vm.startPrank(user1);
        
        uint256[] memory ids = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);
        ids[0] = 1;
        amounts[0] = 10;
        
        vm.expectRevert();
        nft.gameBurnBatch(user1, ids, amounts);
        
        vm.stopPrank();
    }
    
    function testSetResourceActive() public {
        vm.startPrank(owner);
        uint256 resourceId = nft.createResource(
            GameResourceNFT.ResourceType.CRAFTING_MATERIAL,
            1,
            1000,
            "Iron Ore",
            "Basic crafting material"
        );
        
        // Deactivate resource
        nft.setResourceActive(resourceId, false);
        
        GameResourceNFT.ResourceMetadata memory metadata = nft.getResourceMetadata(resourceId);
        assertFalse(metadata.isActive);
        
        // Reactivate resource
        nft.setResourceActive(resourceId, true);
        
        metadata = nft.getResourceMetadata(resourceId);
        assertTrue(metadata.isActive);
        
        vm.stopPrank();
    }
    
    function test_RevertWhen_SetResourceActiveWithoutRole() public {
        vm.startPrank(owner);
        uint256 resourceId = nft.createResource(
            GameResourceNFT.ResourceType.CRAFTING_MATERIAL,
            1,
            1000,
            "Iron Ore",
            "Basic crafting material"
        );
        vm.stopPrank();
        
        vm.startPrank(user1);
        
        vm.expectRevert();
        nft.setResourceActive(resourceId, false);
        
        vm.stopPrank();
    }
    
    function testBalanceOfBatch() public {
        vm.startPrank(owner);
        uint256 resourceId1 = nft.createResource(
            GameResourceNFT.ResourceType.CRAFTING_MATERIAL,
            1,
            1000,
            "Iron Ore",
            "Basic crafting material"
        );
        uint256 resourceId2 = nft.createResource(
            GameResourceNFT.ResourceType.POTION,
            1,
            100,
            "Health Potion",
            "Restores health"
        );
        vm.stopPrank();
        
        vm.startPrank(minter);
        nft.mintResource(user1, resourceId1, 100);
        nft.mintResource(user1, resourceId2, 50);
        nft.mintResource(user2, resourceId1, 25);
        vm.stopPrank();
        
        address[] memory accounts = new address[](3);
        uint256[] memory ids = new uint256[](3);
        
        accounts[0] = user1;
        accounts[1] = user1;
        accounts[2] = user2;
        
        ids[0] = resourceId1;
        ids[1] = resourceId2;
        ids[2] = resourceId1;
        
        uint256[] memory balances = nft.balanceOfBatch(accounts, ids);
        
        assertEq(balances[0], 100); // user1's iron ore
        assertEq(balances[1], 50);  // user1's health potion
        assertEq(balances[2], 25);  // user2's iron ore
    }
    
    function testPauseUnpause() public {
        vm.startPrank(owner);
        uint256 resourceId = nft.createResource(
            GameResourceNFT.ResourceType.CRAFTING_MATERIAL,
            1,
            1000,
            "Iron Ore",
            "Basic crafting material"
        );
        vm.stopPrank();
        
        vm.startPrank(minter);
        nft.mintResource(user1, resourceId, 100);
        vm.stopPrank();
        
        vm.startPrank(owner);
        
        // Pause the contract
        nft.pause();
        assertTrue(nft.paused());
        
        // Try to transfer while paused (should fail)
        vm.stopPrank();
        vm.startPrank(user1);
        vm.expectRevert("ERC1155Pausable: token transfer while paused");
        nft.safeTransferFrom(user1, user2, resourceId, 50, "");
        vm.stopPrank();
        
        // Unpause
        vm.startPrank(owner);
        nft.unpause();
        assertFalse(nft.paused());
        vm.stopPrank();
        
        // Should work after unpause
        vm.startPrank(user1);
        nft.safeTransferFrom(user1, user2, resourceId, 50, "");
        assertEq(nft.balanceOf(user1, resourceId), 50);
        assertEq(nft.balanceOf(user2, resourceId), 50);
        vm.stopPrank();
    }
    
    function testSupportsInterface() public {
        // Test ERC1155 interface - using bytes4 directly
        assertTrue(nft.supportsInterface(0xd9b67a26)); // ERC1155 interface ID
        // Test AccessControl interface
        assertTrue(nft.supportsInterface(0x7965db0b)); // AccessControl interface ID
    }
    
    function testFuzzCreateAndMintResource(uint8 resourceTypeRaw, uint8 rarity, uint16 amount) public {
        vm.assume(uint256(resourceTypeRaw) <= 3); // 0-3 are valid ResourceType values
        vm.assume(rarity > 0 && rarity <= 5);
        vm.assume(amount > 0 && amount <= 1000);
        
        GameResourceNFT.ResourceType resourceType = GameResourceNFT.ResourceType(resourceTypeRaw);
        
        vm.startPrank(owner);
        uint256 resourceId = nft.createResource(
            resourceType,
            rarity,
            amount,
            "Test Resource",
            "Test Description"
        );
        vm.stopPrank();
        
        vm.startPrank(minter);
        nft.mintResource(user1, resourceId, amount);
        
        assertEq(nft.balanceOf(user1, resourceId), amount);
        GameResourceNFT.ResourceMetadata memory metadata = nft.getResourceMetadata(resourceId);
        assertEq(metadata.rarity, rarity);
        
        vm.stopPrank();
    }
    
    function test_RevertWhen_MintInactiveResource() public {
        vm.startPrank(owner);
        uint256 resourceId = nft.createResource(
            GameResourceNFT.ResourceType.CRAFTING_MATERIAL,
            1,
            1000,
            "Iron Ore",
            "Basic crafting material"
        );
        
        // Deactivate resource
        nft.setResourceActive(resourceId, false);
        vm.stopPrank();
        
        vm.startPrank(minter);
        
        vm.expectRevert("Resource is not active");
        nft.mintResource(user1, resourceId, 50);
        
        vm.stopPrank();
    }
    
    function test_RevertWhen_BurnMoreThanBalance() public {
        vm.startPrank(owner);
        uint256 resourceId = nft.createResource(
            GameResourceNFT.ResourceType.CRAFTING_MATERIAL,
            1,
            1000,
            "Iron Ore",
            "Basic crafting material"
        );
        vm.stopPrank();
        
        vm.startPrank(minter);
        nft.mintResource(user1, resourceId, 50);
        vm.stopPrank();
        
        vm.startPrank(gameContract);
        
        uint256[] memory ids = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);
        ids[0] = resourceId;
        amounts[0] = 100; // More than balance
        
        vm.expectRevert("ERC1155: burn amount exceeds balance");
        nft.gameBurnBatch(user1, ids, amounts);
        
        vm.stopPrank();
    }
}