#!/bin/bash

# Update Fyers Redirect URI for Production
# This script updates the redirect URI from localhost to production domain

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

log_header "Updating Fyers Redirect URI for Production"

# Step 1: Update .env file
log_info "Updating .env file with production redirect URI..."
cd "$APP_DIR"

# Backup current .env
cp .env .env.backup.$(date +%Y%m%d_%H%M%S)

# Update redirect URI
sed -i 's|FYERS_REDIRECT_URI=http://127.0.0.1:5000/callback|FYERS_REDIRECT_URI=https://algo.gshashank.com/callback|g' .env

log_success "Updated FYERS_REDIRECT_URI to https://algo.gshashank.com/callback"

# Step 2: Verify the change
log_info "Verifying .env file changes..."
if grep -q "FYERS_REDIRECT_URI=https://algo.gshashank.com/callback" .env; then
    log_success "Redirect URI successfully updated in .env file"
else
    log_error "Failed to update redirect URI in .env file"
    exit 1
fi

# Step 3: Show current .env configuration
log_info "Current .env configuration:"
echo "----------------------------------------"
cat .env
echo "----------------------------------------"

# Step 4: Fix file permissions
log_info "Fixing file permissions..."
chown ubuntu:ubuntu .env
chmod 600 .env

# Step 5: Restart the service to apply changes
log_info "Restarting py-trade service to apply changes..."
systemctl restart py-trade.service

# Step 6: Wait and check service status
sleep 3
log_info "Checking service status..."
if systemctl is-active --quiet py-trade.service; then
    log_success "🎉 py-trade service restarted successfully!"
    
    # Show service status
    systemctl status py-trade.service --no-pager -l
    
    log_header "Redirect URI Update Complete!"
    log_success "✅ Redirect URI updated to production domain"
    log_success "✅ py-trade service is running with new configuration"
    log_success "✅ Login should now work properly at https://algo.gshashank.com"
    
    log_warning "⚠️  IMPORTANT: You must also update the redirect URI in your Fyers API app settings!"
    log_info "   1. Go to https://myapi.fyers.in/dashboard/"
    log_info "   2. Edit your app settings"
    log_info "   3. Change redirect URI to: https://algo.gshashank.com/callback"
    log_info "   4. Save the changes"
    
else
    log_error "Service failed to restart. Checking logs..."
    journalctl -u py-trade.service --no-pager -l -n 20
    
    log_info "Service status:"
    systemctl status py-trade.service --no-pager -l || true
    
    exit 1
fi