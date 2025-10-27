#!/bin/bash

# Fix Fyers API Dependency Issue
# This script handles the fyers-apiv3 version conflict

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

log_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root (use sudo)"
   exit 1
fi

APP_DIR="/opt/py-trade"
VENV_DIR="$APP_DIR/venv"

log_header "Fixing Fyers API Dependency Issue"

# Step 1: Check application directory
if [ ! -d "$APP_DIR" ]; then
    log_error "Application directory $APP_DIR does not exist!"
    exit 1
fi

cd "$APP_DIR"

# Step 2: Create/activate virtual environment
log_info "Setting up virtual environment..."
if [ ! -d "$VENV_DIR" ]; then
    log_info "Creating virtual environment..."
    python3 -m venv venv
    log_success "Virtual environment created"
fi

# Activate virtual environment
source "$VENV_DIR/bin/activate"

# Step 3: Upgrade pip
log_info "Upgrading pip..."
pip install --upgrade pip

# Step 4: Install dependencies without fyers-apiv3 first
log_info "Installing core dependencies..."
pip install Flask==3.0.0
pip install Werkzeug==3.0.1
pip install requests==2.31.0
pip install python-dotenv==1.0.0
pip install gunicorn==21.2.0
pip install setuptools>=68.0.0
pip install wheel>=0.41.0
pip install fyers-apiv3

# Step 5: Find and install the latest available fyers-apiv3
log_info "Finding latest available fyers-apiv3 version..."
LATEST_FYERS=$(pip index versions fyers-apiv3 2>/dev/null | grep "Available versions:" | head -1 | sed 's/Available versions: //' | tr ',' '\n' | head -1 | tr -d ' ')

# if [ -z "$LATEST_FYERS" ]; then
#     log_warning "Could not detect latest version. Trying common versions..."
#     # Try installing different versions in order of preference
#     for version in "3.1.7" "3.1.6" "3.1.5" "3.1.4" "3.1.3" "3.1.2" "3.1.1" "3.1.0"; do
#         log_info "Trying fyers-apiv3==$version..."
#         if pip install "fyers-apiv3==$version" 2>/dev/null; then
#             log_success "Successfully installed fyers-apiv3==$version"
#             INSTALLED_VERSION=$version
#             break
#         else
#             log_warning "Version $version failed, trying next..."
#         fi
#     done
# else
#     log_info "Installing fyers-apiv3==$LATEST_FYERS..."
#     pip install fyers-apiv3
#     INSTALLED_VERSION=$LATEST_FYERS
#     log_success "Successfully installed fyers-apiv3==$INSTALLED_VERSION"
# fi

# Step 6: Verify installation
log_info "Verifying fyers-apiv3 installation..."
python -c "import fyers_apiv3; print('✅ fyers-apiv3 imported successfully')" || {
    log_error "fyers-apiv3 import failed"
    exit 1
}

# Step 7: Test gunicorn
log_info "Testing gunicorn installation..."
if [ -f "$VENV_DIR/bin/gunicorn" ]; then
    "$VENV_DIR/bin/gunicorn" --version
    log_success "Gunicorn is working"
else
    log_error "Gunicorn not found"
    exit 1
fi

# Step 8: Test app import
log_info "Testing application import..."
python -c "import app; print('✅ App imports successfully')" || {
    log_error "App import failed"
    exit 1
}

# Step 9: Fix permissions
log_info "Fixing permissions..."
chown -R ubuntu:ubuntu "$APP_DIR"
chmod +x "$VENV_DIR/bin/gunicorn"
chmod +x "$VENV_DIR/bin/python"

# Step 10: Update requirements.txt with working version
log_info "Updating requirements.txt with working version..."
if [ ! -z "$INSTALLED_VERSION" ]; then
    sed -i "s/fyers-apiv3.*/fyers-apiv3==$INSTALLED_VERSION/" requirements.txt
    log_success "Updated requirements.txt with fyers-apiv3==$INSTALLED_VERSION"
fi

# Step 11: Test service configuration
log_info "Testing service configuration..."
sudo -u ubuntu "$VENV_DIR/bin/gunicorn" --config gunicorn.conf.py --check-config app:app || {
    log_error "Gunicorn configuration test failed"
    exit 1
}

log_success "All dependencies installed and tested successfully!"

# Step 12: Restart service
log_info "Restarting py-trade service..."
systemctl daemon-reload
systemctl stop py-trade.service || true
systemctl start py-trade.service

# Check service status
sleep 3
if systemctl is-active --quiet py-trade.service; then
    log_success "🎉 py-trade service is running successfully!"
    systemctl status py-trade.service --no-pager -l
else
    log_error "Service failed to start. Checking logs..."
    journalctl -u py-trade.service --no-pager -l -n 10
    exit 1
fi

log_header "Dependency Fix Complete!"
log_success "✅ fyers-apiv3 dependency resolved"
log_success "✅ py-trade service is running"
log_success "✅ Application should be accessible at https://algo.gshashank.com"