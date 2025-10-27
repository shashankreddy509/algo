#!/bin/bash

# Fix py-trade Service 203/EXEC Error
# This script diagnoses and fixes the systemd service execution error

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
SERVICE_FILE="/etc/systemd/system/py-trade.service"

log_header "Diagnosing py-trade Service 203/EXEC Error"

# Step 1: Check application directory
log_info "Checking application directory..."
if [ ! -d "$APP_DIR" ]; then
    log_error "Application directory $APP_DIR does not exist!"
    log_info "Creating application directory..."
    mkdir -p "$APP_DIR"
    log_success "Created $APP_DIR"
else
    log_success "Application directory exists: $APP_DIR"
fi

# Step 2: Check if app.py exists
log_info "Checking for app.py..."
if [ ! -f "$APP_DIR/app.py" ]; then
    log_error "app.py not found in $APP_DIR"
    log_info "You need to copy your application files to $APP_DIR"
    exit 1
else
    log_success "app.py found"
fi

# Step 3: Check virtual environment
log_info "Checking virtual environment..."
if [ ! -d "$VENV_DIR" ]; then
    log_warning "Virtual environment not found. Creating..."
    cd "$APP_DIR"
    python3 -m venv venv
    log_success "Created virtual environment"
else
    log_success "Virtual environment exists"
fi

# Step 4: Check Python executable in venv
log_info "Checking Python executable in virtual environment..."
if [ ! -f "$VENV_DIR/bin/python" ]; then
    log_error "Python executable not found in virtual environment"
    log_info "Recreating virtual environment..."
    rm -rf "$VENV_DIR"
    cd "$APP_DIR"
    python3 -m venv venv
    log_success "Recreated virtual environment"
else
    log_success "Python executable found in venv"
fi

# Step 5: Activate virtual environment and install dependencies
log_info "Installing dependencies..."
cd "$APP_DIR"
source "$VENV_DIR/bin/activate"

# Upgrade pip first
pip install --upgrade pip

# Check if requirements.txt exists
if [ -f "requirements.txt" ]; then
    log_info "Installing from requirements.txt..."
    pip install -r requirements.txt
    log_success "Dependencies installed from requirements.txt"
else
    log_warning "requirements.txt not found. Installing essential packages..."
    pip install flask gunicorn python-dotenv requests aiohttp
    log_success "Essential packages installed"
fi

# Step 6: Verify gunicorn installation
log_info "Verifying gunicorn installation..."
if [ ! -f "$VENV_DIR/bin/gunicorn" ]; then
    log_warning "Gunicorn not found. Installing..."
    pip install gunicorn
    log_success "Gunicorn installed"
else
    log_success "Gunicorn found: $VENV_DIR/bin/gunicorn"
fi

# Step 7: Test gunicorn executable
log_info "Testing gunicorn executable..."
if "$VENV_DIR/bin/gunicorn" --version > /dev/null 2>&1; then
    GUNICORN_VERSION=$("$VENV_DIR/bin/gunicorn" --version)
    log_success "Gunicorn is working: $GUNICORN_VERSION"
else
    log_error "Gunicorn executable test failed"
    exit 1
fi

# Step 8: Check gunicorn.conf.py
log_info "Checking gunicorn configuration..."
if [ ! -f "$APP_DIR/gunicorn.conf.py" ]; then
    log_warning "gunicorn.conf.py not found. Creating default configuration..."
    cat > "$APP_DIR/gunicorn.conf.py" << 'EOF'
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
user = "ubuntu"
group = "ubuntu"
tmp_upload_dir = None
logfile = "/var/log/gunicorn/py-trade.log"
loglevel = "info"
access_log_format = '%(h)s %(l)s %(u)s %(t)s "%(r)s" %(s)s %(b)s "%(f)s" "%(a)s"'
EOF
    log_success "Created gunicorn.conf.py"
else
    log_success "gunicorn.conf.py exists"
fi

# Step 9: Create log directory
log_info "Creating log directory..."
mkdir -p /var/log/gunicorn
chown ubuntu:ubuntu /var/log/gunicorn
log_success "Log directory created"

# Step 10: Fix file permissions
log_info "Fixing file permissions..."
chown -R ubuntu:ubuntu "$APP_DIR"
chmod +x "$VENV_DIR/bin/gunicorn"
chmod +x "$VENV_DIR/bin/python"
log_success "File permissions fixed"

# Step 11: Test manual application start
log_info "Testing manual application start..."
cd "$APP_DIR"
sudo -u ubuntu "$VENV_DIR/bin/python" -c "import app; print('✅ App imports successfully')" || {
    log_error "App import failed. Check your Python code."
    exit 1
}

# Test gunicorn with the app
log_info "Testing gunicorn with the application..."
timeout 5s sudo -u ubuntu "$VENV_DIR/bin/gunicorn" --config gunicorn.conf.py --check-config app:app || {
    log_error "Gunicorn configuration test failed"
    exit 1
}
log_success "Gunicorn configuration is valid"

# Step 12: Update service file with correct paths
log_info "Updating service file..."
cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Python Trading Application
Documentation=https://github.com/your-username/py-trade
After=network.target
Wants=network.target

[Service]
Type=notify
User=ubuntu
Group=ubuntu
WorkingDirectory=$APP_DIR
Environment=PATH=$VENV_DIR/bin
Environment=PYTHONPATH=$APP_DIR
ExecStart=$VENV_DIR/bin/gunicorn --config gunicorn.conf.py app:app
ExecReload=/bin/kill -s HUP \$MAINPID
KillMode=mixed
TimeoutStopSec=5
PrivateTmp=true
Restart=on-failure
RestartSec=10

# Security settings
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$APP_DIR
ReadWritePaths=/var/log/gunicorn
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true

[Install]
WantedBy=multi-user.target
EOF

log_success "Service file updated"

# Step 13: Reload systemd and restart service
log_info "Reloading systemd daemon..."
systemctl daemon-reload
log_success "Systemd daemon reloaded"

log_info "Stopping existing service..."
systemctl stop py-trade.service || true

log_info "Starting py-trade service..."
systemctl start py-trade.service

# Step 14: Check service status
sleep 3
log_info "Checking service status..."
if systemctl is-active --quiet py-trade.service; then
    log_success "🎉 py-trade service is running successfully!"
    systemctl status py-trade.service --no-pager -l
    
    log_info "Enabling service to start on boot..."
    systemctl enable py-trade.service
    log_success "Service enabled for auto-start"
    
    log_header "Service Fix Complete!"
    log_success "✅ py-trade service is now running"
    log_success "✅ Application should be accessible at https://algo.gshashank.com"
    log_info "Check logs with: journalctl -u py-trade.service -f"
else
    log_error "Service failed to start. Checking logs..."
    journalctl -u py-trade.service --no-pager -l -n 20
    exit 1
fi