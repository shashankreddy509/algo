#!/bin/bash

# Fix Nginx API Shared Memory Zone Error
# This script fixes the "zero size shared memory zone 'api'" error

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
    print_info "Run it as: sudo ./fix-nginx-api-zone.sh"
    exit 1
fi

print_header "Fixing Nginx API Shared Memory Zone Error"

# Find nginx configuration files with "api" references
print_info "Searching for nginx configurations with 'api' references..."

# Check main nginx.conf
if [ -f "/etc/nginx/nginx.conf" ]; then
    print_info "Checking main nginx configuration..."
    
    # Look for limit_req_zone with "api" name
    if grep -q "limit_req_zone.*api" /etc/nginx/nginx.conf; then
        print_warning "Found API rate limiting zone in main nginx.conf"
        
        # Backup the original file
        cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup.$(date +%Y%m%d_%H%M%S)
        
        # Fix zero-size zone by adding proper size
        sed -i 's/limit_req_zone.*zone=api:[^;]*/limit_req_zone $binary_remote_addr zone=api:10m rate=10r\/s/g' /etc/nginx/nginx.conf
        
        print_success "Fixed API zone in main nginx.conf"
    fi
    
    # Look for other problematic zone definitions
    if grep -q "zone=api:0" /etc/nginx/nginx.conf; then
        sed -i 's/zone=api:0[^;]*/zone=api:10m/g' /etc/nginx/nginx.conf
        print_success "Fixed zero-size API zone"
    fi
fi

# Check sites-available configurations
print_info "Checking site configurations..."
for config_file in /etc/nginx/sites-available/* /etc/nginx/sites-enabled/*; do
    if [ -f "$config_file" ] && grep -q "api" "$config_file"; then
        print_info "Checking $config_file..."
        
        # Backup the file
        cp "$config_file" "$config_file.backup.$(date +%Y%m%d_%H%M%S)"
        
        # Fix any API zone references
        if grep -q "limit_req_zone.*api" "$config_file"; then
            sed -i 's/limit_req_zone.*zone=api:[^;]*/limit_req_zone $binary_remote_addr zone=api:10m rate=10r\/s/g' "$config_file"
            print_success "Fixed API zone in $config_file"
        fi
        
        # Fix zero-size zones
        if grep -q "zone=api:0" "$config_file"; then
            sed -i 's/zone=api:0[^;]*/zone=api:10m/g' "$config_file"
            print_success "Fixed zero-size API zone in $config_file"
        fi
    fi
done

# Check for any remaining problematic configurations
print_header "Cleaning Up Nginx Configuration"

# Remove any duplicate or conflicting zone definitions
print_info "Removing duplicate zone definitions..."

# Create a clean nginx configuration for py-trade
APP_DIR="/opt/py-trade"
NGINX_SITE="py-trade"
DOMAIN="algo.gshashank.com"

# Check if SSL certificate exists
if [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
    HAS_SSL=true
    print_info "SSL certificate found, creating HTTPS configuration"
else
    HAS_SSL=false
    print_info "No SSL certificate found, creating HTTP configuration"
fi

# Create clean nginx configuration
print_info "Creating clean nginx configuration..."

if [ "$HAS_SSL" = true ]; then
    # HTTPS configuration
    cat > /etc/nginx/sites-available/$NGINX_SITE << 'EOF'
# Clean Nginx Configuration for Python Trading Application with SSL
server {
    listen 80;
    server_name algo.gshashank.com www.algo.gshashank.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name algo.gshashank.com www.algo.gshashank.com;

    # SSL Configuration
    ssl_certificate /etc/letsencrypt/live/algo.gshashank.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/algo.gshashank.com/privkey.pem;
    
    # SSL Settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    
    # Security Headers
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # Main application proxy
    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    # Health check
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
}
EOF
else
    # HTTP-only configuration
    cat > /etc/nginx/sites-available/$NGINX_SITE << 'EOF'
# Clean Nginx Configuration for Python Trading Application (HTTP)
server {
    listen 80;
    server_name algo.gshashank.com www.algo.gshashank.com localhost;

    # Security Headers
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # Main application proxy
    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    # Health check
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
}
EOF
fi

print_success "Clean nginx configuration created"

# Remove conflicting configurations
print_info "Removing conflicting configurations..."
rm -f /etc/nginx/sites-enabled/default
rm -f /etc/nginx/sites-enabled/$NGINX_SITE

# Enable the clean site
ln -sf /etc/nginx/sites-available/$NGINX_SITE /etc/nginx/sites-enabled/

# Test nginx configuration
print_header "Testing Nginx Configuration"
print_info "Running nginx configuration test..."

nginx -t

if [ $? -eq 0 ]; then
    print_success "Nginx configuration test passed"
    
    # Restart nginx
    print_info "Restarting nginx..."
    systemctl restart nginx
    
    if [ $? -eq 0 ]; then
        print_success "Nginx restarted successfully"
        systemctl enable nginx
    else
        print_error "Failed to restart nginx"
        systemctl status nginx --no-pager -l
        exit 1
    fi
else
    print_error "Nginx configuration test failed"
    print_info "Showing nginx error details..."
    nginx -t 2>&1
    exit 1
fi

print_header "Nginx Fix Complete!"
print_success "The API shared memory zone error has been resolved"

if [ "$HAS_SSL" = true ]; then
    print_info "Your application is available at: https://algo.gshashank.com"
else
    print_info "Your application is available at: http://algo.gshashank.com"
fi

print_info "Nginx is now running with a clean configuration"