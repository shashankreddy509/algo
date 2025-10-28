#!/usr/bin/env python3
"""
Debug script to test scanner functionality and Firebase initialization.
Run this on EC2 to diagnose issues with the Save to Firestore button.
"""

import os
import sys
import json
from datetime import datetime

# Add the current directory to Python path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

def test_environment_variables():
    """Test if all required environment variables are set."""
    print("=== Testing Environment Variables ===")
    
    required_vars = [
        'FIREBASE_PROJECT_ID',
        'FIREBASE_PRIVATE_KEY_ID', 
        'FIREBASE_PRIVATE_KEY',
        'FIREBASE_CLIENT_EMAIL',
        'FIREBASE_CLIENT_ID'
    ]
    
    missing_vars = []
    for var in required_vars:
        value = os.getenv(var)
        if not value:
            missing_vars.append(var)
            print(f"❌ {var}: NOT SET")
        else:
            # Show partial value for security
            if 'KEY' in var and len(value) > 50:
                print(f"✅ {var}: {value[:20]}...{value[-10:]} (truncated)")
            else:
                print(f"✅ {var}: {value}")
    
    if missing_vars:
        print(f"\n❌ Missing environment variables: {', '.join(missing_vars)}")
        return False
    else:
        print("\n✅ All environment variables are set")
        return True

def test_firebase_initialization():
    """Test Firebase initialization."""
    print("\n=== Testing Firebase Initialization ===")
    
    try:
        from firebase_config import firebase_config
        
        if firebase_config.db is None:
            print("❌ Firebase database client is None")
            return False
        else:
            print("✅ Firebase initialized successfully")
            print(f"✅ Database client: {type(firebase_config.db)}")
            return True
            
    except Exception as e:
        print(f"❌ Firebase initialization failed: {str(e)}")
        return False

def test_scanner_api():
    """Test the scanner API functionality."""
    print("\n=== Testing Scanner API ===")
    
    try:
        # Import app components
        from app import app
        
        with app.test_client() as client:
            # Test scanner endpoint with sample data
            test_data = {
                'oneHourSetup': True,
                'stockSelection': 'nifty50'
            }
            
            response = client.post('/api/scanner', 
                                 data=json.dumps(test_data),
                                 content_type='application/json')
            
            print(f"Status Code: {response.status_code}")
            
            if response.status_code == 200:
                try:
                    data = response.get_json()
                    if data and 'results' in data:
                        results_count = len(data.get('results', []))
                        print(f"✅ Scanner API working - {results_count} results returned")
                        
                        if results_count > 0:
                            print("✅ Results found - Save to Firestore button should be visible")
                            return True
                        else:
                            print("⚠️  No results returned - Save to Firestore button will be hidden")
                            return False
                    else:
                        print("❌ Invalid response format")
                        print(f"Response: {data}")
                        return False
                except Exception as json_error:
                    print(f"❌ JSON parsing error: {str(json_error)}")
                    print(f"Raw response: {response.get_data(as_text=True)[:500]}...")
                    return False
            else:
                print(f"❌ Scanner API failed with status {response.status_code}")
                print(f"Response: {response.get_data(as_text=True)[:500]}...")
                return False
                
    except Exception as e:
        print(f"❌ Scanner API test failed: {str(e)}")
        return False

def test_save_to_firestore():
    """Test saving results to Firestore."""
    print("\n=== Testing Save to Firestore ===")
    
    try:
        from firebase_config import firebase_config
        
        # Test data
        test_results = [
            {
                'symbol': 'RELIANCE',
                'price': 2500.0,
                'change': 1.5,
                'volume': 1000000
            }
        ]
        
        response = firebase_config.save_scanner_results(
            results=test_results,
            scan_type="test",
            user_id="debug_test"
        )
        
        if response.get('success'):
            print("✅ Save to Firestore working")
            print(f"Document ID: {response.get('document_id')}")
            return True
        else:
            print(f"❌ Save to Firestore failed: {response.get('error')}")
            return False
            
    except Exception as e:
        print(f"❌ Save to Firestore test failed: {str(e)}")
        return False

def main():
    """Run all tests."""
    print("🔍 Scanner Debug Tool")
    print("=" * 50)
    
    tests = [
        ("Environment Variables", test_environment_variables),
        ("Firebase Initialization", test_firebase_initialization), 
        ("Scanner API", test_scanner_api),
        ("Save to Firestore", test_save_to_firestore)
    ]
    
    results = {}
    
    for test_name, test_func in tests:
        try:
            results[test_name] = test_func()
        except Exception as e:
            print(f"❌ {test_name} test crashed: {str(e)}")
            results[test_name] = False
    
    print("\n" + "=" * 50)
    print("📊 SUMMARY")
    print("=" * 50)
    
    all_passed = True
    for test_name, passed in results.items():
        status = "✅ PASS" if passed else "❌ FAIL"
        print(f"{test_name}: {status}")
        if not passed:
            all_passed = False
    
    if all_passed:
        print("\n🎉 All tests passed! The Save to Firestore button should work.")
        print("\nIf the button is still not visible:")
        print("1. Check browser console for JavaScript errors")
        print("2. Ensure you run a scanner search to get results")
        print("3. Verify the service was restarted after deployment")
    else:
        print("\n⚠️  Some tests failed. Fix the issues above.")
        print("\nCommon solutions:")
        print("1. Check .env file exists and has correct Firebase credentials")
        print("2. Restart the service: sudo systemctl restart py-trade")
        print("3. Check service logs: sudo journalctl -u py-trade -f")

if __name__ == "__main__":
    main()