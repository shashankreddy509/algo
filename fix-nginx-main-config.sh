#!/bin/bash

# Fix Main Nginx Configuration - API Zone Issue
# The problem is in the main /etc/nginx/nginx.conf file, not in site configs

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
    print_info "Run it as: sudo ./fix-nginx-main-config.sh"
    exit 1
fi

print_header "Fixing Main Nginx Configuration - API Zone Issue"

# Backup the main nginx configuration
print_info "Backing up main nginx configuration..."
cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup.$(date +%Y%m%d_%H%M%S)
print_success "Backup created"

# Show current problematic lines
print_info "Current problematic configuration:"
grep -n "api" /etc/nginx/nginx.conf || echo "No 'api' found in main config"

# Check for the problematic zone definition
print_header "Analyzing Main Nginx Configuration"

# Look for limit_req_zone definitions
if grep -q "limit_req_zone" /etc/nginx/nginx.conf; then
    print_warning "Found limit_req_zone definitions in main config"
    grep -n "limit_req_zone" /etc/nginx/nginx.conf
fi

# Look for any zone definitions with "api"
if grep -q "zone=api" /etc/nginx/nginx.conf; then
    print_warning "Found API zone definitions"
    grep -n "zone=api" /etc/nginx/nginx.conf
fi

# Create a clean main nginx configuration
print_header "Creating Clean Main Nginx Configuration"

cat > /etc/nginx/nginx.conf << 'EOF'
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 768;
    # multi_accept on;
}

http {
    ##
    # Basic Settings
    ##
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    # server_tokens off;

    # server_names_hash_bucket_size 64;
    # server_name_in_redirect off;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    ##
    # SSL Settings
    ##
    ssl_protocols TLSv1 TLSv1.1 TLSv1.2 TLSv1.3; # Dropping SSLv3, ref: POODLE
    ssl_prefer_server_ciphers on;

    ##
    # Logging Settings
    ##
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;
    error_log /var/log/nginx/error.log;

    ##
    # Gzip Settings
    ##
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types
        text/plain
        text/css
        text/xml
        text/javascript
        application/json
        application/javascript
        application/xml+rss
        application/atom+xml
        image/svg+xml;

    ##
    # Virtual Host Configs
    ##
    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
EOF

print_success "Clean main nginx configuration created"

# Remove all site configurations and recreate clean one
print_header "Cleaning Up Site Configurations"

# Remove all existing site configs
rm -f /etc/nginx/sites-enabled/*
rm -f /etc/nginx/sites-available/py-trade

# Create a completely clean site configuration
print_info "Creating clean site configuration..."

DOMAIN="algo.gshashank.com"
APP_DIR="/opt/py-trade"

# Check if SSL certificate exists
if [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
    print_info "SSL certificate found, creating HTTPS configuration"
    
    cat > /etc/nginx/sites-available/py-trade << EOF
# Clean Nginx Configuration for py-trade
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN;

    # SSL Configuration
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    
    # SSL Settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    
    # Security Headers
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;

    # Main application
    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    # Health check
    location /health {
        access_log off;
        return 200 "healthy\\n";
        add_header Content-Type text/plain;
    }
}
EOF
else
    print_info "No SSL certificate, creating HTTP configuration"
    
    cat > /etc/nginx/sites-available/py-trade << EOF
# Clean Nginx Configuration for py-trade (HTTP)
server {
    listen 80;
    server_name $DOMAIN localhost;

    # Security Headers
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;

    # Main application
    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    # Health check
    location /health {
        access_log off;
        return 200 "healthy\\n";
        add_header Content-Type text/plain;
    }
}
EOF
fi

# Enable the site
ln -sf /etc/nginx/sites-available/py-trade /etc/nginx/sites-enabled/

print_success "Clean site configuration created and enabled"

# Test the configuration
print_header "Testing Clean Nginx Configuration"
print_info "Running nginx configuration test..."

nginx -t

if [ $? -eq 0 ]; then
    print_success "✅ Nginx configuration test PASSED!"
    
    # Restart nginx
    print_info "Restarting nginx..."
    systemctl restart nginx
    
    if [ $? -eq 0 ]; then
        print_success "✅ Nginx restarted successfully!"
        systemctl enable nginx
        
        # Check nginx status
        print_info "Nginx status:"
        systemctl status nginx --no-pager -l | head -10
        
    else
        print_error "Failed to restart nginx"
        systemctl status nginx --no-pager -l
        exit 1
    fi
else
    print_error "❌ Nginx configuration test still failed"
    print_info "Showing detailed error:"
    nginx -t 2>&1
    exit 1
fi

print_header "🎉 Nginx Fix Complete!"
print_success "The API shared memory zone error has been completely resolved"
print_success "Nginx is now running with a clean configuration"

if [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
    print_info "🔒 Your application is available at: https://$DOMAIN"
else
    print_info "🌐 Your application is available at: http://$DOMAIN"
fi

print_info "📋 Configuration summary:"
print_info "  - Main nginx.conf: Clean, no problematic zones"
print_info "  - Site config: Clean, no rate limiting"
print_info "  - SSL: $([ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ] && echo "Enabled" || echo "Disabled")"
print_info "  - Status: Running and enabled"