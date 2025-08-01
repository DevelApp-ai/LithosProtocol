using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using UnityEngine;
using Nethereum.Web3;
using Nethereum.Web3.Accounts;
using Nethereum.Signer;

namespace LithosProtocol.Web3.Enhanced
{
    /// <summary>
    /// Enhanced session manager for seamless Unity integration
    /// Handles session keys, delegate wallets, and non-intrusive transaction management
    /// </summary>
    public class LithosSessionManager : MonoBehaviour
    {
        [Header("Session Configuration")]
        [SerializeField] private int sessionDurationHours = 24;
        [SerializeField] private bool autoRenewSessions = true;
        [SerializeField] private int maxSessionActions = 1000;
        
        [Header("Delegate Wallet Settings")]
        [SerializeField] private bool useDelegateWallet = true;
        [SerializeField] private float lowStakeActionThreshold = 0.01f; // ETH value
        
        // Events
        public event Action<string> OnSessionCreated;
        public event Action OnSessionExpired;
        public event Action<string> OnTransactionQueued;
        public event Action<string, bool> OnTransactionCompleted;
        public event Action<string> OnError;

        // Session data
        private SessionData currentSession;
        private Queue<PendingTransaction> transactionQueue;
        private bool isProcessingQueue;
        
        // Delegate wallet
        private Account delegateAccount;
        private Web3 delegateWeb3;
        
        // Main wallet
        private Web3 mainWeb3;
        private string playerAddress;

        private void Awake()
        {
            transactionQueue = new Queue<PendingTransaction>();
            
            // Load existing session if available
            LoadSession();
        }

        private void Start()
        {
            // Start transaction processing coroutine
            if (useDelegateWallet)
            {
                StartCoroutine(ProcessTransactionQueue());
            }
        }

        /// <summary>
        /// Initialize session manager with main wallet
        /// </summary>
        /// <param name="web3">Main Web3 instance</param>
        /// <param name="playerAddr">Player wallet address</param>
        public async Task InitializeAsync(Web3 web3, string playerAddr)
        {
            mainWeb3 = web3;
            playerAddress = playerAddr;
            
            if (useDelegateWallet)
            {
                await CreateDelegateWallet();
            }
            
            await CreateOrRenewSession();
        }

        /// <summary>
        /// Create a new delegate wallet for low-stakes transactions
        /// </summary>
        private async Task CreateDelegateWallet()
        {
            try
            {
                // Generate new delegate account
                var ecKey = EthECKey.GenerateKey();
                delegateAccount = new Account(ecKey.GetPrivateKey());
                
                // Initialize Web3 with delegate account
                string rpcUrl = GetComponent<LithosWeb3Manager>().GetCurrentRpcUrl();
                delegateWeb3 = new Web3(delegateAccount, rpcUrl);
                
                Debug.Log($"Delegate wallet created: {delegateAccount.Address}");
                
                // Fund delegate wallet if needed
                await FundDelegateWallet();
            }
            catch (Exception ex)
            {
                Debug.LogError($"Failed to create delegate wallet: {ex.Message}");
                OnError?.Invoke($"Delegate wallet creation failed: {ex.Message}");
            }
        }

        /// <summary>
        /// Fund the delegate wallet with a small amount for gas
        /// </summary>
        private async Task FundDelegateWallet()
        {
            try
            {
                // Check delegate wallet balance
                var balance = await delegateWeb3.Eth.GetBalance.SendRequestAsync(delegateAccount.Address);
                var balanceEth = Web3.Convert.FromWei(balance.Value);
                
                if (balanceEth < 0.001m) // Less than 0.001 ETH
                {
                    // Request funding from main wallet
                    var fundingAmount = Web3.Convert.ToWei(0.01m); // 0.01 ETH
                    
                    var transactionInput = new Nethereum.RPC.Eth.DTOs.TransactionInput()
                    {
                        To = delegateAccount.Address,
                        Value = new Nethereum.Hex.HexTypes.HexBigInteger(fundingAmount),
                        From = playerAddress
                    };
                    
                    // This would need user approval in a real implementation
                    Debug.Log($"Delegate wallet needs funding: {delegateAccount.Address}");
                }
            }
            catch (Exception ex)
            {
                Debug.LogError($"Failed to fund delegate wallet: {ex.Message}");
            }
        }

