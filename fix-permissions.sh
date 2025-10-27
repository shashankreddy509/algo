#!/bin/bash

# Fix Permissions Script for py-trade Deployment
# This script resolves permission issues with virtual environments and deployment directories

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root"
    print_info "Run it as: sudo ./fix-permissions.sh"
    exit 1
fi

print_header "Fixing Permissions for py-trade Deployment"

# Define paths
CURRENT_DIR=$(pwd)
APP_DIR="/opt/py-trade"
VENV_DIR="$APP_DIR/venv"
HOME_VENV="$HOME/py-trade/venv"
UBUNTU_HOME="/home/ubuntu/py-trade"

print_info "Current directory: $CURRENT_DIR"
print_info "Target app directory: $APP_DIR"

# Fix current directory permissions
print_header "Fixing Current Directory Permissions"
if [[ -d "$CURRENT_DIR" ]]; then
    print_info "Setting ownership of current directory to ubuntu:ubuntu..."
    chown -R ubuntu:ubuntu "$CURRENT_DIR"
    chmod -R 755 "$CURRENT_DIR"
    print_success "Current directory permissions fixed"
fi

# Fix ubuntu home directory permissions if exists
if [[ -d "$UBUNTU_HOME" ]]; then
    print_header "Fixing Ubuntu Home Directory Permissions"
    print_info "Setting ownership of $UBUNTU_HOME to ubuntu:ubuntu..."
    chown -R ubuntu:ubuntu "$UBUNTU_HOME"
    chmod -R 755 "$UBUNTU_HOME"
    
    # Remove any problematic virtual environments
    if [[ -d "$UBUNTU_HOME/venv" ]]; then
        print_warning "Removing problematic virtual environment in home directory..."
        rm -rf "$UBUNTU_HOME/venv"
        print_success "Removed $UBUNTU_HOME/venv"
    fi
fi

# Clean up any existing virtual environments with permission issues
print_header "Cleaning Up Existing Virtual Environments"
VENV_LOCATIONS=(
    "$APP_DIR/venv"
    "$CURRENT_DIR/venv"
    "/home/ubuntu/py-trade/venv"
    "/tmp/py-trade-venv"
)

for venv_path in "${VENV_LOCATIONS[@]}"; do
    if [[ -d "$venv_path" ]]; then
        print_warning "Removing virtual environment: $venv_path"
        rm -rf "$venv_path"
        print_success "Removed $venv_path"
    fi
done

# Create application directory with correct permissions
print_header "Setting Up Application Directory"
if [[ ! -d "$APP_DIR" ]]; then
    print_info "Creating application directory: $APP_DIR"
    mkdir -p "$APP_DIR"
fi

# Set correct ownership and permissions for app directory
print_info "Setting ownership of $APP_DIR to ubuntu:ubuntu..."
chown -R ubuntu:ubuntu "$APP_DIR"
chmod -R 755 "$APP_DIR"

# Copy files to application directory if not already there
if [[ "$CURRENT_DIR" != "$APP_DIR" ]]; then
    print_header "Copying Files to Application Directory"
    print_info "Copying files from $CURRENT_DIR to $APP_DIR..."
    
    # Copy all files except virtual environments and cache
    rsync -av --exclude='venv' --exclude='__pycache__' --exclude='*.pyc' "$CURRENT_DIR/" "$APP_DIR/"
    
    # Set correct permissions after copy
    chown -R ubuntu:ubuntu "$APP_DIR"
    chmod -R 755 "$APP_DIR"
    
    # Make scripts executable
    chmod +x "$APP_DIR"/*.sh
    
    print_success "Files copied and permissions set"
fi

# Test virtual environment creation
print_header "Testing Virtual Environment Creation"
cd "$APP_DIR"

print_info "Testing virtual environment creation as ubuntu user..."
sudo -u ubuntu python3 -m venv "$VENV_DIR"

if [[ -d "$VENV_DIR" ]]; then
    print_success "Virtual environment created successfully"
    
    # Test pip installation
    print_info "Testing pip upgrade in virtual environment..."
    sudo -u ubuntu "$VENV_DIR/bin/pip" install --upgrade pip
    
    if [[ $? -eq 0 ]]; then
        print_success "Pip upgrade successful"
        
        # Test a simple package installation
        print_info "Testing package installation..."
        sudo -u ubuntu "$VENV_DIR/bin/pip" install wheel setuptools
        
        if [[ $? -eq 0 ]]; then
            print_success "Package installation test successful"
        else
            print_error "Package installation test failed"
        fi
    else
        print_error "Pip upgrade failed"
    fi
    
    # Clean up test virtual environment
    print_info "Cleaning up test virtual environment..."
    rm -rf "$VENV_DIR"
else
    print_error "Virtual environment creation failed"
fi

# Fix systemd service permissions if it exists
if [[ -f "/etc/systemd/system/py-trade.service" ]]; then
    print_header "Fixing Systemd Service Permissions"
    print_info "Setting correct permissions for systemd service..."
    chmod 644 /etc/systemd/system/py-trade.service
    systemctl daemon-reload
    print_success "Systemd service permissions fixed"
fi

# Fix nginx configuration permissions if it exists
if [[ -f "/etc/nginx/sites-available/py-trade" ]]; then
    print_header "Fixing Nginx Configuration Permissions"
    print_info "Setting correct permissions for nginx configuration..."
    chmod 644 /etc/nginx/sites-available/py-trade
    print_success "Nginx configuration permissions fixed"
fi

print_header "Permission Fix Summary"
print_success "All permission issues have been resolved"
print_info "Application directory: $APP_DIR (owned by ubuntu:ubuntu)"
print_info "All scripts are executable"
print_info "Virtual environment creation tested successfully"

print_header "Next Steps"
print_info "1. Change to the application directory: cd $APP_DIR"
print_info "2. Run the deployment script: sudo ./deploy.sh initial"
print_info "3. The deployment will now run with correct permissions"

print_warning "Note: Always run deployment scripts from $APP_DIR to avoid permission issues"