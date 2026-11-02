// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/MultiSigWallet.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title MultiSigWallet Tests
 * @dev Comprehensive test suite for MultiSigWallet contract
 * 
 * Tests cover:
 * - Initialization
 * - Owner management
 * - Transaction submission and approval
 * - Transaction execution
 * - Threshold management
 * - Edge cases and error conditions
 */
contract MultiSigWalletTest is Test {
    event WalletInitialized(address[] owners, uint256 threshold);
    event OwnerAdded(address owner);
    event TransactionSubmitted(uint256 transactionId, address submitter);
    event TransactionApproved(uint256 transactionId, address approver);
    event TransactionExecuted(uint256 transactionId, address executor);
    event ETHTransferred(address to, uint256 amount, uint256 transactionId);

    MultiSigWallet public multiSig;
    
    address public owner1;
    address public owner2;
    address public owner3;
    address public nonOwner;
    
    uint256 public threshold = 2;
    
    // Setup
    function setUp() public {
        owner1 = address(1);
        owner2 = address(2);
        owner3 = address(3);
        nonOwner = address(4);
        
        address[] memory owners = new address[](3);
        owners[0] = owner1;
        owners[1] = owner2;
        owners[2] = owner3;
        
        // Deploy behind an ERC1967 proxy (constructor disables direct initialization)
        MultiSigWallet implementation = new MultiSigWallet();
        bytes memory initData = abi.encodeCall(
            MultiSigWallet.initialize,
            (owners, threshold, owner1)
        );
        multiSig = MultiSigWallet(payable(address(new ERC1967Proxy(address(implementation), initData))));
    }
    
    /// @dev Deploys a fresh wallet behind an ERC1967 proxy (constructor disables direct init)
    function _deployWallet(
        address[] memory owners_,
        uint256 threshold_,
        address initialOwner_
    ) internal returns (MultiSigWallet wallet) {
        MultiSigWallet impl = new MultiSigWallet();
        bytes memory initData = abi.encodeCall(MultiSigWallet.initialize, (owners_, threshold_, initialOwner_));
        wallet = MultiSigWallet(payable(address(new ERC1967Proxy(address(impl), initData))));
    }

    // ========== INITIALIZATION TESTS ==========
    
    function testInitialize() public {
        address[] memory owners = multiSig.getOwners();
        assertEq(owners.length, 3);
        assertEq(owners[0], owner1);
        assertEq(owners[1], owner2);
        assertEq(owners[2], owner3);
        
        assertEq(multiSig.getThreshold(), threshold);
        assertTrue(multiSig.isOwner(owner1));
        assertTrue(multiSig.isOwner(owner2));
        assertTrue(multiSig.isOwner(owner3));
        assertFalse(multiSig.isOwner(nonOwner));
    }
    
    function testInitializeRevertsWithEmptyOwners() public {
        address[] memory emptyOwners = new address[](0);
        MultiSigWallet badImpl = new MultiSigWallet();
        vm.expectRevert("MultiSigWallet: owners required");
        new ERC1967Proxy(address(badImpl), abi.encodeCall(MultiSigWallet.initialize, (emptyOwners, 1, owner1)));
    }
    
    function testInitializeRevertsWithZeroThreshold() public {
        address[] memory owners = new address[](1);
        owners[0] = owner1;
        MultiSigWallet badImpl = new MultiSigWallet();
        vm.expectRevert("MultiSigWallet: invalid threshold");
        new ERC1967Proxy(address(badImpl), abi.encodeCall(MultiSigWallet.initialize, (owners, 0, owner1)));
    }
    
    function testInitializeRevertsWithThresholdGreaterThanOwners() public {
        address[] memory owners = new address[](2);
        owners[0] = owner1;
        owners[1] = owner2;
        MultiSigWallet badImpl = new MultiSigWallet();
        vm.expectRevert("MultiSigWallet: invalid threshold");
        new ERC1967Proxy(address(badImpl), abi.encodeCall(MultiSigWallet.initialize, (owners, 3, owner1)));
    }
    
    function testInitializeRevertsWithInvalidOwner() public {
        address[] memory owners = new address[](1);
        owners[0] = address(0);
        MultiSigWallet badImpl = new MultiSigWallet();
        vm.expectRevert("MultiSigWallet: invalid owner");
        new ERC1967Proxy(address(badImpl), abi.encodeCall(MultiSigWallet.initialize, (owners, 1, owner1)));
    }
    
    // ========== OWNER MANAGEMENT TESTS ==========
    
    function testAddOwner() public {
        vm.prank(owner1);
        multiSig.addOwner(nonOwner);
        
        assertTrue(multiSig.isOwner(nonOwner));
        
        address[] memory owners = multiSig.getOwners();
        assertEq(owners.length, 4);
        assertEq(owners[3], nonOwner);
    }
    
    function testAddOwnerRevertsForNonAdmin() public {
        vm.prank(owner2);
        vm.expectRevert("MultiSigWallet: only admin can add owner");
        multiSig.addOwner(nonOwner);
    }
    
    function testAddOwnerRevertsForExistingOwner() public {
        vm.prank(owner1);
        vm.expectRevert("MultiSigWallet: owner already exists");
        multiSig.addOwner(owner1);
    }
    
    function testAddOwnerRevertsForZeroAddress() public {
        vm.prank(owner1);
        vm.expectRevert("MultiSigWallet: invalid owner");
        multiSig.addOwner(address(0));
    }
    
    function testRemoveOwner() public {
        vm.prank(owner1);
        multiSig.removeOwner(owner3);
        
        assertFalse(multiSig.isOwner(owner3));
        
        address[] memory owners = multiSig.getOwners();
        assertEq(owners.length, 2);
    }
    
    function testRemoveOwnerRevertsForNonAdmin() public {
        vm.prank(owner2);
        vm.expectRevert("MultiSigWallet: only admin can remove owner");
        multiSig.removeOwner(owner3);
    }
    
    function testRemoveOwnerRevertsForNonExistentOwner() public {
        vm.prank(owner1);
        vm.expectRevert("MultiSigWallet: owner does not exist");
        multiSig.removeOwner(nonOwner);
    }
    
    function testRemoveOwnerRevertsIfThresholdExceeded() public {
        // Set up a wallet with threshold = 3 and 3 owners
        address[] memory owners = new address[](3);
        owners[0] = owner1;
        owners[1] = owner2;
        owners[2] = owner3;
        
        MultiSigWallet tempMultiSig = _deployWallet(owners, 3, owner1);
        
        vm.prank(owner1);
        vm.expectRevert("MultiSigWallet: cannot remove owner, threshold would be exceeded");
        tempMultiSig.removeOwner(owner2);
    }
    
    function testReplaceOwner() public {
        vm.prank(owner1);
        multiSig.replaceOwner(owner1, nonOwner);
        
        assertFalse(multiSig.isOwner(owner1));
        assertTrue(multiSig.isOwner(nonOwner));
        
        address[] memory owners = multiSig.getOwners();
        assertEq(owners.length, 3);
        
        // Check that nonOwner replaced owner1
        bool found = false;
        for (uint256 i = 0; i < owners.length; i++) {
            if (owners[i] == nonOwner) {
                found = true;
                break;
            }
        }
        assertTrue(found);
    }
    
    function testReplaceOwnerRevertsForNonOwner() public {
        vm.prank(owner2);
        vm.expectRevert("MultiSigWallet: only owner can replace self");
        multiSig.replaceOwner(owner1, nonOwner);
    }
    
    function testReplaceOwnerRevertsForNonExistentOldOwner() public {
        vm.prank(owner1);
        vm.expectRevert("MultiSigWallet: only owner can replace self");
        multiSig.replaceOwner(nonOwner, address(5));
    }
    
    function testReplaceOwnerRevertsForExistingNewOwner() public {
        vm.prank(owner1);
        vm.expectRevert("MultiSigWallet: new owner already exists");
        multiSig.replaceOwner(owner1, owner2);
    }
    
    function testChangeThreshold() public {
        vm.prank(owner1);
        multiSig.changeThreshold(1);
        
        assertEq(multiSig.getThreshold(), 1);
    }
    
    function testChangeThresholdRevertsForNonAdmin() public {
        vm.prank(owner2);
        vm.expectRevert("MultiSigWallet: only admin can change threshold");
        multiSig.changeThreshold(1);
    }
    
    function testChangeThresholdRevertsForInvalidThreshold() public {
        vm.prank(owner1);
        vm.expectRevert("MultiSigWallet: invalid threshold");
        multiSig.changeThreshold(0);
    }
    
    function testChangeThresholdRevertsForThresholdGreaterThanOwners() public {
        vm.prank(owner1);
        vm.expectRevert("MultiSigWallet: invalid threshold");
        multiSig.changeThreshold(4);
    }
    
    // ========== TRANSACTION TESTS ==========
    
    function testSubmitTransaction() public {
        vm.prank(owner1);
        uint256 txId = multiSig.submitTransaction(nonOwner, 1 ether, "", 1); // SEND operation
        
        assertEq(multiSig.getTransactionCount(), 1);
        
        MultiSigWallet.Transaction memory tx = multiSig.getTransaction(txId);
        assertEq(tx.to, nonOwner);
        assertEq(tx.value, 1 ether);
        assertEq(tx.operation, 1); // SEND
        assertFalse(tx.executed);
    }
    
    function testSubmitTransactionRevertsForNonOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert("MultiSigWallet: not an owner");
        multiSig.submitTransaction(nonOwner, 1 ether, "", 1);
    }
    
    function testSubmitTransactionRevertsForSelf() public {
        vm.prank(owner1);
        vm.expectRevert("MultiSigWallet: cannot submit transaction to self");
        multiSig.submitTransaction(address(multiSig), 1 ether, "", 1);
    }
    
    function testApproveTransaction() public {
        vm.prank(owner1);
        uint256 txId = multiSig.submitTransaction(nonOwner, 1 ether, "", 1);
        
        vm.prank(owner2);
        multiSig.approveTransaction(txId);
        
        assertTrue(multiSig.isApproved(txId, owner2));
        assertEq(multiSig.getApprovalCount(txId), 1);
    }
    
    function testApproveTransactionRevertsForNonOwner() public {
        vm.prank(owner1);
        uint256 txId = multiSig.submitTransaction(nonOwner, 1 ether, "", 1);
        
        vm.prank(nonOwner);
        vm.expectRevert("MultiSigWallet: not an owner");
        multiSig.approveTransaction(txId);
    }
    
    function testApproveTransactionRevertsForNonExistentTransaction() public {
        vm.prank(owner1);
        vm.expectRevert("MultiSigWallet: transaction does not exist");
        multiSig.approveTransaction(999);
    }
    
    function testApproveTransactionRevertsForAlreadyApproved() public {
        vm.prank(owner1);
        uint256 txId = multiSig.submitTransaction(nonOwner, 1 ether, "", 1);
        
        vm.prank(owner1);
        multiSig.approveTransaction(txId);
        
        vm.prank(owner1);
        vm.expectRevert("MultiSigWallet: transaction already approved");
        multiSig.approveTransaction(txId);
    }
    
    function testApproveTransactionRevertsForExecutedTransaction() public {
        vm.deal(address(multiSig), 2 ether);
        vm.prank(owner1);
        uint256 txId = multiSig.submitTransaction(nonOwner, 1 ether, "", 1);
        
        vm.prank(owner1);
        multiSig.approveTransaction(txId);
        
        vm.prank(owner2);
        multiSig.approveTransaction(txId);
        
        vm.prank(owner1);
        multiSig.executeTransaction(txId);
        
        vm.prank(owner3);
        vm.expectRevert("MultiSigWallet: transaction already executed");
        multiSig.approveTransaction(txId);
    }
    
    function testRevokeApproval() public {
        vm.prank(owner1);
        uint256 txId = multiSig.submitTransaction(nonOwner, 1 ether, "", 1);
        
        vm.prank(owner2);
        multiSig.approveTransaction(txId);
        
        vm.prank(owner2);
        multiSig.revokeApproval(txId);
        
        assertFalse(multiSig.isApproved(txId, owner2));
    }
    
    function testRevokeApprovalRevertsForNonApproved() public {
        vm.prank(owner1);
        uint256 txId = multiSig.submitTransaction(nonOwner, 1 ether, "", 1);
        
        vm.prank(owner2);
        vm.expectRevert("MultiSigWallet: transaction not approved");
        multiSig.revokeApproval(txId);
    }
    
    function testCanExecute() public {
        vm.prank(owner1);
        uint256 txId = multiSig.submitTransaction(nonOwner, 1 ether, "", 1);
        
        // Initially cannot execute
        assertFalse(multiSig.canExecute(txId));
        
        // After one approval
        vm.prank(owner1);
        multiSig.approveTransaction(txId);
        assertFalse(multiSig.canExecute(txId));
        
        // After second approval (meets threshold of 2)
        vm.prank(owner2);
        multiSig.approveTransaction(txId);
        assertTrue(multiSig.canExecute(txId));
    }
    
    function testExecuteTransactionETH() public {
        // Fund the wallet
        vm.deal(address(multiSig), 10 ether);
        
        vm.prank(owner1);
        uint256 txId = multiSig.submitTransaction(nonOwner, 1 ether, "", 1); // SEND operation
        
        vm.prank(owner1);
        multiSig.approveTransaction(txId);
        
        vm.prank(owner2);
        multiSig.approveTransaction(txId);
        
        uint256 balanceBefore = nonOwner.balance;
        
        vm.prank(owner1);
        multiSig.executeTransaction(txId);
        
        uint256 balanceAfter = nonOwner.balance;
        assertEq(balanceAfter - balanceBefore, 1 ether);
        
        MultiSigWallet.Transaction memory tx = multiSig.getTransaction(txId);
        assertTrue(tx.executed);
    }
    
    function testExecuteTransactionRevertsForInsufficientApprovals() public {
        vm.prank(owner1);
        uint256 txId = multiSig.submitTransaction(nonOwner, 1 ether, "", 1);
        
        vm.prank(owner1);
        multiSig.approveTransaction(txId);
        
        // Only one approval, need two
        vm.prank(owner1);
        vm.expectRevert("MultiSigWallet: insufficient approvals");
        multiSig.executeTransaction(txId);
    }
    
    function testExecuteTransactionRevertsForNonOwner() public {
        vm.prank(owner1);
        uint256 txId = multiSig.submitTransaction(nonOwner, 1 ether, "", 1);
        
        vm.prank(owner1);
        multiSig.approveTransaction(txId);
        
        vm.prank(owner2);
        multiSig.approveTransaction(txId);
        
        vm.prank(nonOwner);
        vm.expectRevert("MultiSigWallet: not an owner");
        multiSig.executeTransaction(txId);
    }
    
    function testExecuteTransactionRevertsForNonExistentTransaction() public {
        vm.prank(owner1);
        vm.expectRevert("MultiSigWallet: transaction does not exist");
        multiSig.executeTransaction(999);
    }
    
    function testExecuteTransactionRevertsForAlreadyExecuted() public {
        // Fund the wallet
        vm.deal(address(multiSig), 10 ether);
        
        vm.prank(owner1);
        uint256 txId = multiSig.submitTransaction(nonOwner, 1 ether, "", 1);
        
        vm.prank(owner1);
        multiSig.approveTransaction(txId);
        
        vm.prank(owner2);
        multiSig.approveTransaction(txId);
        
        vm.prank(owner1);
        multiSig.executeTransaction(txId);
        
        vm.prank(owner1);
        vm.expectRevert("MultiSigWallet: transaction already executed");
        multiSig.executeTransaction(txId);
    }
    
    function testExecuteTransactionWithInsufficientBalance() public {
        vm.prank(owner1);
        uint256 txId = multiSig.submitTransaction(nonOwner, 10 ether, "", 1);
        
        vm.prank(owner1);
        multiSig.approveTransaction(txId);
        
        vm.prank(owner2);
        multiSig.approveTransaction(txId);
        
        vm.prank(owner1);
        vm.expectRevert("MultiSigWallet: insufficient balance");
        multiSig.executeTransaction(txId);
    }
    
    function testSubmitAndExecute() public {
        // Set up a wallet with threshold = 1
        address[] memory owners = new address[](1);
        owners[0] = owner1;
        
        MultiSigWallet tempMultiSig = _deployWallet(owners, 1, owner1);
        
        vm.deal(address(tempMultiSig), 10 ether);
        
        vm.prank(owner1);
        tempMultiSig.submitAndExecute(nonOwner, 1 ether, "", 1);
        
        assertEq(nonOwner.balance, 1 ether);
    }
    
    function testSubmitAndExecuteRevertsForThresholdNotOne() public {
        vm.deal(address(multiSig), 10 ether);
        
        vm.prank(owner1);
        vm.expectRevert("MultiSigWallet: can only submitAndExecute with threshold of 1");
        multiSig.submitAndExecute(nonOwner, 1 ether, "", 1);
    }
    
    // ========== PAUSABLE TESTS ==========
    
    function testPause() public {
        vm.prank(owner1);
        multiSig.pause();
        
        assertTrue(multiSig.paused());
    }
    
    function testPauseRevertsForNonOwner() public {
        vm.expectRevert("MultiSigWallet: not an owner");
        vm.prank(nonOwner);
        multiSig.pause();
    }
    
    function testUnpause() public {
        vm.prank(owner1);
        multiSig.pause();
        
        vm.prank(owner1);
        multiSig.unpause();
        
        assertFalse(multiSig.paused());
    }
    
    function testSubmitTransactionRevertsWhenPaused() public {
        vm.prank(owner1);
        multiSig.pause();
        
        vm.prank(owner1);
        vm.expectRevert("Pausable: paused");
        multiSig.submitTransaction(nonOwner, 1 ether, "", 1);
    }
    
    function testApproveTransactionRevertsWhenPaused() public {
        vm.prank(owner1);
        uint256 txId = multiSig.submitTransaction(nonOwner, 1 ether, "", 1);
        
        vm.prank(owner1);
        multiSig.pause();
        
        vm.prank(owner2);
        vm.expectRevert("Pausable: paused");
        multiSig.approveTransaction(txId);
    }
    
    function testExecuteTransactionRevertsWhenPaused() public {
        vm.deal(address(multiSig), 10 ether);
        
        vm.prank(owner1);
        uint256 txId = multiSig.submitTransaction(nonOwner, 1 ether, "", 1);
        
        vm.prank(owner1);
        multiSig.approveTransaction(txId);
        
        vm.prank(owner2);
        multiSig.approveTransaction(txId);
        
        vm.prank(owner1);
        multiSig.pause();
        
        vm.prank(owner1);
        vm.expectRevert("Pausable: paused");
        multiSig.executeTransaction(txId);
    }
    
    // ========== GETTER TESTS ==========
    
    function testGetApprovedTransactions() public {
        vm.startPrank(owner1);
        uint256 txId1 = multiSig.submitTransaction(nonOwner, 1 ether, "", 1);
        uint256 txId2 = multiSig.submitTransaction(nonOwner, 2 ether, "", 1);
        uint256 txId3 = multiSig.submitTransaction(nonOwner, 3 ether, "", 1);
        
        multiSig.approveTransaction(txId1);
        multiSig.approveTransaction(txId3);
        vm.stopPrank();
        
        uint256[] memory approved = multiSig.getApprovedTransactions(owner1);
        assertEq(approved.length, 2);
        
        // Check that txId1 and txId3 are in the array
        bool found1 = false;
        bool found3 = false;
        for (uint256 i = 0; i < approved.length; i++) {
            if (approved[i] == txId1) found1 = true;
            if (approved[i] == txId3) found3 = true;
        }
        assertTrue(found1);
        assertTrue(found3);
    }
    
    function testGetBalance() public {
        vm.deal(address(multiSig), 10 ether);
        
        assertEq(multiSig.getBalance(), 10 ether);
    }
    
    function testGetNonce() public {
        assertEq(multiSig.getNonce(), 0);
        
        multiSig.incrementNonce();
        assertEq(multiSig.getNonce(), 1);
    }
    
    // ========== EVENT TESTS ==========
    
    function testWalletInitializedEvent() public {
        address[] memory owners = new address[](2);
        owners[0] = address(100);
        owners[1] = address(200);
        
        MultiSigWallet tempImpl = new MultiSigWallet();
        
        vm.expectEmit(true, true, true, true);
        emit WalletInitialized(owners, 1);
        
        MultiSigWallet tempMultiSig = MultiSigWallet(payable(address(new ERC1967Proxy(
            address(tempImpl),
            abi.encodeCall(MultiSigWallet.initialize, (owners, 1, address(100)))
        ))));
    }
    
    function testOwnerAddedEvent() public {
        vm.prank(owner1);
        
        vm.expectEmit(true, true, true, true);
        emit OwnerAdded(nonOwner);
        
        multiSig.addOwner(nonOwner);
    }
    
    function testTransactionSubmittedEvent() public {
        vm.prank(owner1);
        
        vm.expectEmit(true, true, true, true);
        emit TransactionSubmitted(0, owner1);
        
        multiSig.submitTransaction(nonOwner, 1 ether, "", 1);
    }
    
    function testTransactionApprovedEvent() public {
        vm.prank(owner1);
        uint256 txId = multiSig.submitTransaction(nonOwner, 1 ether, "", 1);
        
        vm.prank(owner2);
        
        vm.expectEmit(true, true, true, true);
        emit TransactionApproved(txId, owner2);
        
        multiSig.approveTransaction(txId);
    }
    
    function testTransactionExecutedEvent() public {
        vm.deal(address(multiSig), 10 ether);
        
        vm.prank(owner1);
        uint256 txId = multiSig.submitTransaction(nonOwner, 1 ether, "", 1);
        
        vm.prank(owner1);
        multiSig.approveTransaction(txId);
        
        vm.prank(owner2);
        multiSig.approveTransaction(txId);
        
        vm.prank(owner1);
        
        vm.expectEmit(true, true, true, true);
        emit TransactionExecuted(txId, owner1);
        
        multiSig.executeTransaction(txId);
    }
    
    function testETHTransferredEvent() public {
        vm.deal(address(multiSig), 10 ether);
        
        vm.prank(owner1);
        uint256 txId = multiSig.submitTransaction(nonOwner, 1 ether, "", 1);
        
        vm.prank(owner1);
        multiSig.approveTransaction(txId);
        
        vm.prank(owner2);
        multiSig.approveTransaction(txId);
        
        vm.prank(owner1);
        
        vm.expectEmit(true, true, true, true);
        emit ETHTransferred(nonOwner, 1 ether, txId);
        
        multiSig.executeTransaction(txId);
    }
    
    // ========== EDGE CASES ==========
    
    function testMultipleTransactions() public {
        // Fund the wallet
        vm.deal(address(multiSig), 100 ether);
        
        // Submit multiple transactions
        vm.prank(owner1);
        uint256 txId1 = multiSig.submitTransaction(nonOwner, 10 ether, "", 1);
        
        vm.prank(owner2);
        uint256 txId2 = multiSig.submitTransaction(nonOwner, 20 ether, "", 1);
        
        vm.prank(owner3);
        uint256 txId3 = multiSig.submitTransaction(nonOwner, 30 ether, "", 1);
        
        // Approve all transactions
        vm.startPrank(owner1);
        multiSig.approveTransaction(txId1);
        multiSig.approveTransaction(txId2);
        multiSig.approveTransaction(txId3);
        vm.stopPrank();
        
        vm.startPrank(owner2);
        multiSig.approveTransaction(txId1);
        multiSig.approveTransaction(txId2);
        multiSig.approveTransaction(txId3);
        vm.stopPrank();
        
        // Execute all transactions
        vm.startPrank(owner1);
        multiSig.executeTransaction(txId1);
        multiSig.executeTransaction(txId2);
        multiSig.executeTransaction(txId3);
        vm.stopPrank();
        
        // Check final balance
        assertEq(nonOwner.balance, 60 ether);
    }
    
    function testTransactionOrdering() public {
        vm.deal(address(multiSig), 100 ether);
        
        // Submit transactions in order
        vm.startPrank(owner1);
        uint256 txId1 = multiSig.submitTransaction(nonOwner, 1 ether, "", 1);
        uint256 txId2 = multiSig.submitTransaction(nonOwner, 2 ether, "", 1);
        uint256 txId3 = multiSig.submitTransaction(nonOwner, 3 ether, "", 1);
        vm.stopPrank();
        
        // Execute in different order
        vm.startPrank(owner1);
        multiSig.approveTransaction(txId1);
        multiSig.approveTransaction(txId2);
        multiSig.approveTransaction(txId3);
        vm.stopPrank();
        
        vm.startPrank(owner2);
        multiSig.approveTransaction(txId1);
        multiSig.approveTransaction(txId2);
        multiSig.approveTransaction(txId3);
        vm.stopPrank();
        
        vm.startPrank(owner1);
        multiSig.executeTransaction(txId2); // Execute second first
        multiSig.executeTransaction(txId1); // Then first
        multiSig.executeTransaction(txId3); // Then third
        vm.stopPrank();
        
        assertEq(nonOwner.balance, 6 ether);
    }
    
    function testReceiveETH() public {
        uint256 balanceBefore = address(multiSig).balance;
        
        vm.deal(address(multiSig), 10 ether);
        
        uint256 balanceAfter = address(multiSig).balance;
        assertEq(balanceAfter - balanceBefore, 10 ether);
    }
    
    function testFallbackReverts() public {
        vm.deal(owner1, 1 ether);
        vm.prank(owner1);
        vm.expectRevert("MultiSigWallet: use submitTransaction for contract calls");
        IBogusCaller(address(multiSig)).bogusCall{value: 1 ether}();
    }
}

interface IBogusCaller {
    function bogusCall() external payable;
}
