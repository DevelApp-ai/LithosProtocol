using System;
using System.Collections;
using System.Collections.Generic;
using System.Numerics;
using System.Threading.Tasks;
using UnityEngine;
using Nethereum.Web3;
using Nethereum.Web3.Accounts;
using Nethereum.Contracts;
using Nethereum.Hex.HexTypes;
using Nethereum.RPC.Eth.DTOs;

namespace LithosProtocol.Web3
{
    /// <summary>
    /// Main Web3 manager for LithosProtocol Unity integration
    /// Handles blockchain interactions, wallet connections, and smart contract calls
    /// </summary>
    public class LithosWeb3Manager : MonoBehaviour
    {
        [Header("Network Configuration")]
        [SerializeField] private string rpcUrl = "https://sepolia.infura.io/v3/YOUR_INFURA_KEY";
        [SerializeField] private string networkName = "Sepolia Testnet";
        [SerializeField] private int chainId = 11155111;

        [Header("Contract Addresses")]
        [SerializeField] private string governanceTokenAddress;
        [SerializeField] private string utilityTokenAddress;
        [SerializeField] private string gameAssetNFTAddress;
        [SerializeField] private string gameResourceNFTAddress;
        [SerializeField] private string gameLogicAddress;
        [SerializeField] private string marketplaceAddress;
        [SerializeField] private string stakingAddress;

        [Header("Wallet Configuration")]
        [SerializeField] private bool useMetaMask = true;
        [SerializeField] private bool autoConnect = false;

        // Web3 instances
        private Web3 web3;
        private Account account;
        private string connectedAddress;

        // Contract instances
        private Contract governanceTokenContract;
        private Contract utilityTokenContract;
        private Contract gameAssetNFTContract;
        private Contract gameResourceNFTContract;
        private Contract gameLogicContract;
        private Contract marketplaceContract;
        private Contract stakingContract;

        // Events
        public event Action<string> OnWalletConnected;
        public event Action OnWalletDisconnected;
        public event Action<string> OnTransactionSent;
        public event Action<string> OnTransactionConfirmed;
        public event Action<string> OnError;

        // Player data
        public PlayerData CurrentPlayerData { get; private set; }

        private void Awake()
        {
            // Singleton pattern
            if (FindObjectsOfType<AetheriumWeb3Manager>().Length > 1)
            {
                Destroy(gameObject);
                return;
            }
            DontDestroyOnLoad(gameObject);
        }

        private void Start()
        {
            if (autoConnect)
            {
                StartCoroutine(AutoConnectWallet());
            }
        }

        #region Wallet Connection

        /// <summary>
        /// Connect to MetaMask or other Web3 wallet
        /// </summary>
        public async Task<bool> ConnectWallet()
        {
            try
            {
                if (useMetaMask)
                {
                    return await ConnectMetaMask();
                }
                else
                {
                    // For development/testing with private key
                    return ConnectWithPrivateKey();
                }
            }
            catch (Exception ex)
            {
                Debug.LogError($"Failed to connect wallet: {ex.Message}");
                OnError?.Invoke($"Wallet connection failed: {ex.Message}");
                return false;
            }
        }

        private async Task<bool> ConnectMetaMask()
        {
            // Note: In a real Unity implementation, you would use a Web3 plugin like Web3.Unity
            // This is a simplified example showing the structure
            
            try
            {
                // Initialize Web3 with MetaMask provider
                web3 = new Web3(rpcUrl);
                
                // Get connected account (this would come from MetaMask in real implementation)
                var accounts = await web3.Eth.Accounts.SendRequestAsync();
                if (accounts != null && accounts.Length > 0)
                {
                    connectedAddress = accounts[0];
                    await InitializeContracts();
                    OnWalletConnected?.Invoke(connectedAddress);
                    Debug.Log($"Connected to wallet: {connectedAddress}");
                    return true;
                }
                
                return false;
            }
            catch (Exception ex)
            {
                Debug.LogError($"MetaMask connection failed: {ex.Message}");
                return false;
            }
        }

