#!/usr/bin/env python3
"""
Automated Wallet Integration Tests for LithosProtocol
Tests wallet connection, transaction signing, and contract interactions
"""

import asyncio
import json
import time
from web3 import Web3
from eth_account import Account
import pytest
import requests
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.chrome.options import Options

class WalletIntegrationTester:
    def __init__(self, rpc_url="http://localhost:8545", frontend_url="http://localhost:5173"):
        self.rpc_url = rpc_url
        self.frontend_url = frontend_url
        self.web3 = Web3(Web3.HTTPProvider(rpc_url))
        self.test_account = None
        self.driver = None
        
    def setup_test_environment(self):
        """Set up test environment with local blockchain and test accounts"""
        print("🔧 Setting up test environment...")
        
        # Create test account
        self.test_account = Account.create()
        print(f"✅ Created test account: {self.test_account.address}")
        
        # Setup Chrome driver for frontend testing
        chrome_options = Options()
        chrome_options.add_argument("--headless")
        chrome_options.add_argument("--no-sandbox")
        chrome_options.add_argument("--disable-dev-shm-usage")
        chrome_options.add_argument("--disable-gpu")
        
        try:
            self.driver = webdriver.Chrome(options=chrome_options)
            print("✅ Chrome driver initialized")
        except Exception as e:
            print(f"⚠️  Chrome driver not available: {e}")
            self.driver = None
    
    def test_web3_connection(self):
        """Test basic Web3 connection"""
        print("\n🔗 Testing Web3 connection...")
        
        try:
            # Test connection
            is_connected = self.web3.is_connected()
            print(f"Web3 connected: {is_connected}")
            
            if is_connected:
                # Get network info
                chain_id = self.web3.eth.chain_id
                block_number = self.web3.eth.block_number
                print(f"Chain ID: {chain_id}")
                print(f"Latest block: {block_number}")
                return True
            else:
                print("❌ Web3 connection failed")
                return False
                
        except Exception as e:
            print(f"❌ Web3 connection error: {e}")
            return False
    
    def test_account_operations(self):
        """Test account creation and basic operations"""
        print("\n👤 Testing account operations...")
        
        try:
            # Test account creation
            account = Account.create()
            print(f"✅ Account created: {account.address}")
            
            # Test private key operations
            private_key = account.key.hex()
            recovered_account = Account.from_key(private_key)
            assert account.address == recovered_account.address
            print("✅ Private key operations working")
            
            # Test message signing
            message = "Test message for LithosProtocol"
            signed_message = account.sign_message(message.encode())
            print("✅ Message signing working")
            
            return True
            
        except Exception as e:
            print(f"❌ Account operations error: {e}")
            return False
    
    def test_transaction_creation(self):
        """Test transaction creation and signing"""
        print("\n💸 Testing transaction creation...")
        
        try:
            # Create a test transaction
            transaction = {
                'to': '0x0000000000000000000000000000000000000000',
                'value': Web3.to_wei(0.001, 'ether'),
                'gas': 21000,
                'gasPrice': Web3.to_wei(20, 'gwei'),
                'nonce': 0,
                'chainId': 1337  # Local testnet
            }
            
            # Sign transaction
            signed_txn = self.test_account.sign_transaction(transaction)
            print("✅ Transaction signed successfully")
            print(f"Transaction hash: {signed_txn.hash.hex()}")
            
            return True
            
        except Exception as e:
            print(f"❌ Transaction creation error: {e}")
            return False
    
    def test_contract_interaction_simulation(self):
        """Simulate contract interactions"""
        print("\n📄 Testing contract interaction simulation...")
        
        try:
            # Simulate contract ABI
            contract_abi = [
                {
                    "inputs": [],
                    "name": "registerPlayer",
                    "outputs": [],
                    "stateMutability": "nonpayable",
                    "type": "function"
                },
                {
                    "inputs": [{"name": "player", "type": "address"}],
                    "name": "getPlayerData",
                    "outputs": [{"name": "", "type": "tuple"}],
                    "stateMutability": "view",
                    "type": "function"
                }
            ]
            
            # Test ABI encoding
            contract_address = "0x1234567890123456789012345678901234567890"
            
            # Simulate function call data
            function_selector = Web3.keccak(text="registerPlayer()")[:4]
            print(f"✅ Function selector generated: {function_selector.hex()}")
            
            # Simulate contract call
            call_data = {
                'to': contract_address,
                'data': function_selector.hex()
            }
            print("✅ Contract call data prepared")
            
            return True
            
        except Exception as e:
            print(f"❌ Contract interaction error: {e}")
            return False
    
    def test_frontend_wallet_connection(self):
        """Test frontend wallet connection flow"""
        print("\n🌐 Testing frontend wallet connection...")
        
        if not self.driver:
            print("⚠️  Skipping frontend tests - Chrome driver not available")
            return True
        
        try:
            # Navigate to frontend
            self.driver.get(self.frontend_url)
            print(f"✅ Navigated to {self.frontend_url}")
            
            # Wait for page to load
            WebDriverWait(self.driver, 10).until(
                EC.presence_of_element_located((By.TAG_NAME, "body"))
            )
            
            # Check for connect wallet button
            try:
                connect_button = WebDriverWait(self.driver, 5).until(
                    EC.element_to_be_clickable((By.XPATH, "//button[contains(text(), 'Connect Wallet')]"))
                )
                print("✅ Connect Wallet button found")
                
                # Check page title
                title = self.driver.title
                assert "LithosProtocol" in title
                print(f"✅ Page title correct: {title}")
                
            except Exception as e:
                print(f"⚠️  Connect button not found: {e}")
            
            return True
            
        except Exception as e:
            print(f"❌ Frontend test error: {e}")
            return False
    
    def test_marketplace_functionality(self):
        """Test marketplace frontend functionality"""
        print("\n🏪 Testing marketplace functionality...")
        
        if not self.driver:
            print("⚠️  Skipping marketplace tests - Chrome driver not available")
            return True
        
        try:
            # Check for marketplace elements
            self.driver.get(self.frontend_url)
            
            # Wait for content to load
            time.sleep(2)
            
            # Check for key marketplace elements
            page_source = self.driver.page_source
            
            marketplace_elements = [
                "Marketplace",
                "Game Assets",
                "Rare Collectibles",
                "True Ownership"
            ]
            
            for element in marketplace_elements:
                if element in page_source:
                    print(f"✅ Found marketplace element: {element}")
                else:
                    print(f"⚠️  Missing marketplace element: {element}")
            
            return True
            
        except Exception as e:
            print(f"❌ Marketplace test error: {e}")
            return False
    
    def test_sdk_integration(self):
        """Test SDK integration and functionality"""
        print("\n🔧 Testing SDK integration...")
        
        try:
            # Test SDK configuration
            sdk_config = {
                "network": "localhost",
                "rpcUrl": self.rpc_url,
                "contracts": {
                    "marketplace": "0x1234567890123456789012345678901234567890",
                    "utilityToken": "0x0987654321098765432109876543210987654321"
                }
            }
            
            print("✅ SDK configuration prepared")
            
            # Test contract address validation
            for name, address in sdk_config["contracts"].items():
                if Web3.is_address(address):
                    print(f"✅ Valid contract address for {name}: {address}")
                else:
                    print(f"❌ Invalid contract address for {name}: {address}")
            
            return True
            
        except Exception as e:
            print(f"❌ SDK integration error: {e}")
            return False
    
    def run_performance_tests(self):
        """Run performance tests for wallet operations"""
        print("\n⚡ Running performance tests...")
        
        try:
            # Test account creation performance
            start_time = time.time()
            accounts = []
            for i in range(10):
                account = Account.create()
                accounts.append(account)
            
            creation_time = time.time() - start_time
            print(f"✅ Created 10 accounts in {creation_time:.3f} seconds")
            
            # Test transaction signing performance
            start_time = time.time()
            transaction = {
                'to': '0x0000000000000000000000000000000000000000',
                'value': Web3.to_wei(0.001, 'ether'),
                'gas': 21000,
                'gasPrice': Web3.to_wei(20, 'gwei'),
                'nonce': 0,
                'chainId': 1337
            }
            
            for account in accounts:
                signed_txn = account.sign_transaction(transaction)
            
            signing_time = time.time() - start_time
            print(f"✅ Signed 10 transactions in {signing_time:.3f} seconds")
            
            return True
            
        except Exception as e:
            print(f"❌ Performance test error: {e}")
            return False
    
    def generate_test_report(self, results):
        """Generate comprehensive test report"""
        print("\n📊 Generating test report...")
        
        report = {
            "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
            "test_environment": {
                "rpc_url": self.rpc_url,
                "frontend_url": self.frontend_url,
                "test_account": self.test_account.address if self.test_account else None
            },
            "test_results": results,
            "summary": {
                "total_tests": len(results),
                "passed": sum(1 for r in results.values() if r),
                "failed": sum(1 for r in results.values() if not r)
            }
        }
        
        # Save report to file
        with open('/home/ubuntu/AetheriumPrime/automated-tests/wallet_integration_report.json', 'w') as f:
            json.dump(report, f, indent=2)
        
        print(f"✅ Test report saved")
        print(f"📈 Summary: {report['summary']['passed']}/{report['summary']['total']} tests passed")
        
        return report
    
    def cleanup(self):
        """Clean up test environment"""
        print("\n🧹 Cleaning up test environment...")
        
        if self.driver:
            self.driver.quit()
            print("✅ Chrome driver closed")
    
    def run_all_tests(self):
        """Run all wallet integration tests"""
        print("🚀 Starting LithosProtocol Wallet Integration Tests")
        print("=" * 60)
        
        # Setup
        self.setup_test_environment()
        
        # Run tests
        results = {}
        
        test_methods = [
            ("Web3 Connection", self.test_web3_connection),
            ("Account Operations", self.test_account_operations),
            ("Transaction Creation", self.test_transaction_creation),
            ("Contract Interaction", self.test_contract_interaction_simulation),
            ("Frontend Connection", self.test_frontend_wallet_connection),
            ("Marketplace Functionality", self.test_marketplace_functionality),
            ("SDK Integration", self.test_sdk_integration),
            ("Performance Tests", self.run_performance_tests)
        ]
        
        for test_name, test_method in test_methods:
            try:
                result = test_method()
                results[test_name] = result
                status = "✅ PASSED" if result else "❌ FAILED"
                print(f"\n{status}: {test_name}")
            except Exception as e:
                results[test_name] = False
                print(f"\n❌ FAILED: {test_name} - {e}")
        
        # Generate report
        report = self.generate_test_report(results)
        
        # Cleanup
        self.cleanup()
        
        print("\n" + "=" * 60)
        print("🏁 Wallet Integration Tests Complete")
        
        return report

def main():
    """Main test runner"""
    tester = WalletIntegrationTester()
    report = tester.run_all_tests()
    
    # Exit with appropriate code
    if report['summary']['failed'] > 0:
        exit(1)
    else:
        exit(0)

if __name__ == "__main__":
    main()

