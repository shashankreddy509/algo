from flask import Flask, render_template, request, redirect, url_for, session, flash, jsonify
import os
from dotenv import load_dotenv
import requests
from fyers_apiv3 import fyersModel
import hashlib
import secrets

# Load environment variables
load_dotenv()

app = Flask(__name__)
app.secret_key = os.getenv('FLASK_SECRET_KEY', 'your-secret-key-here')

# Fyers API Configuration
FYERS_CLIENT_ID = os.getenv('FYERS_CLIENT_ID')
FYERS_SECRET_KEY = os.getenv('FYERS_SECRET_KEY')
FYERS_REDIRECT_URI = os.getenv('FYERS_REDIRECT_URI')

class FyersAuth:
    def __init__(self):
        self.client_id = FYERS_CLIENT_ID
        self.secret_key = FYERS_SECRET_KEY
        self.redirect_uri = FYERS_REDIRECT_URI
        
    def generate_auth_url(self):
        """Generate Fyers authentication URL"""
        # Create session model
        session_model = fyersModel.SessionModel(
            client_id=self.client_id,
            secret_key=self.secret_key,
            redirect_uri=self.redirect_uri,
            response_type="code",
            grant_type="authorization_code"
        )
        
        # Generate auth URL
        auth_url = session_model.generate_authcode()
        print(auth_url)
        return auth_url
    
    def get_access_token(self, auth_code):
        """Exchange authorization code for access token"""
        try:
            session_model = fyersModel.SessionModel(
                client_id=self.client_id,
                secret_key=self.secret_key,
                redirect_uri=self.redirect_uri,
                response_type="code",
                grant_type="authorization_code"
            )
            
            session_model.set_token(auth_code)
            response = session_model.generate_token()
            
            if response['code'] == 200:
                return response['access_token']
            else:
                return None
        except Exception as e:
            print(f"Error getting access token: {e}")
            return None

# Initialize Fyers Auth
fyers_auth = FyersAuth()

@app.route('/')
def index():
    """Home page"""
    if 'access_token' in session:
        return redirect(url_for('dashboard'))
    return render_template('index.html')

@app.route('/login')
def login():
    """Initiate Fyers OAuth login"""
    try:
        auth_url = fyers_auth.generate_auth_url()
        return redirect(auth_url)
    except Exception as e:
        flash(f'Error initiating login: {str(e)}', 'error')
        return redirect(url_for('index'))

@app.route('/callback')
def callback():
    """Handle OAuth callback from Fyers"""
    auth_code = request.args.get('auth_code')
    
    if auth_code:
        access_token = fyers_auth.get_access_token(auth_code)
        if access_token:
            session['access_token'] = access_token
            flash('Successfully logged in!', 'success')
            return redirect(url_for('dashboard'))
        else:
            flash('Failed to get access token', 'error')
    else:
        flash('Authorization failed', 'error')
    
    return redirect(url_for('index'))

@app.route('/dashboard')
def dashboard():
    """Dashboard page - requires authentication"""
    if 'access_token' not in session:
        flash('Please login first', 'warning')
        return redirect(url_for('index'))
    
    try:
        print(f"Access token: {session['access_token']}")  # Debug log
        
        # Initialize Fyers model with access token
        fyers = fyersModel.FyersModel(
            client_id=FYERS_CLIENT_ID,
            token=session['access_token']
        )
        
        # Get user profile
        print("Fetching profile...")  # Debug log
        profile_response = fyers.get_profile()
        print(f"Profile response: {profile_response}")  # Debug log
        profile_data = profile_response if profile_response and profile_response.get('code') == 200 else None
        
        # Get funds
        print("Fetching funds...")  # Debug log
        funds_response = fyers.funds()
        print(f"Funds response: {funds_response}")  # Debug log
        funds_data = funds_response if funds_response and funds_response.get('code') == 200 else None
        
        print("Rendering dashboard template...")  # Debug log
        return render_template('dashboard.html', 
                             profile=profile_data, 
                             funds=funds_data)
    except Exception as e:
        print(f"Dashboard error: {str(e)}")  # Debug log
        flash(f'Error loading dashboard: {str(e)}', 'error')
        return redirect(url_for('index'))

@app.route('/logout')
def logout():
    """Logout user"""
    session.clear()
    flash('Successfully logged out!', 'success')
    return redirect(url_for('index'))

@app.route('/scanner')
def scanner():
    """Scanner page - requires authentication"""
    if 'access_token' not in session:
        flash('Please login first', 'warning')
        return redirect(url_for('index'))
    
    return render_template('scanner.html')

@app.route('/api/profile')
def api_profile():
    """API endpoint to get user profile"""
    if 'access_token' not in session:
        return jsonify({'error': 'Not authenticated'}), 401
    
    try:
        fyers = fyersModel.FyersModel(
            client_id=FYERS_CLIENT_ID,
            token=session['access_token']
        )
        
        response = fyers.get_profile()
        return jsonify(response)
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/funds')
def api_funds():
    """API endpoint to get funds information"""
    if 'access_token' not in session:
        return jsonify({'error': 'Not authenticated'}), 401
    
    try:
        fyers = fyersModel.FyersModel(
            client_id=FYERS_CLIENT_ID,
            token=session['access_token']
        )
        
        response = fyers.funds()
        return jsonify(response)
    except Exception as e:
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=5000)