        private bool ConnectWithPrivateKey()
        {
            try
            {
                // For development only - never use in production
                string privateKey = "YOUR_PRIVATE_KEY_HERE";
                account = new Account(privateKey, chainId);
                web3 = new Web3(account, rpcUrl);
                connectedAddress = account.Address;
                
                StartCoroutine(InitializeContractsCoroutine());
                OnWalletConnected?.Invoke(connectedAddress);
                Debug.Log($"Connected with private key: {connectedAddress}");
                return true;
            }
            catch (Exception ex)
            {
                Debug.LogError($"Private key connection failed: {ex.Message}");
                return false;
            }
        }

        private IEnumerator AutoConnectWallet()
        {
            yield return new WaitForSeconds(1f);
            _ = ConnectWallet();
        }

        public void DisconnectWallet()
        {
            web3 = null;
            account = null;
            connectedAddress = null;
            CurrentPlayerData = null;
            OnWalletDisconnected?.Invoke();
            Debug.Log("Wallet disconnected");
        }

        #endregion

        #region Contract Initialization

        private async Task InitializeContracts()
        {
            try
            {
                // Initialize contract instances with ABIs
                if (!string.IsNullOrEmpty(gameLogicAddress))
                {
                    gameLogicContract = web3.Eth.GetContract(GameLogicABI.ABI, gameLogicAddress);
                }

                if (!string.IsNullOrEmpty(governanceTokenAddress))
                {
                    governanceTokenContract = web3.Eth.GetContract(ERC20ABI.ABI, governanceTokenAddress);
                }

                if (!string.IsNullOrEmpty(utilityTokenAddress))
                {
                    utilityTokenContract = web3.Eth.GetContract(ERC20ABI.ABI, utilityTokenAddress);
                }

                if (!string.IsNullOrEmpty(marketplaceAddress))
                {
                    marketplaceContract = web3.Eth.GetContract(MarketplaceABI.ABI, marketplaceAddress);
                }

                if (!string.IsNullOrEmpty(stakingAddress))
                {
                    stakingContract = web3.Eth.GetContract(StakingABI.ABI, stakingAddress);
                }

                Debug.Log("Contracts initialized successfully");
                
                // Load player data
                await LoadPlayerData();
            }
            catch (Exception ex)
            {
                Debug.LogError($"Contract initialization failed: {ex.Message}");
                OnError?.Invoke($"Contract initialization failed: {ex.Message}");
            }
        }

        private IEnumerator InitializeContractsCoroutine()
        {
            var task = InitializeContracts();
            yield return new WaitUntil(() => task.IsCompleted);
        }

        #endregion

        #region Player Operations

        /// <summary>
        /// Register the current player in the game
        /// </summary>
        public async Task<bool> RegisterPlayer()
        {
            if (gameLogicContract == null || string.IsNullOrEmpty(connectedAddress))
            {
                OnError?.Invoke("Not connected to wallet or game contract");
                return false;
            }

            try
            {
                var registerFunction = gameLogicContract.GetFunction("registerPlayer");
                var txHash = await registerFunction.SendTransactionAsync(connectedAddress);
                
                OnTransactionSent?.Invoke(txHash);
                Debug.Log($"Player registration transaction sent: {txHash}");
                
                // Wait for confirmation
                var receipt = await web3.Eth.Transactions.GetTransactionReceipt.SendRequestAsync(txHash);
                while (receipt == null)
                {
                    await Task.Delay(1000);
                    receipt = await web3.Eth.Transactions.GetTransactionReceipt.SendRequestAsync(txHash);
                }
                
                OnTransactionConfirmed?.Invoke(txHash);
                Debug.Log($"Player registered successfully: {txHash}");
                
                // Reload player data
                await LoadPlayerData();
                return true;
            }
            catch (Exception ex)
            {
                Debug.LogError($"Player registration failed: {ex.Message}");
                OnError?.Invoke($"Player registration failed: {ex.Message}");
                return false;
            }
        }

