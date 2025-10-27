#!/bin/bash

# Debug py-trade Service Issues
# This script helps diagnose and fix common service startup problems

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
    print_info "Run it as: sudo ./debug-service.sh"
    exit 1
fi

print_header "Debugging py-trade Service Issues"

# Check service status
print_info "Current service status:"
systemctl status py-trade.service --no-pager -l

print_header "Service Logs (Last 50 lines)"
journalctl -u py-trade.service -n 50 --no-pager

print_header "Checking Service Configuration"

# Check if service file exists
if [ -f "/etc/systemd/system/py-trade.service" ]; then
    print_success "Service file exists"
    print_info "Service file content:"
    cat /etc/systemd/system/py-trade.service
else
    print_error "Service file not found at /etc/systemd/system/py-trade.service"
    
    # Check if it's in the project directory
    if [ -f "/opt/py-trade/py-trade.service" ]; then
        print_info "Found service file in project directory, copying to systemd..."
        cp /opt/py-trade/py-trade.service /etc/systemd/system/
        systemctl daemon-reload
        print_success "Service file copied and systemd reloaded"
    else
        print_error "Service file not found in project directory either"
        exit 1
    fi
fi

print_header "Checking Application Directory and Files"

# Check application directory
if [ -d "/opt/py-trade" ]; then
    print_success "Application directory exists: /opt/py-trade"
    
    # Check key files
    cd /opt/py-trade
    
    if [ -f "app.py" ]; then
        print_success "app.py found"
    else
        print_error "app.py not found"
    fi
    
    if [ -f "requirements.txt" ]; then
        print_success "requirements.txt found"
    else
        print_error "requirements.txt not found"
    fi
    
    if [ -f ".env" ]; then
        print_success ".env file found"
    else
        print_warning ".env file not found - this might cause issues"
    fi
    
    # Check virtual environment
    if [ -d "venv" ]; then
        print_success "Virtual environment found"
        
        # Check if Python executable exists
        if [ -f "venv/bin/python" ]; then
            print_success "Python executable found in venv"
        else
            print_error "Python executable not found in venv"
        fi
        
        # Check if gunicorn is installed
        if [ -f "venv/bin/gunicorn" ]; then
            print_success "Gunicorn found in venv"
        else
            print_error "Gunicorn not found in venv"
        fi
    else
        print_error "Virtual environment not found"
    fi
    
else
    print_error "Application directory not found: /opt/py-trade"
    exit 1
fi

print_header "Checking Permissions"
ls -la /opt/py-trade/ | head -10

print_header "Testing Manual Application Start"
print_info "Attempting to start the application manually..."

cd /opt/py-trade

# Test if we can activate the virtual environment
if [ -f "venv/bin/activate" ]; then
    print_info "Activating virtual environment..."
    source venv/bin/activate
    
    # Test Python import
    print_info "Testing Python imports..."
    python -c "
import sys
print(f'Python version: {sys.version}')
try:
    import flask
    print(f'Flask version: {flask.__version__}')
except ImportError as e:
    print(f'Flask import error: {e}')

try:
    import gunicorn
    print(f'Gunicorn available')
except ImportError as e:
    print(f'Gunicorn import error: {e}')
"

    # Test if app.py can be imported
    print_info "Testing app.py import..."
    python -c "
try:
    import app
    print('✅ app.py imported successfully')
except Exception as e:
    print(f'❌ Error importing app.py: {e}')
    import traceback
    traceback.print_exc()
"

else
    print_error "Cannot activate virtual environment"
fi

print_header "Suggested Fixes"

print_info "Based on the diagnosis, here are potential solutions:"
print_info "1. If virtual environment is missing: Run 'python3 -m venv venv' in /opt/py-trade"
print_info "2. If packages are missing: Run 'pip install -r requirements.txt' in the venv"
print_info "3. If .env is missing: Copy .env.example to .env and configure it"
print_info "4. If permissions are wrong: Run 'chown -R ubuntu:ubuntu /opt/py-trade'"
print_info "5. If service file is wrong: Check ExecStart path and User in service file"

print_header "Quick Fix Attempt"
print_info "Attempting automatic fixes..."

# Fix permissions
chown -R ubuntu:ubuntu /opt/py-trade
chmod +x /opt/py-trade/app.py

# Reload systemd and try to start
systemctl daemon-reload

print_info "Attempting to start service again..."
systemctl start py-trade.service

sleep 2

if systemctl is-active --quiet py-trade.service; then
    print_success "🎉 Service started successfully!"
    systemctl status py-trade.service --no-pager -l
else
    print_error "Service still failing. Check the logs above for specific errors."
    print_info "Run 'journalctl -u py-trade.service -f' to see real-time logs"
fi