        /// <summary>
        /// Create or renew the current session
        /// </summary>
        private async Task CreateOrRenewSession()
        {
            try
            {
                var sessionId = Guid.NewGuid().ToString();
                var expiryTime = DateTime.UtcNow.AddHours(sessionDurationHours);
                
                currentSession = new SessionData
                {
                    SessionId = sessionId,
                    PlayerAddress = playerAddress,
                    DelegateAddress = delegateAccount?.Address,
                    CreatedAt = DateTime.UtcNow,
                    ExpiresAt = expiryTime,
                    ActionsRemaining = maxSessionActions,
                    IsActive = true
                };
                
                // Save session to persistent storage
                SaveSession();
                
                OnSessionCreated?.Invoke(sessionId);
                Debug.Log($"Session created: {sessionId}, expires: {expiryTime}");
            }
            catch (Exception ex)
            {
                Debug.LogError($"Failed to create session: {ex.Message}");
                OnError?.Invoke($"Session creation failed: {ex.Message}");
            }
        }

        /// <summary>
        /// Execute a game action with automatic transaction management
        /// </summary>
        /// <param name="actionType">Type of action (quest, craft, etc.)</param>
        /// <param name="parameters">Action parameters</param>
        /// <param name="estimatedGasCost">Estimated gas cost in ETH</param>
        public async Task<string> ExecuteGameActionAsync(
            GameActionType actionType, 
            Dictionary<string, object> parameters,
            float estimatedGasCost = 0f)
        {
            if (!IsSessionValid())
            {
                await CreateOrRenewSession();
            }

            try
            {
                // Determine if this should use delegate wallet
                bool useDelegateForAction = useDelegateWallet && 
                                          estimatedGasCost <= lowStakeActionThreshold &&
                                          CanUseDelegateWallet(actionType);

                var transaction = new PendingTransaction
                {
                    Id = Guid.NewGuid().ToString(),
                    ActionType = actionType,
                    Parameters = parameters,
                    EstimatedGasCost = estimatedGasCost,
                    UseDelegateWallet = useDelegateForAction,
                    CreatedAt = DateTime.UtcNow,
                    Status = TransactionStatus.Pending
                };

                if (useDelegateForAction)
                {
                    // Queue for background processing
                    transactionQueue.Enqueue(transaction);
                    OnTransactionQueued?.Invoke(transaction.Id);
                    
                    // Optimistically update UI
                    return transaction.Id;
                }
                else
                {
                    // Requires main wallet approval
                    return await ExecuteWithMainWallet(transaction);
                }
            }
            catch (Exception ex)
            {
                Debug.LogError($"Failed to execute game action: {ex.Message}");
                OnError?.Invoke($"Action execution failed: {ex.Message}");
                return null;
            }
        }

        /// <summary>
        /// Process queued transactions in the background
        /// </summary>
        private System.Collections.IEnumerator ProcessTransactionQueue()
        {
            while (true)
            {
                if (!isProcessingQueue && transactionQueue.Count > 0)
                {
                    isProcessingQueue = true;
                    
                    var transaction = transactionQueue.Dequeue();
                    
                    // Process transaction asynchronously
                    _ = ProcessDelegateTransaction(transaction);
                }
                
                yield return new WaitForSeconds(1f); // Check every second
            }
        }

        /// <summary>
        /// Process a transaction using the delegate wallet
        /// </summary>
        private async Task ProcessDelegateTransaction(PendingTransaction transaction)
        {
            try
            {
                transaction.Status = TransactionStatus.Processing;
                
                // Execute the actual blockchain transaction
                string txHash = await ExecuteBlockchainTransaction(transaction);
                
                if (!string.IsNullOrEmpty(txHash))
                {
                    transaction.Status = TransactionStatus.Completed;
                    transaction.TransactionHash = txHash;
                    
                    // Consume session action
                    currentSession.ActionsRemaining--;
                    SaveSession();
                    
                    OnTransactionCompleted?.Invoke(transaction.Id, true);
                }
                else
                {
                    transaction.Status = TransactionStatus.Failed;
                    OnTransactionCompleted?.Invoke(transaction.Id, false);
                }
            }
            catch (Exception ex)
            {
                Debug.LogError($"Failed to process delegate transaction: {ex.Message}");
                transaction.Status = TransactionStatus.Failed;
                OnTransactionCompleted?.Invoke(transaction.Id, false);
            }
            finally
            {
                isProcessingQueue = false;
            }
        }

        /// <summary>
        /// Execute transaction with main wallet (requires user approval)
        /// </summary>
        private async Task<string> ExecuteWithMainWallet(PendingTransaction transaction)
        {
            // This would show a transaction approval UI
            Debug.Log($"Requesting main wallet approval for: {transaction.ActionType}");
            
            // Simulate user approval (in real implementation, this would be async)
            await Task.Delay(1000);
            
            return await ExecuteBlockchainTransaction(transaction);
        }