        /// <summary>
        /// Load current player data from the blockchain
        /// </summary>
        public async Task LoadPlayerData()
        {
            if (gameLogicContract == null || string.IsNullOrEmpty(connectedAddress))
            {
                return;
            }

            try
            {
                var getPlayerDataFunction = gameLogicContract.GetFunction("getPlayerData");
                var result = await getPlayerDataFunction.CallAsync<PlayerDataStruct>(connectedAddress);
                
                CurrentPlayerData = new PlayerData
                {
                    Level = (int)result.Level,
                    Experience = (long)result.Experience,
                    PvpWins = (int)result.PvpWins,
                    PvpLosses = (int)result.PvpLosses,
                    LastDailyQuestClaim = (long)result.LastDailyQuestClaim,
                    IsActive = result.IsActive
                };
                
                Debug.Log($"Player data loaded: Level {CurrentPlayerData.Level}, XP {CurrentPlayerData.Experience}");
            }
            catch (Exception ex)
            {
                Debug.LogError($"Failed to load player data: {ex.Message}");
            }
        }

        /// <summary>
        /// Complete a quest
        /// </summary>
        public async Task<bool> CompleteQuest(int questId)
        {
            if (gameLogicContract == null || string.IsNullOrEmpty(connectedAddress))
            {
                OnError?.Invoke("Not connected to wallet or game contract");
                return false;
            }

            try
            {
                var completeQuestFunction = gameLogicContract.GetFunction("completeQuest");
                var txHash = await completeQuestFunction.SendTransactionAsync(connectedAddress, questId);
                
                OnTransactionSent?.Invoke(txHash);
                Debug.Log($"Quest completion transaction sent: {txHash}");
                
                // Wait for confirmation
                await WaitForTransactionConfirmation(txHash);
                
                OnTransactionConfirmed?.Invoke(txHash);
                Debug.Log($"Quest {questId} completed successfully");
                
                // Reload player data
                await LoadPlayerData();
                return true;
            }
            catch (Exception ex)
            {
                Debug.LogError($"Quest completion failed: {ex.Message}");
                OnError?.Invoke($"Quest completion failed: {ex.Message}");
                return false;
            }
        }

        #endregion

        #region Token Operations

        /// <summary>
        /// Get governance token balance
        /// </summary>
        public async Task<decimal> GetGovernanceTokenBalance()
        {
            if (governanceTokenContract == null || string.IsNullOrEmpty(connectedAddress))
            {
                return 0;
            }

            try
            {
                var balanceFunction = governanceTokenContract.GetFunction("balanceOf");
                var balance = await balanceFunction.CallAsync<BigInteger>(connectedAddress);
                return Web3.Convert.FromWei(balance);
            }
            catch (Exception ex)
            {
                Debug.LogError($"Failed to get governance token balance: {ex.Message}");
                return 0;
            }
        }

        /// <summary>
        /// Get utility token balance
        /// </summary>
        public async Task<decimal> GetUtilityTokenBalance()
        {
            if (utilityTokenContract == null || string.IsNullOrEmpty(connectedAddress))
            {
                return 0;
            }

            try
            {
                var balanceFunction = utilityTokenContract.GetFunction("balanceOf");
                var balance = await balanceFunction.CallAsync<BigInteger>(connectedAddress);
                return Web3.Convert.FromWei(balance);
            }
            catch (Exception ex)
            {
                Debug.LogError($"Failed to get utility token balance: {ex.Message}");
                return 0;
            }
        }

        #endregion

        #region Marketplace Operations

