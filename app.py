from flask import Flask, render_template, request, redirect, url_for, session, flash, jsonify, make_response
import os
from dotenv import load_dotenv
import requests
from fyers_apiv3 import fyersModel
import hashlib
import secrets
import csv
import io
from datetime import datetime
from paper_trading_db import paper_trading_db

# Load environment variables
load_dotenv()

app = Flask(__name__)
app.secret_key = os.getenv('FLASK_SECRET_KEY', 'your-secret-key-here')

# Fyers API Configuration
FYERS_CLIENT_ID = os.getenv('FYERS_CLIENT_ID')
FYERS_SECRET_KEY = os.getenv('FYERS_SECRET_KEY')
FYERS_REDIRECT_URI = os.getenv('FYERS_REDIRECT_URI')

# Store scan results for CSV export (keyed by session ID)
scan_results_cache = {}

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

@app.route('/api/scanner', methods=['POST'])
def api_scanner():
    if 'access_token' not in session:
        return jsonify({'error': 'Not authenticated'}), 401
    
    try:
        data = request.get_json()
        
        # Initialize Fyers client
        fyers = fyersModel.FyersModel(
            client_id=FYERS_CLIENT_ID,
            token=session['access_token']
        )
        
        # Get market data for scanning
        results = []
        
        if data.get('oneHourSetup'):
            # One Hour Setup Strategy Logic
            results = scan_one_hour_setup(fyers, data)
        else:
            # Regular scanning logic
            results = scan_regular(fyers, data)
        
        # Store results in cache for CSV export
        session_id = session.get('session_id', session.get('access_token', 'default'))
        scan_results_cache[session_id] = {
            'results': results,
            'scan_type': 'oneHourSetup' if data.get('oneHourSetup') else 'regular',
            'timestamp': datetime.now()
        }
        
        return jsonify({'results': results, 'count': len(results)})
    
    except Exception as e:
        print(f"Scanner error: {str(e)}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/scanner/export-csv', methods=['POST'])
def api_scanner_export_csv():
    """Export scanner results to CSV file using cached results"""
    if 'access_token' not in session:
        return jsonify({'error': 'Not authenticated'}), 401
    
    try:
        # Get cached results instead of re-scanning
        session_id = session.get('session_id', session.get('access_token', 'default'))
        cached_data = scan_results_cache.get(session_id)
        
        if not cached_data:
            return jsonify({'error': 'No scan results found. Please run a scan first.'}), 400
        
        results = cached_data['results']
        scan_type = cached_data['scan_type']
        
        # Create CSV content
        output = io.StringIO()
        writer = csv.writer(output)
        
        # Determine headers based on scan type
        if scan_type == 'oneHourSetup':
            headers = ['Symbol', 'Price', 'Change %', 'Volume', 'Previous Close Type', 'Signal', 'Flat Open', 'Pattern']
            writer.writerow(headers)
            
            for result in results:
                writer.writerow([
                    result.get('symbol', ''),
                    result.get('price', ''),
                    result.get('change', ''),
                    result.get('volume', ''),
                    result.get('prevClose', ''),
                    result.get('signal', ''),
                    result.get('flatOpen', ''),
                    result.get('pattern', '')
                ])
        else:
            # Regular scan headers
            headers = ['Symbol', 'Price', 'Change %', 'Volume', 'Market Cap', 'RSI', 'Pattern']
            writer.writerow(headers)
            
            for result in results:
                writer.writerow([
                    result.get('symbol', ''),
                    result.get('price', ''),
                    result.get('change', ''),
                    result.get('volume', ''),
                    result.get('marketCap', ''),
                    result.get('rsi', ''),
                    result.get('pattern', '')
                ])
        
        # Create response with CSV file
        csv_content = output.getvalue()
        output.close()
        
        # Generate filename with timestamp
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        scan_type_name = "OneHourSetup" if scan_type == 'oneHourSetup' else "RegularScan"
        filename = f"scanner_results_{scan_type_name}_{timestamp}.csv"
        
        # Create response
        response = make_response(csv_content)
        response.headers['Content-Type'] = 'text/csv'
        response.headers['Content-Disposition'] = f'attachment; filename={filename}'
        
        return response
    
    except Exception as e:
        print(f"CSV export error: {str(e)}")
        return jsonify({'error': str(e)}), 500

def scan_one_hour_setup(fyers, filters):
    """
    Scan for One Hour Setup strategy candidates
    """
    try:
        # Get stock selection from filters
        stock_selection = filters.get('stockSelection', 'all')
        selected_stocks = filters.get('selectedStocks', [])
        
        # Determine which stocks to scan based on selection
        if stock_selection == 'nifty50':
            # Get only Nifty 50 stocks
            nifty_50 = [
                "NSE:ADANIENT-EQ","NSE:ADANIPORTS-EQ","NSE:APOLLOHOSP-EQ","NSE:ASIANPAINT-EQ","NSE:AXISBANK-EQ","NSE:BAJAJ-AUTO-EQ","NSE:BAJFINANCE-EQ","NSE:BAJAJFINSV-EQ","NSE:BEL-EQ","NSE:BPCL-EQ","NSE:BHARTIARTL-EQ","NSE:BRITANNIA-EQ","NSE:CIPLA-EQ","NSE:COALINDIA-EQ","NSE:DRREDDY-EQ","NSE:EICHERMOT-EQ","NSE:GRASIM-EQ","NSE:HCLTECH-EQ","NSE:HDFCBANK-EQ","NSE:HDFCLIFE-EQ","NSE:HEROMOTOCO-EQ","NSE:HINDALCO-EQ","NSE:HINDUNILVR-EQ","NSE:ICICIBANK-EQ","NSE:ITC-EQ","NSE:INDUSINDBK-EQ","NSE:INFY-EQ","NSE:JSWSTEEL-EQ","NSE:KOTAKBANK-EQ","NSE:LT-EQ","NSE:M&M-EQ","NSE:MARUTI-EQ","NSE:NTPC-EQ","NSE:NESTLEIND-EQ","NSE:ONGC-EQ","NSE:POWERGRID-EQ","NSE:RELIANCE-EQ","NSE:SBILIFE-EQ","NSE:SHRIRAMFIN-EQ","NSE:SBIN-EQ","NSE:SUNPHARMA-EQ","NSE:TCS-EQ","NSE:TATACONSUM-EQ","NSE:TATASTEEL-EQ","NSE:TECHM-EQ","NSE:TITAN-EQ","NSE:TRENT-EQ","NSE:ULTRACEMCO-EQ","NSE:WIPRO-EQ"
            ]
            symbols_to_scan = nifty_50
        elif stock_selection == 'fno':
            # Get only F&O stocks
            symbols_to_scan = get_nifty_fno_symbols(fyers)
        elif stock_selection == 'custom' and selected_stocks:
            # Use custom selected stocks - add NSE: prefix if not present
            symbols_to_scan = []
            for stock in selected_stocks:
                if ':' not in stock:
                    symbols_to_scan.append(f"NSE:{stock}-EQ")
                else:
                    symbols_to_scan.append(stock)
        else:
            # Default: Get all Nifty 50 and F&O stocks
            symbols_to_scan = get_nifty_fno_symbols(fyers)
        
        results = []
        
        for symbol in symbols_to_scan:  # Scan selected symbols
            try:
                # Get historical data for previous day analysis
                hist_data = get_historical_data(fyers, symbol)
                current_price = get_current_price(fyers, symbol)
                
                if hist_data and current_price:
                    # Add symbol info to hist_data for debugging
                    hist_data['symbol'] = symbol

                    analysis = analyze_one_hour_setup(hist_data, current_price, filters)
                    if analysis['eligible']:
                        results.append({
                            'symbol': symbol.split(':')[1].replace('-EQ', ''),
                            'price': current_price['price'],
                            'change': current_price['change_percent'],
                            'volume': current_price['volume'],
                            'prevClose': analysis['prev_close_type'],
                            'signal': analysis['signal'],
                            'flatOpen': analysis['flat_open'],
                            'pattern': analysis['pattern']
                        })
                else:
                    print(f"Missing data for {symbol}: hist_data={bool(hist_data)}, current_price={bool(current_price)}")
            except Exception as e:
                print(f"Error processing {symbol}: {str(e)}")
                continue
        
        return results
    
    except Exception as e:
        print(f"One Hour Setup scan error: {str(e)}")
        return []

def get_dynamic_symbols(fyers, segment='NSE'):
    """
    Get dynamic symbol list from Fyers API
    Since market segment filtering was removed, this now returns NSE stocks by default
    """
    try:
        # Return Nifty 50 symbols as they are most liquid
        nifty_50_symbols = [
            "NSE:RELIANCE-EQ", "NSE:TCS-EQ", "NSE:INFY-EQ", "NSE:HDFCBANK-EQ",
            "NSE:ICICIBANK-EQ", "NSE:KOTAKBANK-EQ", "NSE:SBIN-EQ", "NSE:BHARTIARTL-EQ",
            "NSE:ITC-EQ", "NSE:LT-EQ", "NSE:HCLTECH-EQ", "NSE:AXISBANK-EQ",
            "NSE:MARUTI-EQ", "NSE:ASIANPAINT-EQ", "NSE:NESTLEIND-EQ", "NSE:ULTRACEMCO-EQ",
            "NSE:WIPRO-EQ", "NSE:TECHM-EQ", "NSE:POWERGRID-EQ", "NSE:NTPC-EQ",
            "NSE:BAJFINANCE-EQ", "NSE:BAJAJFINSV-EQ", "NSE:HINDUNILVR-EQ", "NSE:TITAN-EQ",
            "NSE:ONGC-EQ", "NSE:SUNPHARMA-EQ", "NSE:DRREDDY-EQ", "NSE:CIPLA-EQ",
            "NSE:COALINDIA-EQ", "NSE:JSWSTEEL-EQ", "NSE:TATASTEEL-EQ", "NSE:HINDALCO-EQ",
            "NSE:ADANIPORTS-EQ", "NSE:GRASIM-EQ", "NSE:BRITANNIA-EQ", "NSE:DIVISLAB-EQ",
            "NSE:EICHERMOT-EQ", "NSE:HEROMOTOCO-EQ", "NSE:BAJAJ-AUTO-EQ", "NSE:M&M-EQ",
            "NSE:BPCL-EQ", "NSE:IOC-EQ", "NSE:INDUSINDBK-EQ", "NSE:APOLLOHOSP-EQ",
            "NSE:TATAMOTORS-EQ", "NSE:SHREECEM-EQ", "NSE:UPL-EQ", "NSE:TATACONSUM-EQ",
            "NSE:SBILIFE-EQ", "NSE:HDFCLIFE-EQ"
        ]
        
        # Add some additional high-volume stocks
        additional_stocks = [
            "NSE:ADANIENT-EQ", "NSE:ADANIGREEN-EQ", "NSE:VEDL-EQ", "NSE:GODREJCP-EQ",
            "NSE:PIDILITIND-EQ", "NSE:DABUR-EQ", "NSE:MARICO-EQ", "NSE:COLPAL-EQ",
            "NSE:BANKBARODA-EQ", "NSE:PNB-EQ", "NSE:CANBK-EQ", "NSE:UNIONBANK-EQ",
            "NSE:SAIL-EQ", "NSE:NMDC-EQ", "NSE:MOIL-EQ", "NSE:NATIONALUM-EQ"
        ]
        
        return nifty_50_symbols + additional_stocks
    
    except Exception as e:
        print(f"Error getting dynamic symbols: {str(e)}")
        # Fallback to basic symbols
        return [
            "NSE:RELIANCE-EQ", "NSE:TCS-EQ", "NSE:INFY-EQ", "NSE:HDFCBANK-EQ",
            "NSE:ICICIBANK-EQ", "NSE:KOTAKBANK-EQ", "NSE:SBIN-EQ", "NSE:BHARTIARTL-EQ"
        ]

def get_nifty_fno_symbols(fyers):
    """
    Get Nifty 50 and F&O stocks for one-hour setup scanning
    """
    try:
        # Nifty 50 stocks with high F&O activity
        # nifty_fno_stocks = ["NSE:DALBHARAT-EQ"]
        nifty_50 = [
            "NSE:NIFTYBANK-INDEX,","NSE:NIFTY50-INDEX","NSE:ADANIENT-EQ","NSE:ADANIPORTS-EQ","NSE:APOLLOHOSP-EQ","NSE:ASIANPAINT-EQ","NSE:AXISBANK-EQ","NSE:BAJAJ-AUTO-EQ","NSE:BAJFINANCE-EQ","NSE:BAJAJFINSV-EQ","NSE:BEL-EQ","NSE:BPCL-EQ","NSE:BHARTIARTL-EQ","NSE:BRITANNIA-EQ","NSE:CIPLA-EQ","NSE:COALINDIA-EQ","NSE:DRREDDY-EQ","NSE:EICHERMOT-EQ","NSE:GRASIM-EQ","NSE:HCLTECH-EQ","NSE:HDFCBANK-EQ","NSE:HDFCLIFE-EQ","NSE:HEROMOTOCO-EQ","NSE:HINDALCO-EQ","NSE:HINDUNILVR-EQ","NSE:ICICIBANK-EQ","NSE:ITC-EQ","NSE:INDUSINDBK-EQ","NSE:INFY-EQ","NSE:JSWSTEEL-EQ","NSE:KOTAKBANK-EQ","NSE:LT-EQ","NSE:M&M-EQ","NSE:MARUTI-EQ","NSE:NTPC-EQ","NSE:NESTLEIND-EQ","NSE:ONGC-EQ","NSE:POWERGRID-EQ","NSE:RELIANCE-EQ","NSE:SBILIFE-EQ","NSE:SHRIRAMFIN-EQ","NSE:SBIN-EQ","NSE:SUNPHARMA-EQ","NSE:TCS-EQ","NSE:TATACONSUM-EQ","NSE:TATASTEEL-EQ","NSE:TECHM-EQ","NSE:TITAN-EQ","NSE:TRENT-EQ","NSE:ULTRACEMCO-EQ","NSE:WIPRO-EQ"
        ]
        nifty_fno_stocks = [
            "NSE:PAGEIND-EQ","NSE:BOSCHLTD-EQ","NSE:SHREECEM-EQ","NSE:POWERINDIA-EQ","NSE:MARUTI-EQ","NSE:DIXON-EQ","NSE:SOLARINDS-EQ","NSE:ULTRACEMCO-EQ","NSE:BAJAJ-AUTO-EQ","NSE:MCX-EQ","NSE:OFSS-EQ","NSE:AMBER-EQ","NSE:APOLLOHOSP-EQ","NSE:POLYCAB-EQ","NSE:NUVAMA-EQ","NSE:EICHERMOT-EQ","NSE:KAYNES-EQ","NSE:DIVISLAB-EQ","NSE:BRITANNIA-EQ","NSE:PERSISTENT-EQ","NSE:INDIGO-EQ","NSE:LTIM-EQ","NSE:ALKEM-EQ","NSE:TATAELXSI-EQ","NSE:HDFCAMC-EQ","NSE:HEROMOTOCO-EQ","NSE:ABB-EQ","NSE:HAL-EQ","NSE:TRENT-EQ","NSE:DMART-EQ","NSE:CUMMINSIND-EQ","NSE:KEI-EQ","NSE:SUPREMEIND-EQ","NSE:LT-EQ","NSE:CAMS-EQ","NSE:TITAN-EQ","NSE:M&M-EQ","NSE:TVSMOTOR-EQ","NSE:PIIND-EQ","NSE:TORNTPHARM-EQ","NSE:MUTHOOTFIN-EQ","NSE:TIINDIA-EQ","NSE:SIEMENS-EQ","NSE:SRF-EQ","NSE:TCS-EQ","NSE:GRASIM-EQ","NSE:MPHASIS-EQ","NSE:MAZDOCK-EQ","NSE:HINDUNILVR-EQ","NSE:ANGELONE-EQ","NSE:ADANIENT-EQ","NSE:ASIANPAINT-EQ","NSE:BSE-EQ","NSE:MANKIND-EQ","NSE:GODREJPROP-EQ","NSE:COLPAL-EQ","NSE:KOTAKBANK-EQ","NSE:BAJAJFINSV-EQ","NSE:DALBHARAT-EQ","NSE:BHARTIARTL-EQ","NSE:BLUESTARCO-EQ","NSE:ICICIGI-EQ","NSE:LUPIN-EQ","NSE:SBILIFE-EQ","NSE:GLENMARK-EQ","NSE:COFORGE-EQ","NSE:APLAPOLLO-EQ","NSE:PRESTIGE-EQ","NSE:CHOLAFIN-EQ","NSE:OBEROIRLTY-EQ","NSE:SUNPHARMA-EQ","NSE:POLICYBZR-EQ","NSE:PHOENIXLTD-EQ","NSE:CDSL-EQ","NSE:CIPLA-EQ","NSE:BDL-EQ","NSE:INFY-EQ","NSE:HCLTECH-EQ","NSE:MFSL-EQ","NSE:PIDILITIND-EQ","NSE:HAVELLS-EQ","NSE:TECHM-EQ","NSE:RELIANCE-EQ","NSE:VOLTAS-EQ","NSE:ASTRAL-EQ","NSE:ADANIPORTS-EQ","NSE:NAUKRI-EQ","NSE:ICICIBANK-EQ","NSE:UNITDSPR-EQ","NSE:TORNTPOWER-EQ","NSE:PAYTM-EQ","NSE:BHARATFORG-EQ","NSE:DRREDDY-EQ","NSE:NESTLEIND-EQ","NSE:AXISBANK-EQ","NSE:UNOMINDA-EQ","NSE:360ONE-EQ","NSE:CYIENT-EQ","NSE:MAXHEALTH-EQ","NSE:KPITTECH-EQ","NSE:LODHA-EQ","NSE:TATACONSUM-EQ","NSE:KFINTECH-EQ","NSE:JSWSTEEL-EQ","NSE:GODREJCP-EQ","NSE:BAJFINANCE-EQ","NSE:AUROPHARMA-EQ","NSE:FORTIS-EQ","NSE:ADANIGREEN-EQ","NSE:JINDALSTEL-EQ","NSE:ZYDUSLIFE-EQ","NSE:HDFCBANK-EQ","NSE:ADANIENSOL-EQ","NSE:SBICARD-EQ","NSE:LAURUSLABS-EQ","NSE:PNBHOUSING-EQ","NSE:SBIN-EQ","NSE:LICI-EQ","NSE:TITAGARH-EQ","NSE:AUBANK-EQ","NSE:HINDALCO-EQ","NSE:INDIANB-EQ","NSE:DLF-EQ","NSE:INDUSINDBK-EQ","NSE:INDHOTEL-EQ","NSE:HDFCLIFE-EQ","NSE:MARICO-EQ","NSE:CGPOWER-EQ","NSE:SHRIRAMFIN-EQ","NSE:IRCTC-EQ","NSE:TATATECH-EQ","NSE:UPL-EQ","NSE:SYNGENE-EQ","NSE:ICICIPRULI-EQ","NSE:JUBLFOOD-EQ","NSE:PATANJALI-EQ","NSE:LICHSGFIN-EQ","NSE:PGEL-EQ","NSE:AMBUJACEM-EQ","NSE:CONCOR-EQ","NSE:JSWENERGY-EQ","NSE:DABUR-EQ","NSE:VEDL-EQ","NSE:KALYANKJIL-EQ","NSE:IIFL-EQ","NSE:HINDZINC-EQ","NSE:SONACOMS-EQ","NSE:DELHIVERY-EQ","NSE:VBL-EQ","NSE:HINDPETRO-EQ","NSE:BEL-EQ","NSE:OIL-EQ","NSE:ITC-EQ","NSE:TMPV-EQ","NSE:TATAPOWER-EQ","NSE:COALINDIA-EQ","NSE:PFC-EQ","NSE:EXIDEIND-EQ","NSE:RECLTD-EQ","NSE:INDUSTOWER-EQ","NSE:BIOCON-EQ","NSE:NTPC-EQ","NSE:BPCL-EQ","NSE:RVNL-EQ","NSE:ETERNAL-EQ","NSE:RBLBANK-EQ","NSE:ABCAPITAL-EQ","NSE:JIOFIN-EQ","NSE:CROMPTON-EQ","NSE:POWERGRID-EQ","NSE:PETRONET-EQ","NSE:MANAPPURAM-EQ","NSE:LTF-EQ","NSE:BANKBARODA-EQ","NSE:ONGC-EQ","NSE:NYKAA-EQ","NSE:WIPRO-EQ","NSE:NATIONALUM-EQ","NSE:BHEL-EQ","NSE:FEDERALBNK-EQ","NSE:HUDCO-EQ","NSE:IGL-EQ","NSE:NCC-EQ","NSE:PPLPHARMA-EQ","NSE:SAMMAANCAP-EQ","NSE:GAIL-EQ","NSE:TATASTEEL-EQ","NSE:BANDHANBNK-EQ","NSE:INOXWIND-EQ","NSE:IREDA-EQ","NSE:IOC-EQ","NSE:IEX-EQ","NSE:UNIONBANK-EQ","NSE:ASHOKLEY-EQ","NSE:BANKINDIA-EQ","NSE:SAIL-EQ","NSE:CANBK-EQ","NSE:IRFC-EQ","NSE:PNB-EQ","NSE:NBCC-EQ","NSE:MOTHERSON-EQ","NSE:GMRAIRPORT-EQ","NSE:NHPC-EQ","NSE:IDFCFIRSTB-EQ","NSE:HFCL-EQ","NSE:NMDC-EQ","NSE:SUZLON-EQ","NSE:YESBANK-EQ","NSE:IDEA-EQ"
        ]
        
        # Combine and remove duplicates
        all_symbols = list(set(nifty_fno_stocks))
        
        return all_symbols
        
    except Exception as e:
        print(f"Error getting Nifty F&O symbols: {str(e)}")
        # Fallback to basic Nifty stocks
        # return ["NSE:DALBHARAT-EQ"]
        return [
            "NSE:PAGEIND-EQ","NSE:BOSCHLTD-EQ","NSE:SHREECEM-EQ","NSE:POWERINDIA-EQ","NSE:MARUTI-EQ","NSE:DIXON-EQ","NSE:SOLARINDS-EQ","NSE:ULTRACEMCO-EQ","NSE:BAJAJ-AUTO-EQ","NSE:MCX-EQ","NSE:OFSS-EQ","NSE:AMBER-EQ","NSE:APOLLOHOSP-EQ","NSE:POLYCAB-EQ","NSE:NUVAMA-EQ","NSE:EICHERMOT-EQ","NSE:KAYNES-EQ","NSE:DIVISLAB-EQ","NSE:BRITANNIA-EQ","NSE:PERSISTENT-EQ","NSE:INDIGO-EQ","NSE:LTIM-EQ","NSE:ALKEM-EQ","NSE:TATAELXSI-EQ","NSE:HDFCAMC-EQ","NSE:HEROMOTOCO-EQ","NSE:ABB-EQ","NSE:HAL-EQ","NSE:TRENT-EQ","NSE:DMART-EQ","NSE:CUMMINSIND-EQ","NSE:KEI-EQ","NSE:SUPREMEIND-EQ","NSE:LT-EQ","NSE:CAMS-EQ","NSE:TITAN-EQ","NSE:M&M-EQ","NSE:TVSMOTOR-EQ","NSE:PIIND-EQ","NSE:TORNTPHARM-EQ","NSE:MUTHOOTFIN-EQ","NSE:TIINDIA-EQ","NSE:SIEMENS-EQ","NSE:SRF-EQ","NSE:TCS-EQ","NSE:GRASIM-EQ","NSE:MPHASIS-EQ","NSE:MAZDOCK-EQ","NSE:HINDUNILVR-EQ","NSE:ANGELONE-EQ","NSE:ADANIENT-EQ","NSE:ASIANPAINT-EQ","NSE:BSE-EQ","NSE:MANKIND-EQ","NSE:GODREJPROP-EQ","NSE:COLPAL-EQ","NSE:KOTAKBANK-EQ","NSE:BAJAJFINSV-EQ","NSE:DALBHARAT-EQ","NSE:BHARTIARTL-EQ","NSE:BLUESTARCO-EQ","NSE:ICICIGI-EQ","NSE:LUPIN-EQ","NSE:SBILIFE-EQ","NSE:GLENMARK-EQ","NSE:COFORGE-EQ","NSE:APLAPOLLO-EQ","NSE:PRESTIGE-EQ","NSE:CHOLAFIN-EQ","NSE:OBEROIRLTY-EQ","NSE:SUNPHARMA-EQ","NSE:POLICYBZR-EQ","NSE:PHOENIXLTD-EQ","NSE:CDSL-EQ","NSE:CIPLA-EQ","NSE:BDL-EQ","NSE:INFY-EQ","NSE:HCLTECH-EQ","NSE:MFSL-EQ","NSE:PIDILITIND-EQ","NSE:HAVELLS-EQ","NSE:TECHM-EQ","NSE:RELIANCE-EQ","NSE:VOLTAS-EQ","NSE:ASTRAL-EQ","NSE:ADANIPORTS-EQ","NSE:NAUKRI-EQ","NSE:ICICIBANK-EQ","NSE:UNITDSPR-EQ","NSE:TORNTPOWER-EQ","NSE:PAYTM-EQ","NSE:BHARATFORG-EQ","NSE:DRREDDY-EQ","NSE:NESTLEIND-EQ","NSE:AXISBANK-EQ","NSE:UNOMINDA-EQ","NSE:360ONE-EQ","NSE:CYIENT-EQ","NSE:MAXHEALTH-EQ","NSE:KPITTECH-EQ","NSE:LODHA-EQ","NSE:TATACONSUM-EQ","NSE:KFINTECH-EQ","NSE:JSWSTEEL-EQ","NSE:GODREJCP-EQ","NSE:BAJFINANCE-EQ","NSE:AUROPHARMA-EQ","NSE:FORTIS-EQ","NSE:ADANIGREEN-EQ","NSE:JINDALSTEL-EQ","NSE:ZYDUSLIFE-EQ","NSE:HDFCBANK-EQ","NSE:ADANIENSOL-EQ","NSE:SBICARD-EQ","NSE:LAURUSLABS-EQ","NSE:PNBHOUSING-EQ","NSE:SBIN-EQ","NSE:LICI-EQ","NSE:TITAGARH-EQ","NSE:AUBANK-EQ","NSE:HINDALCO-EQ","NSE:INDIANB-EQ","NSE:DLF-EQ","NSE:INDUSINDBK-EQ","NSE:INDHOTEL-EQ","NSE:HDFCLIFE-EQ","NSE:MARICO-EQ","NSE:CGPOWER-EQ","NSE:SHRIRAMFIN-EQ","NSE:IRCTC-EQ","NSE:TATATECH-EQ","NSE:UPL-EQ","NSE:SYNGENE-EQ","NSE:ICICIPRULI-EQ","NSE:JUBLFOOD-EQ","NSE:PATANJALI-EQ","NSE:LICHSGFIN-EQ","NSE:PGEL-EQ","NSE:AMBUJACEM-EQ","NSE:CONCOR-EQ","NSE:JSWENERGY-EQ","NSE:DABUR-EQ","NSE:VEDL-EQ","NSE:KALYANKJIL-EQ","NSE:IIFL-EQ","NSE:HINDZINC-EQ","NSE:SONACOMS-EQ","NSE:DELHIVERY-EQ","NSE:VBL-EQ","NSE:HINDPETRO-EQ","NSE:BEL-EQ","NSE:OIL-EQ","NSE:ITC-EQ","NSE:TMPV-EQ","NSE:TATAPOWER-EQ","NSE:COALINDIA-EQ","NSE:PFC-EQ","NSE:EXIDEIND-EQ","NSE:RECLTD-EQ","NSE:INDUSTOWER-EQ","NSE:BIOCON-EQ","NSE:NTPC-EQ","NSE:BPCL-EQ","NSE:RVNL-EQ","NSE:ETERNAL-EQ","NSE:RBLBANK-EQ","NSE:ABCAPITAL-EQ","NSE:JIOFIN-EQ","NSE:CROMPTON-EQ","NSE:POWERGRID-EQ","NSE:PETRONET-EQ","NSE:MANAPPURAM-EQ","NSE:LTF-EQ","NSE:BANKBARODA-EQ","NSE:ONGC-EQ","NSE:NYKAA-EQ","NSE:WIPRO-EQ","NSE:NATIONALUM-EQ","NSE:BHEL-EQ","NSE:FEDERALBNK-EQ","NSE:HUDCO-EQ","NSE:IGL-EQ","NSE:NCC-EQ","NSE:PPLPHARMA-EQ","NSE:SAMMAANCAP-EQ","NSE:GAIL-EQ","NSE:TATASTEEL-EQ","NSE:BANDHANBNK-EQ","NSE:INOXWIND-EQ","NSE:IREDA-EQ","NSE:IOC-EQ","NSE:IEX-EQ","NSE:UNIONBANK-EQ","NSE:ASHOKLEY-EQ","NSE:BANKINDIA-EQ","NSE:SAIL-EQ","NSE:CANBK-EQ","NSE:IRFC-EQ","NSE:PNB-EQ","NSE:NBCC-EQ","NSE:MOTHERSON-EQ","NSE:GMRAIRPORT-EQ","NSE:NHPC-EQ","NSE:IDFCFIRSTB-EQ","NSE:HFCL-EQ","NSE:NMDC-EQ","NSE:SUZLON-EQ","NSE:YESBANK-EQ","NSE:IDEA-EQ"
        ]

def scan_regular(fyers, filters):
    """
    Regular stock scanning logic using real Fyers API data
    """
    try:
        # Get dynamic symbol list from Fyers API (no longer filtering by segment)
        symbols = get_dynamic_symbols(fyers)
        
        results = []
        
        # Limit to first 20 symbols for performance (increased from 10)
        for symbol in symbols[:20]:
            try:
                current_price = get_current_price(fyers, symbol)
                if current_price and meets_criteria(current_price, filters):
                    # Calculate RSI and pattern based on historical data
                    hist_data = get_historical_data(fyers, symbol)
                    rsi_value = calculate_rsi(hist_data) if hist_data else 50
                    pattern = determine_pattern(current_price, hist_data)
                    
                    results.append({
                        'symbol': symbol.split(':')[1].replace('-EQ', ''),
                        'price': current_price['price'],
                        'change': current_price['change_percent'],
                        'volume': current_price['volume'],
                        'rsi': rsi_value,
                        'pattern': pattern
                    })
            except Exception as e:
                print(f"Error processing {symbol}: {str(e)}")
                continue
        
        return results
    
    except Exception as e:
        print(f"Regular scan error: {str(e)}")
        return []

def get_historical_data(fyers, symbol):
    """
    Get historical data for previous day analysis
    """
    try:
        from datetime import datetime, timedelta
        
        # Calculate date range (previous trading day)
        today = datetime.now()
        # Get previous trading day (skip weekends)
        prev_day = today - timedelta(days=1)
        while prev_day.weekday() >= 5:  # Skip Saturday (5) and Sunday (6)
            prev_day -= timedelta(days=1)
        
        # Format dates for Fyers API
        from_date = prev_day.strftime("%Y-%m-%d")
        to_date = today.strftime("%Y-%m-%d")
        
        # Fyers historical data request
        data = {
            "symbol": symbol,
            "resolution": "D",  # Daily data
            "date_format": "1",
            "range_from": from_date,
            "range_to": to_date,
            "cont_flag": "1"
        }
        
        response = fyers.history(data)
        
        if response and response.get('code') == 200 and response.get('candles'):
            candles = response['candles']
            if len(candles) > 0:
                # Fyers candle format: [timestamp, open, high, low, close, volume]
                latest_candle = candles[-1]
                
                return {
                    'prev_day_open': float(latest_candle[1]),
                    'prev_day_high': float(latest_candle[2]),
                    'prev_day_low': float(latest_candle[3]),
                    'prev_day_close': float(latest_candle[4]),
                    'prev_day_volume': int(latest_candle[5])
                }
        
        print(f"No historical data found for {symbol}")
        return None
        
    except Exception as e:
        print(f"Historical data error for {symbol}: {str(e)}")
        return None

def get_current_price(fyers, symbol):
    """
    Get current market data for a symbol
    """
    try:
        # Fyers quotes API call
        data = {"symbols": symbol}
        response = fyers.quotes(data)
        
        if response and response.get('code') == 200 and response.get('d'):
            quote_data = response['d'][0]  # First symbol data
            
            # Extract relevant data from Fyers response
            current_price = float(quote_data.get('v', {}).get('lp', 0))  # Last price
            prev_close = float(quote_data.get('v', {}).get('prev_close_price', current_price))
            volume = int(quote_data.get('v', {}).get('volume', 0))
            
            # Calculate change percentage
            change_percent = ((current_price - prev_close) / prev_close) * 100 if prev_close > 0 else 0
            
            return {
                'price': current_price,
                'change_percent': round(change_percent, 2),
                'volume': volume,
                'prev_close': prev_close,
                'high': float(quote_data.get('v', {}).get('h', current_price)),
                'low': float(quote_data.get('v', {}).get('l', current_price)),
                'open': float(quote_data.get('v', {}).get('o', current_price))
            }
        
        print(f"No current price data found for {symbol}")
        return None
        
    except Exception as e:
        print(f"Current price error for {symbol}: {str(e)}")
        return None

def analyze_one_hour_setup(hist_data, current_price, filters):
    """
    Analyze if stock meets One Hour Setup criteria for next day trading
    
    One Hour Setup Strategy:
    1. Previous day should have Strong Bullish/Bearish close
    2. Next day opening should be flat (within tolerance of previous close)
    3. This creates a setup for potential breakout trading
    """
    try:
        # Determine previous day's closing strength
        prev_close_strength = determine_close_strength(hist_data)
        
        # Check if next day opening will be flat (using current price as proxy)
        flat_open = check_flat_opening(hist_data, current_price, filters)
        print('----------------------------------------------------------------')
        print(f"Previous Close Strength: {prev_close_strength}")
        print(f"Next Day Flat Open Expected: {flat_open}")
        print('----------------------------------------------------------------')
        # Determine signal based on strategy
        # Setup is ready when we have strong previous close AND flat opening expected
        signal = "Setup Ready" if flat_open and prev_close_strength in ["Strong Bullish", "Strong Bearish"] else "Wait for Signal"
        
        # Enhanced eligibility criteria for next day trading preparation
        # Include stocks with strong patterns that might have flat openings
        is_eligible = (prev_close_strength in ["Strong Bullish", "Strong Bearish"]) and flat_open
        
        print(f"One Hour Setup Analysis for {hist_data.get('symbol', 'Unknown')}: prev_close={prev_close_strength}, flat_open={flat_open}, eligible={is_eligible}, signal={signal}")
        
        return {
            'eligible': is_eligible,
            'prev_close_type': prev_close_strength,
            'flat_open': flat_open,
            'signal': signal,
            'pattern': f"{prev_close_strength} Close + {'Flat' if flat_open else 'Gap'} Open"
        }
    
    except Exception as e:
        print(f"One Hour Setup analysis error: {str(e)}")
        return {'eligible': False}

def determine_close_strength(hist_data):
    """
    Determine if previous day's close was Strong Bullish or Strong Bearish
    """
    try:
        open_price = hist_data['prev_day_open']
        close_price = hist_data['prev_day_close']
        high_price = hist_data['prev_day_high']
        low_price = hist_data['prev_day_low']
        
        # Calculate candle body and range
        body_size = abs(close_price - open_price)
        total_range = high_price - low_price
    
        # Handle edge cases
        if total_range == 0:
            # If no range, check if it's a bullish or bearish doji
            if close_price > open_price:
                return "Strong Bullish"
            elif close_price < open_price:
                return "Strong Bearish"
            else:
                return "Neutral"
        
        body_percentage = (body_size / total_range) * 100
        price_change_percent = abs((close_price - open_price) / open_price) * 100
        
        # Enhanced Strong candle criteria:
        # 1. Body > 50% of total range (reduced from 60% for better detection)
        # 2. OR price change > 2% (alternative criteria for strong moves)
        is_strong_candle = body_percentage > 50 or price_change_percent > 2
        print('----------------------------------------------------------------')
        print(f"body_size={body_size:.2f}, total_range={total_range:.2f}, body_pct={body_percentage:.1f}%, price_change={price_change_percent:.1f}%")
        print(f"Strong Candle: {is_strong_candle}")
        print('----------------------------------------------------------------')
        if is_strong_candle:
            if close_price > open_price:
                print(f"Strong Bullish detected: body_pct={body_percentage:.1f}%, price_change={price_change_percent:.1f}%")
                return "Strong Bullish"
            else:
                print(f"Strong Bearish detected: body_pct={body_percentage:.1f}%, price_change={price_change_percent:.1f}%")
                return "Strong Bearish"
        
        # Medium strength criteria
        if body_percentage > 30 or price_change_percent > 1:
            if close_price > open_price:
                return "Bullish"
            else:
                return "Bearish"
        
        return "Neutral"
    
    except Exception as e:
        print(f"Close strength analysis error: {str(e)}")
        return "Neutral"

def check_flat_opening(hist_data, current_price, filters):
    """
    Check if next day opening will be flat compared to previous close
    For one-hour setup strategy, this is used for next day trading preparation
    """
    try:
        prev_close = hist_data['prev_day_close']
        
        # For next day trading, we use current price as proxy for potential opening
        # In real trading, this would be checked at market open the next day
        current_ltp = current_price['price']  # Last traded price as opening proxy
        
        # Calculate percentage difference between previous close and current price
        percent_diff = abs((current_ltp - prev_close) / prev_close) * 100
        
        # Get tolerance from filters (default 1% for flat opening)
        stock_tolerance = float(filters.get('stockFlatTolerance', 1.0))
        
        is_flat = percent_diff <= stock_tolerance
        
        print(f"Flat opening check: prev_close={prev_close:.2f}, current_ltp={current_ltp:.2f}, diff={percent_diff:.2f}%, tolerance={stock_tolerance}%, is_flat={is_flat}")
        
        return is_flat
    
    except Exception as e:
        print(f"Flat opening check error: {str(e)}")
        return False
    
    except Exception as e:
        print(f"Flat opening check error: {str(e)}")
        return False

def meets_criteria(price_data, filters):
    """
    Check if stock meets regular scanning criteria
    """
    try:
        # Since we removed all filtering criteria, all stocks meet the criteria
        # This function is kept for compatibility but no longer filters
        return True
    
    except Exception as e:
        print(f"Criteria check error: {str(e)}")
        return False

def calculate_rsi(hist_data, period=14):
    """Calculate RSI (Relative Strength Index) from historical data"""
    try:
        if not hist_data:
            return 50  # Default neutral RSI
        
        # Get historical candles for RSI calculation
        from datetime import datetime, timedelta
        
        # Get more historical data for RSI calculation
        today = datetime.now()
        from_date = (today - timedelta(days=30)).strftime("%Y-%m-%d")
        to_date = today.strftime("%Y-%m-%d")
        
        # For now, use a simplified RSI calculation based on current price data
        # In a real implementation, you would fetch more historical data
        return 50  # Neutral RSI as placeholder
        
    except Exception as e:
        print(f"RSI calculation error: {str(e)}")
        return 50

def determine_pattern(current_price, hist_data):
    """Determine price pattern based on current and historical data"""
    try:
        if not current_price:
            return 'Neutral'
        
        change_percent = current_price.get('change_percent', 0)
        volume = current_price.get('volume', 0)
        
        # Pattern determination based on price change and volume
        if change_percent > 3:
            return 'Strong Bullish'
        elif change_percent > 1.5:
            return 'Bullish'
        elif change_percent < -3:
            return 'Strong Bearish'
        elif change_percent < -1.5:
            return 'Bearish'
        elif abs(change_percent) < 0.5:
            return 'Sideways'
        else:
            return 'Neutral'
        
    except Exception as e:
        print(f"Pattern determination error: {str(e)}")
        return 'Neutral'

# Paper Trading Routes
@app.route('/paper-trading')
def paper_trading():
    if 'access_token' not in session:
        return redirect(url_for('login'))
    return render_template('paper_trading.html')

@app.route('/api/paper-trading/portfolio')
def api_paper_trading_portfolio():
    if 'access_token' not in session:
        return jsonify({'error': 'Not authenticated'}), 401
    
    try:
        # Get or initialize portfolio data
        portfolio_data = get_portfolio_data()
        active_positions = get_active_positions()
        trade_history = get_trade_history()
        
        return jsonify({
            'success': True,
            'portfolio': portfolio_data,
            'activePositions': active_positions,
            'tradeHistory': trade_history
        })
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

@app.route('/api/paper-trading/execute', methods=['POST'])
def api_paper_trading_execute():
    if 'access_token' not in session:
        return jsonify({'error': 'Not authenticated'}), 401
    
    try:
        data = request.get_json()
        
        # Validate trade data
        required_fields = ['symbol', 'type', 'quantity', 'entryPrice', 'stopLoss', 'target']
        for field in required_fields:
            if field not in data:
                return jsonify({'success': False, 'error': f'Missing field: {field}'}), 400
        
        # Execute paper trade
        trade_result = execute_paper_trade(data)
        
        if trade_result['success']:
            return jsonify({'success': True, 'tradeId': trade_result['tradeId']})
        else:
            return jsonify({'success': False, 'error': trade_result['error']})
    
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

@app.route('/api/paper-trading/close', methods=['POST'])
def api_paper_trading_close():
    if 'access_token' not in session:
        return jsonify({'error': 'Not authenticated'}), 401
    
    try:
        data = request.get_json()
        position_id = data.get('positionId')
        exit_price = data.get('exitPrice')
        
        if not position_id:
            return jsonify({'success': False, 'error': 'Position ID required'}), 400
        
        if not exit_price:
            return jsonify({'success': False, 'error': 'Exit price required'}), 400
        
        # Close position using database
        user_id = session.get('user_id', 'default_user')
        result = paper_trading_db.close_position(user_id, position_id, float(exit_price), 'MANUAL')
        
        return jsonify(result)
    
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

# Paper Trading Helper Functions
def get_portfolio_data():
    """Get current portfolio summary"""
    user_id = session.get('user_id', 'default_user')
    portfolio = paper_trading_db.get_or_create_portfolio(user_id)
    active_positions = paper_trading_db.get_active_positions(user_id)
    trade_history = paper_trading_db.get_trade_history(user_id)
    
    return {
        'value': portfolio['current_value'],
        'totalPnL': portfolio['total_pnl'],
        'activeTrades': len(active_positions),
        'completedTrades': len(trade_history),
        'winningTrades': len([t for t in trade_history if t.get('pnl', 0) > 0])
    }

def get_active_positions():
    """Get all active trading positions"""
    user_id = session.get('user_id', 'default_user')
    positions = paper_trading_db.get_active_positions(user_id)
    
    # Calculate current P&L for each position
    for position in positions:
        if position['trade_type'].upper() == 'BUY':
            position['pnl'] = (position['current_price'] - position['entry_price']) * position['quantity']
        else:  # SELL
            position['pnl'] = (position['entry_price'] - position['current_price']) * position['quantity']
    
    return positions

def get_trade_history():
    """Get completed trade history"""
    user_id = session.get('user_id', 'default_user')
    return paper_trading_db.get_trade_history(user_id)

def execute_paper_trade(trade_data):
    """Execute a paper trade with risk management controls"""
    try:
        # Risk Management Checks
        risk_check = validate_trade_risk(trade_data)
        if not risk_check['valid']:
            return {'success': False, 'error': risk_check['error']}
        
        # Calculate risk
        entry_price = float(trade_data['entryPrice'])
        stop_loss = float(trade_data['stopLoss'])
        quantity = int(trade_data['quantity'])
        risk_amount = abs(entry_price - stop_loss) * quantity
        
        # Prepare trade data for database
        db_trade_data = {
            'symbol': trade_data['symbol'],
            'type': trade_data['type'],
            'quantity': quantity,
            'entryPrice': entry_price,
            'stopLoss': stop_loss,
            'target': float(trade_data['target']),
            'strategy': trade_data.get('strategy', 'Manual'),
            'notes': trade_data.get('notes', ''),
            'riskAmount': risk_amount
        }
        
        # Execute trade in database
        user_id = session.get('user_id', 'default_user')
        result = paper_trading_db.execute_trade(user_id, db_trade_data)
        
        if result['success']:
            return {'success': True, 'tradeId': result['trade_id']}
        else:
            return {'success': False, 'error': result['error']}
    
    except Exception as e:
        return {'success': False, 'error': str(e)}

def validate_trade_risk(trade_data):
    """Validate trade against risk management rules"""
    try:
        symbol = trade_data['symbol']
        strategy = trade_data.get('strategy', '')
        
        # Get existing trades for this symbol/strategy
        existing_trades = get_symbol_trades(symbol, strategy)
        
        # Rule 1: Max 2 trades per index for One Hour Setup
        if strategy == 'One Hour Setup':
            if is_index_symbol(symbol):
                active_index_trades = len([t for t in existing_trades if t['status'] == 'ACTIVE'])
                if active_index_trades >= 2:
                    return {
                        'valid': False,
                        'error': f'Maximum 2 active trades allowed for index {symbol} with One Hour Setup strategy'
                    }
        
        # Rule 2: No re-entry after stop loss hit
        recent_sl_trades = [t for t in existing_trades if t.get('exitReason') == 'STOP_LOSS']
        if recent_sl_trades:
            # Check if any SL hit today
            from datetime import datetime, timedelta
            today = datetime.now().date()
            for trade in recent_sl_trades:
                trade_date = datetime.fromisoformat(trade['timestamp']).date()
                if trade_date == today:
                    return {
                        'valid': False,
                        'error': f'No re-entry allowed for {symbol} after stop loss hit today'
                    }
        
        # Rule 3: Maximum risk per trade (2% of portfolio)
        entry_price = float(trade_data['entryPrice'])
        stop_loss = float(trade_data['stopLoss'])
        quantity = int(trade_data['quantity'])
        risk_amount = abs(entry_price - stop_loss) * quantity
        
        portfolio_value = get_portfolio_data()['value']
        max_risk = portfolio_value * 0.02  # 2% max risk
        
        if risk_amount > max_risk:
            return {
                'valid': False,
                'error': f'Risk amount ₹{risk_amount:.2f} exceeds maximum allowed risk ₹{max_risk:.2f} (2% of portfolio)'
            }
        
        # Rule 4: Maximum 5 active positions at any time
        all_active_positions = get_active_positions()
        if len(all_active_positions) >= 5:
            return {
                'valid': False,
                'error': 'Maximum 5 active positions allowed. Close some positions before opening new ones.'
            }
        
        return {'valid': True}
    
    except Exception as e:
        return {'valid': False, 'error': f'Risk validation error: {str(e)}'}

def get_symbol_trades(symbol, strategy):
    """Get all trades for a specific symbol and strategy"""
    user_id = session.get('user_id', 'default_user')
    return paper_trading_db.get_symbol_trades(user_id, symbol, strategy)

def is_index_symbol(symbol):
    """Check if symbol is an index (Nifty, Bank Nifty, etc.)"""
    index_symbols = ['NIFTY', 'BANKNIFTY', 'FINNIFTY', 'MIDCPNIFTY']
    return any(index in symbol.upper() for index in index_symbols)

@app.route('/api/risk-management/status')
def api_risk_management_status():
    """Get current risk management status"""
    if 'access_token' not in session:
        return jsonify({'error': 'Not authenticated'}), 401
    
    try:
        portfolio = get_portfolio_data()
        active_positions = get_active_positions()
        
        # Calculate risk metrics
        total_risk = sum(pos.get('riskAmount', 0) for pos in active_positions)
        risk_percentage = (total_risk / portfolio['value']) * 100 if portfolio['value'] > 0 else 0
        
        # Count trades by strategy
        strategy_counts = {}
        for pos in active_positions:
            strategy = pos.get('strategy', 'Unknown')
            strategy_counts[strategy] = strategy_counts.get(strategy, 0) + 1
        
        # Index trade counts
        index_trades = len([pos for pos in active_positions if is_index_symbol(pos.get('symbol', ''))])
        
        return jsonify({
            'success': True,
            'riskMetrics': {
                'totalRisk': total_risk,
                'riskPercentage': risk_percentage,
                'maxRiskAllowed': portfolio['value'] * 0.02,
                'activePositions': len(active_positions),
                'maxPositions': 5,
                'indexTrades': index_trades,
                'maxIndexTrades': 2,
                'strategyBreakdown': strategy_counts
            }
        })
    
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

@app.route('/api/chart-data/<symbol>')
def api_chart_data(symbol):
    """Get chart data for a specific symbol"""
    if 'access_token' not in session:
        return jsonify({'error': 'Not authenticated'}), 401
    
    try:
        timeframe = request.args.get('timeframe', '1m')
        
        # Get Fyers client
        fyers = fyersModel.FyersModel(client_id=FYERS_CLIENT_ID, token=session['access_token'])
        
        # Try to get real chart data from Fyers API
        try:
            chart_data = get_real_chart_data(fyers, symbol, timeframe)
            if not chart_data:
                chart_data = generate_mock_chart_data(symbol, timeframe)
        except Exception as api_error:
            print(f"Fyers API error for chart data: {api_error}")
            chart_data = generate_mock_chart_data(symbol, timeframe)
        
        market_info = get_real_market_info(fyers, symbol)
        if not market_info:
            market_info = get_fallback_market_info(symbol)
        signals = analyze_one_hour_setup_signals(symbol, chart_data)
        
        return jsonify({
            'success': True,
            'data': chart_data,
            'marketInfo': market_info,
            'signals': signals
        })
    
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

def get_real_chart_data(fyers, symbol, timeframe='1m'):
    """Get real-time chart data using Fyers API"""
    try:
        from datetime import datetime, timedelta
        
        # Determine timeframe and date range
        timeframe_map = {
            '1m': '1',
            '5m': '5', 
            '15m': '15',
            '1h': '60'
        }
        
        resolution = timeframe_map.get(timeframe, '1')
        
        # Calculate date range
        now = datetime.now()
        if timeframe == '1m':
            from_date = (now - timedelta(hours=2)).strftime("%Y-%m-%d")
            to_date = now.strftime("%Y-%m-%d")
        elif timeframe == '5m':
            from_date = (now - timedelta(hours=8)).strftime("%Y-%m-%d")
            to_date = now.strftime("%Y-%m-%d")
        elif timeframe == '15m':
            from_date = (now - timedelta(days=1)).strftime("%Y-%m-%d")
            to_date = now.strftime("%Y-%m-%d")
        else:  # 1h
            from_date = (now - timedelta(days=5)).strftime("%Y-%m-%d")
            to_date = now.strftime("%Y-%m-%d")
        
        # Fyers historical data request
        data = {
            "symbol": symbol,
            "resolution": resolution,
            "date_format": "1",
            "range_from": from_date,
            "range_to": to_date,
            "cont_flag": "1"
        }
        
        response = fyers.history(data)
        
        if response and response.get('code') == 200 and response.get('candles'):
            candles = response['candles']
            chart_data = []
            
            for candle in candles:
                # Fyers candle format: [timestamp, open, high, low, close, volume]
                chart_data.append({
                    'time': datetime.fromtimestamp(candle[0]).isoformat(),
                    'open': round(float(candle[1]), 2),
                    'high': round(float(candle[2]), 2),
                    'low': round(float(candle[3]), 2),
                    'close': round(float(candle[4]), 2),
                    'volume': int(candle[5])
                })
            
            return chart_data
        
        print(f"No chart data found for {symbol}")
        return None
        
    except Exception as e:
        print(f"Chart data error for {symbol}: {str(e)}")
        return None

def generate_mock_chart_data(symbol, timeframe='1m'):
    """Generate fallback mock chart data"""
    return generate_fallback_chart_data(symbol, timeframe)

def generate_fallback_chart_data(symbol, timeframe='1m'):
    """Generate fallback mock candlestick data for chart"""
    import random
    from datetime import datetime, timedelta
    
    # Determine number of candles based on timeframe
    timeframe_minutes = {
        '1m': 1,
        '5m': 5,
        '15m': 15,
        '1h': 60
    }
    
    minutes = timeframe_minutes.get(timeframe, 1)
    num_candles = min(100, 1440 // minutes)  # Max 100 candles or 1 day worth
    
    # Base price for different symbols
    base_prices = {
        'NIFTY': 19500,
        'BANKNIFTY': 44000,
        'RELIANCE': 2500,
        'TCS': 3600,
        'INFY': 1450
    }
    
    base_price = base_prices.get(symbol.upper(), 2000)
    current_time = datetime.now()
    data = []
    
    for i in range(num_candles, 0, -1):
        candle_time = current_time - timedelta(minutes=i * minutes)
        
        # Generate realistic price movement
        volatility = base_price * 0.002  # 0.2% volatility
        open_price = base_price + random.uniform(-volatility, volatility)
        
        high_move = random.uniform(0, volatility)
        low_move = random.uniform(0, volatility)
        
        high = open_price + high_move
        low = open_price - low_move
        close = low + random.uniform(0, high - low)
        
        volume = random.randint(1000, 50000)
        
        data.append({
            'time': candle_time.isoformat(),
            'open': round(open_price, 2),
            'high': round(high, 2),
            'low': round(low, 2),
            'close': round(close, 2),
            'volume': volume
        })
        
        base_price = close  # Next candle starts from current close
    
    return data

def get_real_market_info(fyers, symbol):
    """Get real market info using Fyers API"""
    try:
        current_price_data = get_current_price(fyers, symbol)
        
        if current_price_data:
            return {
                'symbol': symbol,
                'price': current_price_data['price'],
                'change': current_price_data['change'],
                'changePercent': current_price_data['changePercent'],
                'volume': current_price_data.get('volume', 0),
                'high': current_price_data.get('high', current_price_data['price']),
                'low': current_price_data.get('low', current_price_data['price']),
                'open': current_price_data.get('open', current_price_data['price']),
                'marketStatus': 'OPEN'  # Simplified - could be enhanced with actual market hours
            }
        else:
            return None
            
    except Exception as e:
        print(f"Error getting real market info for {symbol}: {str(e)}")
        return None

def get_mock_market_info(symbol):
    """Get real market information using Fyers API"""
    try:
        # Initialize Fyers client
        if 'access_token' not in session:
            return get_fallback_market_info(symbol)
            
        fyers = fyersModel.FyersModel(
            client_id=FYERS_CLIENT_ID,
            token=session['access_token']
        )
        
        # Get current quote
        data = {"symbols": symbol}
        response = fyers.quotes(data)
        
        if response and response.get('code') == 200 and response.get('d'):
            quote_data = response['d'][0]
            quote_values = quote_data.get('v', {})
            
            current_price = float(quote_values.get('lp', 0))
            prev_close = float(quote_values.get('prev_close_price', current_price))
            volume = int(quote_values.get('volume', 0))
            
            # Calculate change
            change = current_price - prev_close
            change_percent = (change / prev_close) * 100 if prev_close > 0 else 0
            
            # Determine market status
            from datetime import datetime
            current_hour = datetime.now().hour
            market_status = 'Open' if 9 <= current_hour <= 15 else 'Closed'
            
            return {
                'currentPrice': round(current_price, 2),
                'change': round(change, 2),
                'changePercent': round(change_percent, 2),
                'volume': volume,
                'status': market_status
            }
        
        print(f"No market info found for {symbol}")
        return get_fallback_market_info(symbol)
        
    except Exception as e:
        print(f"Market info error for {symbol}: {str(e)}")
        return get_fallback_market_info(symbol)

def get_fallback_market_info(symbol):
    """Get fallback mock market information"""
    import random
    from datetime import datetime
    
    base_prices = {
        'NIFTY': 19500,
        'BANKNIFTY': 44000,
        'RELIANCE': 2500,
        'TCS': 3600,
        'INFY': 1450
    }
    
    base_price = base_prices.get(symbol.upper(), 2000)
    current_price = base_price + random.uniform(-50, 50)
    change = random.uniform(-100, 100)
    change_percent = (change / current_price) * 100
    
    return {
        'currentPrice': round(current_price, 2),
        'change': round(change, 2),
        'changePercent': round(change_percent, 2),
        'volume': random.randint(100000, 10000000),
        'status': 'Open' if 9 <= datetime.now().hour <= 15 else 'Closed'
    }

def analyze_one_hour_setup_signals(symbol, chart_data):
    """Analyze One Hour Setup signals from chart data"""
    import random
    
    if len(chart_data) < 2:
        return {
            'prevDayClose': 'Analyzing...',
            'openingStatus': 'Checking...',
            'entrySignal': 'Waiting...'
        }
    
    # Mock signal analysis
    prev_day_close = random.choice(['Strong Bullish', 'Strong Bearish', 'Neutral'])
    
    # Check if opening is flat (within tolerance)
    first_candle = chart_data[0]
    open_price = float(first_candle['open'])
    close_price = float(first_candle['close'])
    
    flat_tolerance = 0.01  # 1% for stocks
    if symbol.upper() in ['NIFTY', 'BANKNIFTY']:
        flat_tolerance = 0.005  # 0.5% for indices
    
    price_diff_percent = abs(close_price - open_price) / open_price
    opening_status = 'Flat Open' if price_diff_percent <= flat_tolerance else 'Gap Open'
    
    # Entry signal logic
    entry_signal = 'Waiting for Signal'
    if prev_day_close != 'Neutral' and opening_status == 'Flat Open':
        # Look for opposite color candle
        if len(chart_data) >= 5:
            # Check recent candles for entry trigger
            recent_candles = chart_data[-5:]
            if prev_day_close == 'Strong Bearish':
                # Look for green candle then break of its low
                green_candles = [c for c in recent_candles if float(c['close']) > float(c['open'])]
                if green_candles and random.random() > 0.7:
                    entry_signal = 'Short Entry Triggered'
            elif prev_day_close == 'Strong Bullish':
                # Look for red candle then break of its high
                red_candles = [c for c in recent_candles if float(c['close']) < float(c['open'])]
                if red_candles and random.random() > 0.7:
                    entry_signal = 'Long Entry Triggered'
    
    return {
        'prevDayClose': prev_day_close,
        'openingStatus': opening_status,
        'entrySignal': entry_signal
    }

@app.route('/api/update-position-prices', methods=['POST'])
def api_update_position_prices():
    """Update current prices for all active positions"""
    if 'access_token' not in session:
        return jsonify({'error': 'Not authenticated'}), 401
    
    try:
        # Get Fyers client
        fyers = fyersModel.FyersModel(
            client_id=FYERS_CLIENT_ID,
            token=session['access_token']
        )
        
        # Get active positions
        user_id = session.get('user_id', 'default_user')
        active_positions = paper_trading_db.get_active_positions(user_id)
        
        updated_positions = []
        
        for position in active_positions:
            try:
                # Get current price from Fyers
                current_price_data = get_current_price(fyers, position['symbol'])
                
                if current_price_data:
                    current_price = current_price_data['price']
                    
                    # Update position with current price
                    paper_trading_db.update_position_price(position['id'], current_price)
                    
                    # Calculate P&L
                    if position['trade_type'].upper() == 'BUY':
                        pnl = (current_price - position['entry_price']) * position['quantity']
                    else:  # SELL
                        pnl = (position['entry_price'] - current_price) * position['quantity']
                    
                    position['current_price'] = current_price
                    position['pnl'] = round(pnl, 2)
                    
                    # Check for stop loss or target hit
                    if position['trade_type'].upper() == 'BUY':
                        if current_price <= position['stop_loss']:
                            paper_trading_db.close_position(user_id, position['id'], current_price, 'STOP_LOSS')
                            position['status'] = 'CLOSED'
                            position['exit_reason'] = 'STOP_LOSS'
                        elif current_price >= position['target']:
                            paper_trading_db.close_position(user_id, position['id'], current_price, 'TARGET')
                            position['status'] = 'CLOSED'
                            position['exit_reason'] = 'TARGET'
                    else:  # SELL
                        if current_price >= position['stop_loss']:
                            paper_trading_db.close_position(user_id, position['id'], current_price, 'STOP_LOSS')
                            position['status'] = 'CLOSED'
                            position['exit_reason'] = 'STOP_LOSS'
                        elif current_price <= position['target']:
                            paper_trading_db.close_position(user_id, position['id'], current_price, 'TARGET')
                            position['status'] = 'CLOSED'
                            position['exit_reason'] = 'TARGET'
                    
                    updated_positions.append(position)
                    
            except Exception as e:
                print(f"Error updating position {position['id']}: {str(e)}")
                continue
        
        return jsonify({
            'success': True,
            'positions': updated_positions,
            'updated_count': len(updated_positions)
        })
    
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=5000)