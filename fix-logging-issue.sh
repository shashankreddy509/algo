#!/bin/bash

# Fix Gunicorn Logging Permission Issue
# This script fixes the read-only file system error for gunicorn logs

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

log_header "Fixing Gunicorn Logging Permission Issue"

# Step 1: Stop the service
log_info "Stopping py-trade service..."
systemctl stop py-trade.service || true

# Step 2: Update gunicorn configuration to use stdout/stderr
log_info "Updating gunicorn configuration..."
cd "$APP_DIR"

cat > gunicorn.conf.py << 'EOF'
# Gunicorn Configuration for Production Deployment
# File: gunicorn.conf.py

import multiprocessing

# Server socket
bind = "127.0.0.1:5000"
backlog = 2048

# Worker processes
workers = multiprocessing.cpu_count() * 2 + 1
worker_class = "sync"
worker_connections = 1000
timeout = 30
keepalive = 2

# Restart workers after this many requests, to help prevent memory leaks
max_requests = 1000
max_requests_jitter = 100

# Load application code before the worker processes are forked
preload_app = True

# Logging - Use stdout/stderr instead of files to avoid permission issues
accesslog = "-"  # stdout
errorlog = "-"   # stderr
loglevel = "info"
access_log_format = '%(h)s %(l)s %(u)s %(t)s "%(r)s" %(s)s %(b)s "%(f)s" "%(a)s" %(D)s'

# Process naming
proc_name = "py-trade"

# Daemon mode (set to False when using systemd)
daemon = False

# User and group to run as
user = "ubuntu"
group = "ubuntu"

# Temp directory
tmp_upload_dir = None

# SSL (if needed)
# keyfile = "/path/to/keyfile"
# certfile = "/path/to/certfile"
EOF

log_success "Updated gunicorn.conf.py to use stdout/stderr logging"

# Step 3: Fix file permissions
log_info "Fixing file permissions..."
chown -R ubuntu:ubuntu "$APP_DIR"
chmod 644 gunicorn.conf.py

# Step 4: Test gunicorn configuration
log_info "Testing gunicorn configuration..."
cd "$APP_DIR"
source venv/bin/activate
sudo -u ubuntu venv/bin/gunicorn --config gunicorn.conf.py --check-config app:app || {
    log_error "Gunicorn configuration test failed"
    exit 1
}
log_success "Gunicorn configuration is valid"

# Step 5: Test manual start (brief test)
log_info "Testing manual application start..."
timeout 3s sudo -u ubuntu venv/bin/gunicorn --config gunicorn.conf.py app:app &
MANUAL_PID=$!
sleep 2

# Check if process is running
if kill -0 $MANUAL_PID 2>/dev/null; then
    log_success "Manual start test successful"
    kill $MANUAL_PID 2>/dev/null || true
    wait $MANUAL_PID 2>/dev/null || true
else
    log_warning "Manual start test completed (process may have exited normally)"
fi

# Step 6: Reload systemd and start service
log_info "Reloading systemd daemon..."
systemctl daemon-reload

log_info "Starting py-trade service..."
systemctl start py-trade.service

# Step 7: Check service status
sleep 3
log_info "Checking service status..."
if systemctl is-active --quiet py-trade.service; then
    log_success "🎉 py-trade service is running successfully!"
    
    # Show service status
    systemctl status py-trade.service --no-pager -l
    
    # Enable service for auto-start
    log_info "Enabling service to start on boot..."
    systemctl enable py-trade.service
    log_success "Service enabled for auto-start"
    
    log_header "Service Fix Complete!"
    log_success "✅ Logging issue resolved"
    log_success "✅ py-trade service is running"
    log_success "✅ Application should be accessible at https://algo.gshashank.com"
    log_info "View logs with: journalctl -u py-trade.service -f"
    
else
    log_error "Service failed to start. Checking logs..."
    journalctl -u py-trade.service --no-pager -l -n 20
    
    log_info "Service status:"
    systemctl status py-trade.service --no-pager -l || true
    
    exit 1
fi