        /// <summary>
        /// List an item on the marketplace
        /// </summary>
        public async Task<bool> ListItem(string nftContract, int tokenId, int amount, int listingType, string paymentToken, decimal price, long endTime)
        {
            if (marketplaceContract == null || string.IsNullOrEmpty(connectedAddress))
            {
                OnError?.Invoke("Not connected to wallet or marketplace contract");
                return false;
            }

            try
            {
                var listItemFunction = marketplaceContract.GetFunction("listItem");
                var priceWei = Web3.Convert.ToWei(price);
                
                var txHash = await listItemFunction.SendTransactionAsync(
                    connectedAddress,
                    nftContract,
                    tokenId,
                    amount,
                    listingType,
                    paymentToken,
                    priceWei,
                    endTime
                );
                
                OnTransactionSent?.Invoke(txHash);
                Debug.Log($"Item listing transaction sent: {txHash}");
                
                await WaitForTransactionConfirmation(txHash);
                
                OnTransactionConfirmed?.Invoke(txHash);
                Debug.Log($"Item listed successfully");
                return true;
            }
            catch (Exception ex)
            {
                Debug.LogError($"Item listing failed: {ex.Message}");
                OnError?.Invoke($"Item listing failed: {ex.Message}");
                return false;
            }
        }

        /// <summary>
        /// Buy an item from the marketplace
        /// </summary>
        public async Task<bool> BuyItem(int listingId)
        {
            if (marketplaceContract == null || string.IsNullOrEmpty(connectedAddress))
            {
                OnError?.Invoke("Not connected to wallet or marketplace contract");
                return false;
            }

            try
            {
                var buyItemFunction = marketplaceContract.GetFunction("buyItem");
                var txHash = await buyItemFunction.SendTransactionAsync(connectedAddress, listingId);
                
                OnTransactionSent?.Invoke(txHash);
                Debug.Log($"Item purchase transaction sent: {txHash}");
                
                await WaitForTransactionConfirmation(txHash);
                
                OnTransactionConfirmed?.Invoke(txHash);
                Debug.Log($"Item purchased successfully");
                return true;
            }
            catch (Exception ex)
            {
                Debug.LogError($"Item purchase failed: {ex.Message}");
                OnError?.Invoke($"Item purchase failed: {ex.Message}");
                return false;
            }
        }

        #endregion

        #region Utility Methods

        private async Task WaitForTransactionConfirmation(string txHash)
        {
            var receipt = await web3.Eth.Transactions.GetTransactionReceipt.SendRequestAsync(txHash);
            while (receipt == null)
            {
                await Task.Delay(1000);
                receipt = await web3.Eth.Transactions.GetTransactionReceipt.SendRequestAsync(txHash);
            }
        }

        public bool IsConnected()
        {
            return !string.IsNullOrEmpty(connectedAddress) && web3 != null;
        }

        public string GetConnectedAddress()
        {
            return connectedAddress;
        }

        #endregion

        #region Data Structures

        [Serializable]
        public class PlayerData
        {
            public int Level;
            public long Experience;
            public int PvpWins;
            public int PvpLosses;
            public long LastDailyQuestClaim;
            public bool IsActive;
        }

        [Serializable]
        public struct PlayerDataStruct
        {
            public BigInteger Level;
            public BigInteger Experience;
            public BigInteger PvpWins;
            public BigInteger PvpLosses;
            public BigInteger LastDailyQuestClaim;
            public bool IsActive;
        }

        #endregion
    }

    #region Contract ABIs

