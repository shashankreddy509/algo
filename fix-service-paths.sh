#!/bin/bash

# Fix Service File Paths and Restart Service
# The issue is that the service file has wrong paths (/home/ubuntu/py-trade instead of /opt/py-trade)

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
    print_info "Run it as: sudo ./fix-service-paths.sh"
    exit 1
fi

print_header "Fixing Service File Paths - Status 203/EXEC Error"

print_info "The error 'status=203/EXEC' means systemd cannot execute the command"
print_info "This is because the service file has wrong paths: /home/ubuntu/py-trade instead of /opt/py-trade"

# Stop the service first
print_info "Stopping the service..."
systemctl stop py-trade.service

# Copy the corrected service file
print_info "Updating service file with correct paths..."
cp /opt/py-trade/py-trade.service /etc/systemd/system/py-trade.service

# Reload systemd
print_info "Reloading systemd daemon..."
systemctl daemon-reload

# Show the corrected service file
print_info "Updated service file content:"
cat /etc/systemd/system/py-trade.service

print_header "Verifying Application Setup"

# Check if the application directory and files exist
cd /opt/py-trade

if [ ! -d "venv" ]; then
    print_error "Virtual environment not found at /opt/py-trade/venv"
    print_info "Creating virtual environment..."
    python3 -m venv venv
    source venv/bin/activate
    pip install --upgrade pip
    pip install -r requirements.txt
    print_success "Virtual environment created and packages installed"
else
    print_success "Virtual environment exists"
fi

# Check if gunicorn exists
if [ ! -f "venv/bin/gunicorn" ]; then
    print_error "Gunicorn not found in virtual environment"
    print_info "Installing gunicorn..."
    source venv/bin/activate
    pip install gunicorn
    print_success "Gunicorn installed"
else
    print_success "Gunicorn found"
fi

# Check if app.py exists
if [ ! -f "app.py" ]; then
    print_error "app.py not found in /opt/py-trade"
    exit 1
else
    print_success "app.py found"
fi

# Check if .env exists
if [ ! -f ".env" ]; then
    print_warning ".env file not found"
    if [ -f ".env.example" ]; then
        print_info "Copying .env.example to .env..."
        cp .env.example .env
        print_warning "Please edit .env file with your actual configuration"
    fi
else
    print_success ".env file found"
fi

# Fix permissions
print_info "Fixing permissions..."
chown -R ubuntu:ubuntu /opt/py-trade
chmod +x /opt/py-trade/app.py

print_header "Testing Manual Application Start"

# Test if the application can start manually
print_info "Testing manual application start..."
cd /opt/py-trade
source venv/bin/activate

# Test gunicorn command
print_info "Testing gunicorn command..."
timeout 5s venv/bin/gunicorn --config gunicorn.conf.py app:app --check-config

if [ $? -eq 0 ]; then
    print_success "Gunicorn configuration test passed"
else
    print_error "Gunicorn configuration test failed"
    print_info "Checking if gunicorn.conf.py exists..."
    if [ ! -f "gunicorn.conf.py" ]; then
        print_warning "gunicorn.conf.py not found, creating basic configuration..."
        cat > gunicorn.conf.py << 'EOF'
# Gunicorn configuration file
bind = "127.0.0.1:5000"
workers = 2
worker_class = "sync"
worker_connections = 1000
timeout = 30
keepalive = 2
max_requests = 1000
max_requests_jitter = 100
preload_app = True
EOF
        print_success "Basic gunicorn.conf.py created"
    fi
fi

print_header "Starting the Service"

# Enable and start the service
print_info "Enabling service..."
systemctl enable py-trade.service

print_info "Starting service..."
systemctl start py-trade.service

# Wait a moment for the service to start
sleep 3

# Check service status
print_info "Checking service status..."
if systemctl is-active --quiet py-trade.service; then
    print_success "🎉 Service started successfully!"
    systemctl status py-trade.service --no-pager -l
    
    print_header "🚀 Application Ready!"
    print_success "Your application should now be accessible at https://algo.gshashank.com"
    
else
    print_error "Service still not starting. Checking logs..."
    journalctl -u py-trade.service -n 20 --no-pager
    
    print_info "Trying to start manually for debugging..."
    cd /opt/py-trade
    source venv/bin/activate
    python app.py &
    APP_PID=$!
    sleep 2
    
    if kill -0 $APP_PID 2>/dev/null; then
        print_success "Application starts manually - issue is with service configuration"
        kill $APP_PID
    else
        print_error "Application fails to start even manually"
    fi
fi