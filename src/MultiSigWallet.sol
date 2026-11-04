// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/IERC1155Upgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title MultiSigWallet
 * @dev Multi-signature wallet contract for LithosProtocol
 * 
 * Features:
 * - Multiple owners with configurable threshold
 * - Support for ETH, ERC20, ERC721, and ERC1155 transfers
 * - Transaction batching
 * - UUPS upgradeable pattern
 * - Pausable functionality
 * - Event logging for all operations
 */
contract MultiSigWallet is 
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable
{
    using ECDSA for bytes32;
    
    uint256 private _threshold;
    address[] private _owners;
    mapping(address => bool) private _isOwner;
    
    uint256 private _transactionCount;
    uint256 private _nonce;
    
    mapping(uint256 => Transaction) private _transactions;
    mapping(uint256 => mapping(address => bool)) private _approved;
    
    // Events
    event WalletInitialized(address[] owners, uint256 threshold);
    event OwnerAdded(address owner);
    event OwnerRemoved(address owner);
    event ThresholdChanged(uint256 newThreshold);
    event TransactionSubmitted(uint256 transactionId, address submitter);
    event TransactionApproved(uint256 transactionId, address approver);
    event TransactionRevoked(uint256 transactionId, address revoker);
    event TransactionExecuted(uint256 transactionId, address executor);
    event ETHTransferred(address to, uint256 amount, uint256 transactionId);
    event ERC20Transferred(address token, address to, uint256 amount, uint256 transactionId);
    event ERC721Transferred(address token, address to, uint256 tokenId, uint256 transactionId);
    event ERC1155Transferred(address token, address to, uint256 tokenId, uint256 amount, uint256 transactionId);
    
    // Structs
    struct Transaction {
        address to;
        uint256 value;
        bytes data;
        uint256 operation;
        bool executed;
        address submitter;
        uint256 submittedAt;
    }
    
    // Operation types
    uint256 private constant CALL = 0;
    uint256 private constant SEND = 1;
    uint256 private constant WITHDRAW = 2;
    
    // Modifiers
    modifier onlyMultisigOwner() {
        require(_isOwner[msg.sender], "MultiSigWallet: not an owner");
        _;
    }
    
    modifier onlyTransactionSubmitter(uint256 transactionId) {
        require(_transactions[transactionId].submitter == msg.sender, "MultiSigWallet: not the submitter");
        _;
    }
    
    modifier transactionExists(uint256 transactionId) {
        require(transactionId < _transactionCount, "MultiSigWallet: transaction does not exist");
        _;
    }
    
    modifier notExecuted(uint256 transactionId) {
        require(!_transactions[transactionId].executed, "MultiSigWallet: transaction already executed");
        _;
    }
    
    modifier notApproved(uint256 transactionId) {
        require(!_approved[transactionId][msg.sender], "MultiSigWallet: transaction already approved");
        _;
    }
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    /**
     * @dev Initialize the multi-signature wallet
     * @param owners Array of owner addresses
     * @param threshold Number of required approvals
     * @param initialOwner The initial owner (admin) of the contract
     */
    function initialize(
        address[] memory owners,
        uint256 threshold,
        address initialOwner
    ) initializer public {
        __UUPSUpgradeable_init();
        __Ownable_init();
        __AccessControl_init();
        __Pausable_init();
        
        require(owners.length > 0, "MultiSigWallet: owners required");
        require(threshold > 0 && threshold <= owners.length, "MultiSigWallet: invalid threshold");
        
        for (uint256 i = 0; i < owners.length; i++) {
            address owner = owners[i];
            require(owner != address(0), "MultiSigWallet: invalid owner");
            require(!_isOwner[owner], "MultiSigWallet: owner not unique");
            _isOwner[owner] = true;
            _owners.push(owner);
        }
        
        _threshold = threshold;
        _transferOwnership(initialOwner);
        _grantRole(DEFAULT_ADMIN_ROLE, initialOwner);
        
        emit WalletInitialized(owners, threshold);
    }
    
    /**
     * @dev Add a new owner
     * Only callable by owner with DEFAULT_ADMIN_ROLE
     * @param owner Address of the new owner
     */
    function addOwner(address owner) external onlyMultisigOwner {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "MultiSigWallet: only admin can add owner");
        require(owner != address(0), "MultiSigWallet: invalid owner");
        require(!_isOwner[owner], "MultiSigWallet: owner already exists");
        
        _isOwner[owner] = true;
        _owners.push(owner);
        
        emit OwnerAdded(owner);
    }
    
    /**
     * @dev Remove an owner
     * Only callable by owner with DEFAULT_ADMIN_ROLE
     * @param owner Address of the owner to remove
     */
    function removeOwner(address owner) external onlyMultisigOwner {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "MultiSigWallet: only admin can remove owner");
        require(_isOwner[owner], "MultiSigWallet: owner does not exist");
        require(_owners.length > _threshold || !_isOwner[msg.sender], "MultiSigWallet: cannot remove owner, threshold would be exceeded");
        
        _isOwner[owner] = false;
        
        // Remove from owners array
        for (uint256 i = 0; i < _owners.length; i++) {
            if (_owners[i] == owner) {
                _owners[i] = _owners[_owners.length - 1];
                _owners.pop();
                break;
            }
        }
        
        emit OwnerRemoved(owner);
    }
    
    /**
     * @dev Replace an owner with a new owner
     * Only callable by the owner being replaced
     * @param oldOwner Address of the owner to replace
     * @param newOwner Address of the new owner
     */
    function replaceOwner(address oldOwner, address newOwner) external onlyMultisigOwner {
        require(msg.sender == oldOwner, "MultiSigWallet: only owner can replace self");
        require(_isOwner[oldOwner], "MultiSigWallet: old owner does not exist");
        require(newOwner != address(0), "MultiSigWallet: invalid new owner");
        require(!_isOwner[newOwner], "MultiSigWallet: new owner already exists");
        
        _isOwner[oldOwner] = false;
        _isOwner[newOwner] = true;
        
        // Replace in owners array
        for (uint256 i = 0; i < _owners.length; i++) {
            if (_owners[i] == oldOwner) {
                _owners[i] = newOwner;
                break;
            }
        }
        
        emit OwnerRemoved(oldOwner);
        emit OwnerAdded(newOwner);
    }
    
    /**
     * @dev Change the required threshold
     * Only callable by owner with DEFAULT_ADMIN_ROLE
     * @param threshold New threshold value
     */
    function changeThreshold(uint256 threshold) external onlyMultisigOwner {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "MultiSigWallet: only admin can change threshold");
        require(threshold > 0 && threshold <= _owners.length, "MultiSigWallet: invalid threshold");
        
        _threshold = threshold;
        emit ThresholdChanged(threshold);
    }
    
    /**
     * @dev Get the current threshold
     * @return The threshold value
     */
    function getThreshold() external view returns (uint256) {
        return _threshold;
    }
    
    /**
     * @dev Get the list of owners
     * @return Array of owner addresses
     */
    function getOwners() external view returns (address[] memory) {
        return _owners;
    }
    
    /**
     * @dev Check if an address is an owner
     * @param owner Address to check
     * @return Boolean indicating if the address is an owner
     */
    function isOwner(address owner) external view returns (bool) {
        return _isOwner[owner];
    }
    
    /**
     * @dev Submit a new transaction
     * @param to Recipient address
     * @param value ETH value to send (0 for contract calls)
     * @param data Calldata for the transaction
     * @param operation Operation type (0 = CALL, 1 = SEND, 2 = WITHDRAW)
     * @return Transaction ID
     */
    function submitTransaction(
        address to,
        uint256 value,
        bytes memory data,
        uint256 operation
    ) public onlyMultisigOwner returns (uint256) {
        require(!paused(), "Pausable: paused");
        require(to != address(this), "MultiSigWallet: cannot submit transaction to self");
        require(operation <= 2, "MultiSigWallet: invalid operation");
        
        uint256 transactionId = _transactionCount;
        _transactionCount++;
        
        _transactions[transactionId] = Transaction({
            to: to,
            value: value,
            data: data,
            operation: operation,
            executed: false,
            submitter: msg.sender,
            submittedAt: block.timestamp
        });
        
        emit TransactionSubmitted(transactionId, msg.sender);
        
        return transactionId;
    }
    
    /**
     * @dev Approve a transaction
     * @param transactionId ID of the transaction to approve
     */
    function approveTransaction(uint256 transactionId) public onlyMultisigOwner transactionExists(transactionId) notExecuted(transactionId) notApproved(transactionId) {
        require(!paused(), "Pausable: paused");
        
        _approved[transactionId][msg.sender] = true;
        emit TransactionApproved(transactionId, msg.sender);
    }
    
    /**
     * @dev Revoke approval for a transaction
     * @param transactionId ID of the transaction to revoke
     */
    function revokeApproval(uint256 transactionId) external onlyMultisigOwner transactionExists(transactionId) notExecuted(transactionId) {
        require(!paused(), "Pausable: paused");
        require(_approved[transactionId][msg.sender], "MultiSigWallet: transaction not approved");
        
        _approved[transactionId][msg.sender] = false;
        emit TransactionRevoked(transactionId, msg.sender);
    }
    
    /**
     * @dev Check if a transaction is approved by an owner
     * @param transactionId ID of the transaction
     * @param owner Address of the owner
     * @return Boolean indicating if the transaction is approved
     */
    function isApproved(uint256 transactionId, address owner) external view returns (bool) {
        return _approved[transactionId][owner];
    }
    
    /**
     * @dev Get the number of approvals for a transaction
     * @param transactionId ID of the transaction
     * @return Number of approvals
     */
    function getApprovalCount(uint256 transactionId) public view returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 0; i < _owners.length; i++) {
            if (_approved[transactionId][_owners[i]]) {
                count++;
            }
        }
        return count;
    }
    
    /**
     * @dev Check if a transaction can be executed (has enough approvals)
     * @param transactionId ID of the transaction
     * @return Boolean indicating if the transaction can be executed
     */
    function canExecute(uint256 transactionId) public view returns (bool) {
        return getApprovalCount(transactionId) >= _threshold;
    }
    
    /**
     * @dev Execute a transaction
     * @param transactionId ID of the transaction to execute
     */
    function executeTransaction(uint256 transactionId) public onlyMultisigOwner transactionExists(transactionId) notExecuted(transactionId) {
        require(!paused(), "Pausable: paused");
        require(canExecute(transactionId), "MultiSigWallet: insufficient approvals");
        
        Transaction storage transaction = _transactions[transactionId];
        
        if (transaction.operation == SEND) {
            // Simple ETH transfer
            require(address(this).balance >= transaction.value, "MultiSigWallet: insufficient balance");
            (bool success, ) = transaction.to.call{value: transaction.value}("");
            require(success, "MultiSigWallet: transaction failed");
            emit ETHTransferred(transaction.to, transaction.value, transactionId);
        } else if (transaction.operation == WITHDRAW) {
            // Withdraw ETH to owner
            require(address(this).balance >= transaction.value, "MultiSigWallet: insufficient balance");
            (bool success, ) = payable(transaction.to).call{value: transaction.value}("");
            require(success, "MultiSigWallet: withdrawal failed");
        } else {
            // Contract call
            (bool success, ) = transaction.to.call{value: transaction.value}(transaction.data);
            require(success, "MultiSigWallet: transaction failed");
            
            // Emit specific events based on call data
            bytes memory txData = transaction.data;
            if (txData.length >= 4) {
                bytes4 selector;
                assembly { selector := shr(224, mload(add(txData, 32))) }
                if (selector == IERC20Upgradeable(transaction.to).transfer.selector) {
                    // ERC20 transfer
                    address recipient;
                    uint256 amount;
                    assembly {
                        let dataPtr := add(txData, 36)
                        recipient := mload(dataPtr)
                        amount := mload(add(dataPtr, 32))
                    }
                    emit ERC20Transferred(transaction.to, recipient, amount, transactionId);
                } else if (selector == IERC721Upgradeable(transaction.to).transferFrom.selector ||
                           selector == bytes4(0x42842e0e) /* safeTransferFrom(address,address,uint256) */) {
                    // ERC721 transfer
                    uint256 tokenId;
                    assembly {
                        let dataPtr := add(txData, 68)
                        tokenId := mload(dataPtr)
                    }
                    emit ERC721Transferred(transaction.to, transaction.to, tokenId, transactionId);
                } else if (selector == IERC1155Upgradeable(transaction.to).safeTransferFrom.selector) {
                    // ERC1155 transfer
                    uint256 tokenId;
                    uint256 amount;
                    assembly {
                        let dataPtr := add(txData, 68)
                        tokenId := mload(dataPtr)
                        amount := mload(add(dataPtr, 32))
                    }
                    emit ERC1155Transferred(transaction.to, transaction.to, tokenId, amount, transactionId);
                }
            }
        }
        
        transaction.executed = true;
        emit TransactionExecuted(transactionId, msg.sender);
    }
    
    /**
     * @dev Submit and execute a transaction in one call (if threshold is 1)
     * @param to Recipient address
     * @param value ETH value to send
     * @param data Calldata for the transaction
     * @param operation Operation type
     */
    function submitAndExecute(
        address to,
        uint256 value,
        bytes memory data,
        uint256 operation
    ) external onlyMultisigOwner {
        require(!paused(), "Pausable: paused");
        require(_threshold == 1, "MultiSigWallet: can only submitAndExecute with threshold of 1");
        
        uint256 transactionId = submitTransaction(to, value, data, operation);
        approveTransaction(transactionId);
        executeTransaction(transactionId);
    }
    
    /**
     * @dev Get transaction details
     * @param transactionId ID of the transaction
     * @return Transaction details
     */
    function getTransaction(uint256 transactionId) external view returns (Transaction memory) {
        return _transactions[transactionId];
    }
    
    /**
     * @dev Get the current nonce
     * @return The nonce value
     */
    function getNonce() external view returns (uint256) {
        return _nonce;
    }
    
    /**
     * @dev Increment the nonce (for off-chain signature verification)
     */
    function incrementNonce() external {
        _nonce++;
    }
    
    /**
     * @dev Get the contract's ETH balance
     * @return The balance in wei
     */
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }
    
    /**
     * @dev Get the number of transactions
     * @return The transaction count
     */
    function getTransactionCount() external view returns (uint256) {
        return _transactionCount;
    }
    
    /**
     * @dev Get the list of approved transactions for an owner
     * @param owner Address of the owner
     * @return Array of approved transaction IDs
     */
    function getApprovedTransactions(address owner) external view returns (uint256[] memory) {
        uint256[] memory approved = new uint256[](_transactionCount);
        uint256 count = 0;
        
        for (uint256 i = 0; i < _transactionCount; i++) {
            if (_approved[i][owner]) {
                approved[count] = i;
                count++;
            }
        }
        
        // Resize array
        uint256[] memory result = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = approved[i];
        }
        
        return result;
    }
    
    /**
     * @dev Pause the contract
     * Only callable by owner
     */
    function pause() public onlyMultisigOwner {
        _pause();
    }
    
    /**
     * @dev Unpause the contract
     * Only callable by owner
     */
    function unpause() public onlyMultisigOwner {
        _unpause();
    }
    
    /**
     * @dev Required by UUPS pattern
     * Only owner can authorize upgrades
     */
    function _authorizeUpgrade(address newImplementation)
        internal
        onlyMultisigOwner
        override
    {}
    
    // Fallback function to receive ETH
    receive() external payable {}
    
    // Fallback function for contract calls
    fallback() external payable {
        require(!paused(), "Pausable: paused");
        revert("MultiSigWallet: use submitTransaction for contract calls");
    }
}