    /// <summary>
    /// Contract ABI definitions (simplified for example)
    /// In production, these would be generated from the contract artifacts
    /// </summary>
    public static class GameLogicABI
    {
        public const string ABI = @"[
            {
                ""inputs"": [],
                ""name"": ""registerPlayer"",
                ""outputs"": [],
                ""stateMutability"": ""nonpayable"",
                ""type"": ""function""
            },
            {
                ""inputs"": [{""internalType"": ""address"", ""name"": ""player"", ""type"": ""address""}],
                ""name"": ""getPlayerData"",
                ""outputs"": [{
                    ""components"": [
                        {""internalType"": ""uint256"", ""name"": ""level"", ""type"": ""uint256""},
                        {""internalType"": ""uint256"", ""name"": ""experience"", ""type"": ""uint256""},
                        {""internalType"": ""uint256"", ""name"": ""pvpWins"", ""type"": ""uint256""},
                        {""internalType"": ""uint256"", ""name"": ""pvpLosses"", ""type"": ""uint256""},
                        {""internalType"": ""uint256"", ""name"": ""lastDailyQuestClaim"", ""type"": ""uint256""},
                        {""internalType"": ""bool"", ""name"": ""isActive"", ""type"": ""bool""}
                    ],
                    ""internalType"": ""struct GameLogic.PlayerData"",
                    ""name"": """",
                    ""type"": ""tuple""
                }],
                ""stateMutability"": ""view"",
                ""type"": ""function""
            },
            {
                ""inputs"": [{""internalType"": ""uint256"", ""name"": ""questId"", ""type"": ""uint256""}],
                ""name"": ""completeQuest"",
                ""outputs"": [],
                ""stateMutability"": ""nonpayable"",
                ""type"": ""function""
            }
        ]";
    }

    public static class ERC20ABI
    {
        public const string ABI = @"[
            {
                ""inputs"": [{""internalType"": ""address"", ""name"": ""owner"", ""type"": ""address""}],
                ""name"": ""balanceOf"",
                ""outputs"": [{""internalType"": ""uint256"", ""name"": """", ""type"": ""uint256""}],
                ""stateMutability"": ""view"",
                ""type"": ""function""
            },
            {
                ""inputs"": [
                    {""internalType"": ""address"", ""name"": ""to"", ""type"": ""address""},
                    {""internalType"": ""uint256"", ""name"": ""amount"", ""type"": ""uint256""}
                ],
                ""name"": ""transfer"",
                ""outputs"": [{""internalType"": ""bool"", ""name"": """", ""type"": ""bool""}],
                ""stateMutability"": ""nonpayable"",
                ""type"": ""function""
            }
        ]";
    }

    public static class MarketplaceABI
    {
        public const string ABI = @"[
            {
                ""inputs"": [
                    {""internalType"": ""address"", ""name"": ""nftContract"", ""type"": ""address""},
                    {""internalType"": ""uint256"", ""name"": ""tokenId"", ""type"": ""uint256""},
                    {""internalType"": ""uint256"", ""name"": ""amount"", ""type"": ""uint256""},
                    {""internalType"": ""uint8"", ""name"": ""listingType"", ""type"": ""uint8""},
                    {""internalType"": ""address"", ""name"": ""paymentToken"", ""type"": ""address""},
                    {""internalType"": ""uint256"", ""name"": ""price"", ""type"": ""uint256""},
                    {""internalType"": ""uint256"", ""name"": ""endTime"", ""type"": ""uint256""}
                ],
                ""name"": ""listItem"",
                ""outputs"": [],
                ""stateMutability"": ""nonpayable"",
                ""type"": ""function""
            },
            {
                ""inputs"": [{""internalType"": ""uint256"", ""name"": ""listingId"", ""type"": ""uint256""}],
                ""name"": ""buyItem"",
                ""outputs"": [],
                ""stateMutability"": ""payable"",
                ""type"": ""function""
            }
        ]";
    }

    public static class StakingABI
    {
        public const string ABI = @"[
            {
                ""inputs"": [
                    {""internalType"": ""uint256"", ""name"": ""poolId"", ""type"": ""uint256""},
                    {""internalType"": ""uint256"", ""name"": ""amount"", ""type"": ""uint256""}
                ],
                ""name"": ""stakeTokens"",
                ""outputs"": [],
                ""stateMutability"": ""nonpayable"",
                ""type"": ""function""
            },
            {
                ""inputs"": [{""internalType"": ""uint256"", ""name"": ""poolId"", ""type"": ""uint256""}],
                ""name"": ""claimRewards"",
                ""outputs"": [],
                ""stateMutability"": ""nonpayable"",
                ""type"": ""function""
            }
        ]";
    }

    #endregion
}

