"""
Firebase Firestore configuration and utilities for the trading application.
"""
import os
import json
from datetime import datetime
import firebase_admin
from firebase_admin import credentials, firestore
from flask import current_app

class FirebaseConfig:
    """Firebase configuration and Firestore operations."""
    
    def __init__(self):
        self.db = None
        self._initialize_firebase()
    
    def _initialize_firebase(self):
        """Initialize Firebase Admin SDK with service account credentials."""
        try:
            # Check if Firebase is already initialized
            if not firebase_admin._apps:
                # Create credentials from environment variables
                cred_dict = {
                    "type": "service_account",
                    "project_id": os.getenv('FIREBASE_PROJECT_ID'),
                    "private_key_id": os.getenv('FIREBASE_PRIVATE_KEY_ID'),
                    "private_key": os.getenv('FIREBASE_PRIVATE_KEY', '').replace('\\n', '\n'),
                    "client_email": os.getenv('FIREBASE_CLIENT_EMAIL'),
                    "client_id": os.getenv('FIREBASE_CLIENT_ID'),
                    "auth_uri": os.getenv('FIREBASE_AUTH_URI', 'https://accounts.google.com/o/oauth2/auth'),
                    "token_uri": os.getenv('FIREBASE_TOKEN_URI', 'https://oauth2.googleapis.com/token'),
                    "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
                    "client_x509_cert_url": f"https://www.googleapis.com/robot/v1/metadata/x509/{os.getenv('FIREBASE_CLIENT_EMAIL', '').replace('@', '%40')}"
                }
                
                # Validate required fields
                required_fields = ['project_id', 'private_key', 'client_email']
                missing_fields = [field for field in required_fields if not cred_dict.get(field)]
                
                if missing_fields:
                    raise ValueError(f"Missing Firebase configuration: {', '.join(missing_fields)}")
                
                # Initialize Firebase
                cred = credentials.Certificate(cred_dict)
                firebase_admin.initialize_app(cred)
            
            # Get Firestore client
            self.db = firestore.client()
            print("Firebase initialized successfully")
            
        except Exception as e:
            print(f"Firebase initialization error: {str(e)}")
            self.db = None
    
    def save_scanner_results(self, results, scan_type="regular", user_id="anonymous"):
        """
        Save scanner results to Firestore.
        
        Args:
            results (list): List of stock results from scanner
            scan_type (str): Type of scan performed
            user_id (str): User identifier
            
        Returns:
            dict: Success/error response
        """
        if not self.db:
            return {"success": False, "error": "Firebase not initialized"}
        
        try:
            # Prepare document data
            doc_data = {
                "timestamp": datetime.utcnow(),
                "scan_type": scan_type,
                "user_id": user_id,
                "results_count": len(results),
                "results": results,
                "metadata": {
                    "app_version": "1.0",
                    "scan_date": datetime.utcnow().strftime("%Y-%m-%d"),
                    "scan_time": datetime.utcnow().strftime("%H:%M:%S")
                }
            }
            
            # Save to Firestore
            doc_ref = self.db.collection('scanner_results').add(doc_data)
            doc_id = doc_ref[1].id
            
            return {
                "success": True,
                "document_id": doc_id,
                "message": f"Saved {len(results)} results to Firestore"
            }
            
        except Exception as e:
            return {
                "success": False,
                "error": f"Failed to save to Firestore: {str(e)}"
            }
    
    def get_scanner_history(self, user_id="anonymous", limit=10):
        """
        Retrieve scanner history from Firestore.
        
        Args:
            user_id (str): User identifier
            limit (int): Number of records to retrieve
            
        Returns:
            list: List of scanner results
        """
        if not self.db:
            return []
        
        try:
            docs = (self.db.collection('scanner_results')
                   .where('user_id', '==', user_id)
                   .order_by('timestamp', direction=firestore.Query.DESCENDING)
                   .limit(limit)
                   .stream())
            
            history = []
            for doc in docs:
                data = doc.to_dict()
                data['id'] = doc.id
                history.append(data)
            
            return history
            
        except Exception as e:
            print(f"Error retrieving scanner history: {str(e)}")
            return []

# Global Firebase instance
firebase_config = FirebaseConfig()