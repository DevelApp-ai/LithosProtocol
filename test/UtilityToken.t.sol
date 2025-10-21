// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/UtilityToken.sol";

contract UtilityTokenTest is Test {
    UtilityToken public token;
    UtilityToken public implementation;
    
    address public owner = address(0x1);
    address public minter = address(0x2);
    address public burner = address(0x3);
    address public user1 = address(0x4);
    address public user2 = address(0x5);
    
    string constant TOKEN_NAME = "Aetherium Play";
    string constant TOKEN_SYMBOL = "PLAY";
    uint256 constant INITIAL_SUPPLY = 1000000 * 10**18;
    
    event Transfer(address indexed from, address indexed to, uint256 value);
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    
    function setUp() public {
        // Deploy implementation
        implementation = new UtilityToken();
        
        // Deploy proxy with initialization
        bytes memory initData = abi.encodeWithSelector(
            UtilityToken.initialize.selector,
            owner,
            TOKEN_NAME,
            TOKEN_SYMBOL,
            INITIAL_SUPPLY
        );
        
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        token = UtilityToken(address(proxy));
        
        // Grant roles
        vm.startPrank(owner);
        token.grantRole(token.MINTER_ROLE(), minter);
        token.grantRole(token.BURNER_ROLE(), burner);
        vm.stopPrank();
    }
    
    function testInitialization() public {
        assertEq(token.name(), TOKEN_NAME);
        assertEq(token.symbol(), TOKEN_SYMBOL);
        assertEq(token.totalSupply(), INITIAL_SUPPLY);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY);
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), owner));
        assertTrue(token.hasRole(token.MINTER_ROLE(), owner));
        assertTrue(token.hasRole(token.BURNER_ROLE(), owner));
        assertTrue(token.hasRole(token.GAME_ROLE(), owner));
    }
    
    function test_RevertWhen_InitializeTwice() public {
        vm.expectRevert("Initializable: contract is already initialized");
        token.initialize(owner, TOKEN_NAME, TOKEN_SYMBOL, INITIAL_SUPPLY);
    }
    
    function testMintWithMinterRole() public {
        vm.startPrank(minter);
        
        uint256 mintAmount = 1000 * 10**18;
        uint256 initialSupply = token.totalSupply();
        
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), user1, mintAmount);
        
        token.mint(user1, mintAmount);
        
        assertEq(token.balanceOf(user1), mintAmount);
        assertEq(token.totalSupply(), initialSupply + mintAmount);
        
        vm.stopPrank();
    }
    
    function test_RevertWhen_MintWithoutRole() public {
        vm.startPrank(user1);
        
        vm.expectRevert();
        token.mint(user1, 1000 * 10**18);
        
        vm.stopPrank();
    }
    
    function testBurnFromWithBurnerRole() public {
        // First give user1 some tokens
        vm.startPrank(owner);
        token.transfer(user1, 1000 * 10**18);
        vm.stopPrank();
        
        // Approve burner to spend tokens
        vm.startPrank(user1);
        token.approve(burner, 500 * 10**18);
        vm.stopPrank();
        
        // Burn tokens
        vm.startPrank(burner);
        
        uint256 burnAmount = 500 * 10**18;
        uint256 initialSupply = token.totalSupply();
        uint256 initialBalance = token.balanceOf(user1);
        
        vm.expectEmit(true, true, false, true);
        emit Transfer(user1, address(0), burnAmount);
        
        token.burnFrom(user1, burnAmount);
        
        assertEq(token.balanceOf(user1), initialBalance - burnAmount);
        assertEq(token.totalSupply(), initialSupply - burnAmount);
        
        vm.stopPrank();
    }
    
    function test_RevertWhen_BurnFromWithoutRole() public {
        vm.startPrank(user1);
        
        vm.expectRevert();
        token.burnFrom(user1, 100 * 10**18);
        
        vm.stopPrank();
    }
    
    function testGameTransferWithGameRole() public {
        // Give user1 some tokens
        vm.startPrank(owner);
        token.transfer(user1, 1000 * 10**18);
        
        // Use game transfer (requires GAME_ROLE)
        token.gameTransfer(user1, user2, 500 * 10**18);
        assertEq(token.balanceOf(user1), 500 * 10**18);
        assertEq(token.balanceOf(user2), 500 * 10**18);
        
        vm.stopPrank();
    }
    
    function test_RevertWhen_GameTransferWithoutRole() public {
        vm.startPrank(user1);
        
        vm.expectRevert();
        token.gameTransfer(user1, user2, 100 * 10**18);
        
        vm.stopPrank();
    }
    
    function testPauseUnpause() public {
        vm.startPrank(owner);
        
        // Pause the contract
        token.pause();
        assertTrue(token.paused());
        
        // Try to transfer while paused
        vm.expectRevert("ERC20Pausable: token transfer while paused");
        token.transfer(user1, 1000 * 10**18);
        
        // Unpause
        token.unpause();
        assertFalse(token.paused());
        
        // Should work after unpause
        bool success = token.transfer(user1, 1000 * 10**18);
        assertTrue(success);
        assertEq(token.balanceOf(user1), 1000 * 10**18);
        
        vm.stopPrank();
    }
    
    function test_RevertWhen_PauseUnpauseWithoutOwner() public {
        vm.startPrank(user1);
        
        vm.expectRevert("Ownable: caller is not the owner");
        token.pause();
        
        vm.expectRevert("Ownable: caller is not the owner");  
        token.unpause();
        
        vm.stopPrank();
    }
    
    function testUpgrade() public {
        // Deploy new implementation
        UtilityToken newImplementation = new UtilityToken();
        
        vm.startPrank(owner);
        
        // Upgrade to new implementation
        token.upgradeToAndCall(address(newImplementation), "");
        
        // Verify state is preserved
        assertEq(token.name(), TOKEN_NAME);
        assertEq(token.symbol(), TOKEN_SYMBOL);
        assertEq(token.totalSupply(), INITIAL_SUPPLY);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY);
        
        vm.stopPrank();
    }
    
    function test_RevertWhen_UpgradeWithoutOwner() public {
        UtilityToken newImplementation = new UtilityToken();
        
        vm.startPrank(user1);
        
        vm.expectRevert("Ownable: caller is not the owner");
        token.upgradeToAndCall(address(newImplementation), "");
        
        vm.stopPrank();
    }
    
    function testRoleManagement() public {
        vm.startPrank(owner);
        
        // Grant new role
        vm.expectEmit(true, true, true, false);
        emit RoleGranted(token.MINTER_ROLE(), user1, owner);
        
        token.grantRole(token.MINTER_ROLE(), user1);
        assertTrue(token.hasRole(token.MINTER_ROLE(), user1));
        
        // Revoke role
        token.revokeRole(token.MINTER_ROLE(), user1);
        assertFalse(token.hasRole(token.MINTER_ROLE(), user1));
        
        vm.stopPrank();
    }
    
    function testSupportsInterface() public {
        // Test ERC20 interface - using bytes4 directly
        assertTrue(token.supportsInterface(0x36372b07)); // ERC20 interface ID  
        // Test AccessControl interface
        assertTrue(token.supportsInterface(0x7965db0b)); // AccessControl interface ID
    }
    
    function testFuzzTransfer(uint256 amount) public {
        vm.assume(amount <= INITIAL_SUPPLY);
        
        vm.startPrank(owner);
        
        bool success = token.transfer(user1, amount);
        assertTrue(success);
        
        assertEq(token.balanceOf(user1), amount);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY - amount);
        
        vm.stopPrank();
    }
    
    function testFuzzMint(uint256 amount) public {
        vm.assume(amount > 0 && amount <= 10**30); // Reasonable upper bound
        
        vm.startPrank(minter);
        
        uint256 initialSupply = token.totalSupply();
        token.mint(user1, amount);
        
        assertEq(token.balanceOf(user1), amount);
        assertEq(token.totalSupply(), initialSupply + amount);
        
        vm.stopPrank();
    }
    
    function test_RevertWhen_MintToZeroAddress() public {
        vm.startPrank(minter);
        
        vm.expectRevert("ERC20: mint to the zero address");
        token.mint(address(0), 1000 * 10**18);
        
        vm.stopPrank();
    }
    
    function test_RevertWhen_TransferInsufficientBalance() public {
        vm.startPrank(user1); // user1 has no tokens
        
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        token.transfer(user2, 1000 * 10**18);
        
        vm.stopPrank();
    }
}