        /// <summary>
        /// Execute the actual blockchain transaction
        /// </summary>
        private async Task<string> ExecuteBlockchainTransaction(PendingTransaction transaction)
        {
            try
            {
                Web3 web3ToUse = transaction.UseDelegateWallet ? delegateWeb3 : mainWeb3;
                
                // This is a simplified example - real implementation would call specific contract methods
                switch (transaction.ActionType)
                {
                    case GameActionType.CompleteQuest:
                        return await ExecuteQuestCompletion(web3ToUse, transaction.Parameters);
                    
                    case GameActionType.CraftItem:
                        return await ExecuteCrafting(web3ToUse, transaction.Parameters);
                    
                    case GameActionType.PvPBattle:
                        return await ExecutePvPAction(web3ToUse, transaction.Parameters);
                    
                    default:
                        throw new NotImplementedException($"Action type {transaction.ActionType} not implemented");
                }
            }
            catch (Exception ex)
            {
                Debug.LogError($"Blockchain transaction failed: {ex.Message}");
                return null;
            }
        }

        // Placeholder methods for specific game actions
        private async Task<string> ExecuteQuestCompletion(Web3 web3, Dictionary<string, object> parameters)
        {
            // Implementation would call GameLogic contract
            await Task.Delay(100); // Simulate network delay
            return "0x" + Guid.NewGuid().ToString("N");
        }

        private async Task<string> ExecuteCrafting(Web3 web3, Dictionary<string, object> parameters)
        {
            // Implementation would call crafting functions
            await Task.Delay(100);
            return "0x" + Guid.NewGuid().ToString("N");
        }

        private async Task<string> ExecutePvPAction(Web3 web3, Dictionary<string, object> parameters)
        {
            // Implementation would call PvP functions
            await Task.Delay(100);
            return "0x" + Guid.NewGuid().ToString("N");
        }

        /// <summary>
        /// Check if session is still valid
        /// </summary>
        private bool IsSessionValid()
        {
            return currentSession != null && 
                   currentSession.IsActive && 
                   DateTime.UtcNow < currentSession.ExpiresAt &&
                   currentSession.ActionsRemaining > 0;
        }

        /// <summary>
        /// Check if delegate wallet can be used for this action type
        /// </summary>
        private bool CanUseDelegateWallet(GameActionType actionType)
        {
            // Define which actions can use delegate wallet
            return actionType == GameActionType.CompleteQuest ||
                   actionType == GameActionType.CraftItem ||
                   actionType == GameActionType.RepairItem;
        }

        /// <summary>
        /// Save session to persistent storage
        /// </summary>
        private void SaveSession()
        {
            if (currentSession != null)
            {
                string sessionJson = JsonUtility.ToJson(currentSession);
                PlayerPrefs.SetString("LithosSession", sessionJson);
                PlayerPrefs.Save();
            }
        }

        /// <summary>
        /// Load session from persistent storage
        /// </summary>
        private void LoadSession()
        {
            if (PlayerPrefs.HasKey("LithosSession"))
            {
                string sessionJson = PlayerPrefs.GetString("LithosSession");
                currentSession = JsonUtility.FromJson<SessionData>(sessionJson);
                
                // Validate loaded session
                if (!IsSessionValid())
                {
                    currentSession = null;
                }
            }
        }

        /// <summary>
        /// Get current session information
        /// </summary>
        public SessionInfo GetSessionInfo()
        {
            if (currentSession == null)
                return null;

            return new SessionInfo
            {
                SessionId = currentSession.SessionId,
                IsActive = IsSessionValid(),
                ExpiresAt = currentSession.ExpiresAt,
                ActionsRemaining = currentSession.ActionsRemaining,
                DelegateWalletAddress = currentSession.DelegateAddress
            };
        }

        /// <summary>
        /// Manually renew the current session
        /// </summary>
        public async Task RenewSessionAsync()
        {
            await CreateOrRenewSession();
        }

        private void OnDestroy()
        {
            SaveSession();
        }
    }

    // Data structures
    [Serializable]
    public class SessionData
    {
        public string SessionId;
        public string PlayerAddress;
        public string DelegateAddress;
        public DateTime CreatedAt;
        public DateTime ExpiresAt;
        public int ActionsRemaining;
        public bool IsActive;
    }

    public class SessionInfo
    {
        public string SessionId;
        public bool IsActive;
        public DateTime ExpiresAt;
        public int ActionsRemaining;
        public string DelegateWalletAddress;
    }

    public class PendingTransaction
    {
        public string Id;
        public GameActionType ActionType;
        public Dictionary<string, object> Parameters;
        public float EstimatedGasCost;
        public bool UseDelegateWallet;
        public DateTime CreatedAt;
        public TransactionStatus Status;
        public string TransactionHash;
    }

    public enum GameActionType
    {
        CompleteQuest,
        CraftItem,
        RepairItem,
        PvPBattle,
        MarketplaceTrade,
        StakeTokens,
        UnstakeTokens
    }

    public enum TransactionStatus
    {
        Pending,
        Processing,
        Completed,
        Failed
    }
}

