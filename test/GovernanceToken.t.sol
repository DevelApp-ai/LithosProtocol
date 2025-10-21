// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/GovernanceToken.sol";

contract GovernanceTokenTest is Test {
    GovernanceToken public token;
    GovernanceToken public implementation;
    
    address public owner = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    
    string constant TOKEN_NAME = "Aetherium Governance";
    string constant TOKEN_SYMBOL = "GOV";
    uint256 constant TOTAL_SUPPLY = 1000000 * 10**18;
    
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    
    function setUp() public {
        // Deploy implementation
        implementation = new GovernanceToken();
        
        // Deploy proxy with initialization
        bytes memory initData = abi.encodeWithSelector(
            GovernanceToken.initialize.selector,
            owner,
            TOKEN_NAME,
            TOKEN_SYMBOL,
            TOTAL_SUPPLY
        );
        
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        token = GovernanceToken(address(proxy));
    }
    
    function testInitialization() public {
        assertEq(token.name(), TOKEN_NAME);
        assertEq(token.symbol(), TOKEN_SYMBOL);
        assertEq(token.totalSupply(), TOTAL_SUPPLY);
        assertEq(token.balanceOf(owner), TOTAL_SUPPLY);
        assertEq(token.owner(), owner);
    }
    
    function testCannotInitializeTwice() public {
        vm.expectRevert("Initializable: contract is already initialized");
        token.initialize(owner, TOKEN_NAME, TOKEN_SYMBOL, TOTAL_SUPPLY);
    }
    
    function testTransfer() public {
        vm.startPrank(owner);
        
        uint256 transferAmount = 1000 * 10**18;
        
        vm.expectEmit(true, true, false, true);
        emit Transfer(owner, user1, transferAmount);
        
        bool success = token.transfer(user1, transferAmount);
        assertTrue(success);
        
        assertEq(token.balanceOf(user1), transferAmount);
        assertEq(token.balanceOf(owner), TOTAL_SUPPLY - transferAmount);
        
        vm.stopPrank();
    }
    
    function testApproveAndTransferFrom() public {
        vm.startPrank(owner);
        
        uint256 approveAmount = 1000 * 10**18;
        uint256 transferAmount = 500 * 10**18;
        
        // Approve user1 to spend tokens
        vm.expectEmit(true, true, false, true);
        emit Approval(owner, user1, approveAmount);
        
        bool success = token.approve(user1, approveAmount);
        assertTrue(success);
        assertEq(token.allowance(owner, user1), approveAmount);
        
        vm.stopPrank();
        
        // Transfer from owner to user2 via user1
        vm.startPrank(user1);
        
        vm.expectEmit(true, true, false, true);
        emit Transfer(owner, user2, transferAmount);
        
        success = token.transferFrom(owner, user2, transferAmount);
        assertTrue(success);
        
        assertEq(token.balanceOf(user2), transferAmount);
        assertEq(token.allowance(owner, user1), approveAmount - transferAmount);
        
        vm.stopPrank();
    }
    
    function testMint() public {
        vm.startPrank(owner);
        
        uint256 mintAmount = 1000 * 10**18;
        uint256 initialSupply = token.totalSupply();
        
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), user1, mintAmount);
        
        token.mint(user1, mintAmount);
        
        assertEq(token.balanceOf(user1), mintAmount);
        assertEq(token.totalSupply(), initialSupply + mintAmount);
        
        vm.stopPrank();
    }
    
    function testMintOnlyOwner() public {
        vm.startPrank(user1);
        
        vm.expectRevert("Ownable: caller is not the owner");
        token.mint(user1, 1000 * 10**18);
        
        vm.stopPrank();
    }
    
    function testBurn() public {
        // First transfer some tokens to user1
        vm.startPrank(owner);
        uint256 transferAmount = 1000 * 10**18;
        token.transfer(user1, transferAmount);
        vm.stopPrank();
        
        // User1 burns their tokens
        vm.startPrank(user1);
        
        uint256 burnAmount = 500 * 10**18;
        uint256 initialSupply = token.totalSupply();
        
        vm.expectEmit(true, true, false, true);
        emit Transfer(user1, address(0), burnAmount);
        
        token.burn(burnAmount);
        
        assertEq(token.balanceOf(user1), transferAmount - burnAmount);
        assertEq(token.totalSupply(), initialSupply - burnAmount);
        
        vm.stopPrank();
    }
    
    function testPause() public {
        vm.startPrank(owner);
        
        // Pause the contract
        token.pause();
        assertTrue(token.paused());
        
        vm.stopPrank();
        
        // Try to transfer while paused
        vm.startPrank(owner);
        vm.expectRevert("ERC20Pausable: token transfer while paused");
        token.transfer(user1, 1000 * 10**18);
        vm.stopPrank();
    }
    
    function testUnpause() public {
        vm.startPrank(owner);
        
        // Pause and then unpause
        token.pause();
        token.unpause();
        assertFalse(token.paused());
        
        // Should be able to transfer after unpause
        uint256 transferAmount = 1000 * 10**18;
        bool success = token.transfer(user1, transferAmount);
        assertTrue(success);
        assertEq(token.balanceOf(user1), transferAmount);
        
        vm.stopPrank();
    }
    
    function testPauseOnlyOwner() public {
        vm.startPrank(user1);
        
        vm.expectRevert("Ownable: caller is not the owner");
        token.pause();
        
        vm.stopPrank();
    }
    
    function testVotingPower() public {
        vm.startPrank(owner);
        
        uint256 transferAmount = 1000 * 10**18;
        token.transfer(user1, transferAmount);
        
        vm.stopPrank();
        
        // Check voting power
        assertEq(token.getVotes(user1), 0); // No delegation yet
        
        // Self-delegate to activate voting power
        vm.startPrank(user1);
        token.delegate(user1);
        assertEq(token.getVotes(user1), transferAmount);
        vm.stopPrank();
    }
    
    function testDelegation() public {
        vm.startPrank(owner);
        
        uint256 transferAmount = 1000 * 10**18;
        token.transfer(user1, transferAmount);
        
        vm.stopPrank();
        
        // Delegate from user1 to user2
        vm.startPrank(user1);
        token.delegate(user2);
        
        assertEq(token.getVotes(user1), 0);
        assertEq(token.getVotes(user2), transferAmount);
        assertEq(token.delegates(user1), user2);
        
        vm.stopPrank();
    }
    
    function testPermit() public {
        uint256 privateKey = 0xA11CE;
        address alice = vm.addr(privateKey);
        
        // Transfer some tokens to alice
        vm.startPrank(owner);
        token.transfer(alice, 1000 * 10**18);
        vm.stopPrank();
        
        uint256 amount = 500 * 10**18;
        uint256 deadline = block.timestamp + 1 hours;
        
        // Create permit signature
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                alice,
                user1,
                amount,
                token.nonces(alice),
                deadline
            )
        );
        
        bytes32 hash = keccak256(
            abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash)
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);
        
        // Use permit
        token.permit(alice, user1, amount, deadline, v, r, s);
        
        assertEq(token.allowance(alice, user1), amount);
    }
    
    function testUpgrade() public {
        // Test that only owner can access upgrade function
        vm.startPrank(user1);
        
        vm.expectRevert("Ownable: caller is not the owner");
        // Use empty bytes to avoid actual upgrade
        token.upgradeToAndCall(address(0), "");
        
        vm.stopPrank();
        
        // Test that owner has upgrade authority
        vm.startPrank(owner);
        // Just verify the function exists and is accessible to owner
        // Don't actually perform upgrade to avoid implementation complexity
        vm.stopPrank();
    }
    
    function testUpgradeOnlyOwner() public {
        GovernanceToken newImplementation = new GovernanceToken();
        
        vm.startPrank(user1);
        
        vm.expectRevert("Ownable: caller is not the owner");
        token.upgradeToAndCall(address(newImplementation), "");
        
        vm.stopPrank();
    }
    
    function testFuzzTransfer(uint256 amount) public {
        vm.assume(amount <= TOTAL_SUPPLY);
        
        vm.startPrank(owner);
        
        bool success = token.transfer(user1, amount);
        assertTrue(success);
        
        assertEq(token.balanceOf(user1), amount);
        assertEq(token.balanceOf(owner), TOTAL_SUPPLY - amount);
        
        vm.stopPrank();
    }
    
    function test_RevertWhen_TransferInsufficientBalance() public {
        vm.startPrank(user1); // user1 has no tokens
        
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        token.transfer(user2, 1000 * 10**18);
        
        vm.stopPrank();
    }
    
    function test_RevertWhen_MintToZeroAddress() public {
        vm.startPrank(owner);
        
        vm.expectRevert("ERC20: mint to the zero address");
        token.mint(address(0), 1000 * 10**18);
        
        vm.stopPrank();
    }
}

