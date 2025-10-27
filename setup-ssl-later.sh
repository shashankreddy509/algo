#!/bin/bash

# SSL Setup Script for py-trade Application
# Run this script AFTER you have:
# 1. A registered domain name pointing to your EC2 instance
# 2. The application running successfully on HTTP

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
    print_info "Run it as: sudo ./setup-ssl-later.sh your-domain.com"
    exit 1
fi

# Check if domain is provided
if [ -z "$1" ]; then
    print_error "Domain name is required"
    print_info "Usage: sudo ./setup-ssl-later.sh your-domain.com"
    print_info "Example: sudo ./setup-ssl-later.sh mytrading.example.com"
    exit 1
fi

DOMAIN="$1"
APP_DIR="/opt/py-trade"
NGINX_SITE="py-trade"

print_header "SSL Setup for py-trade Application"
print_info "Domain: $DOMAIN"

# Verify domain points to this server
print_header "Verifying Domain Configuration"
print_info "Checking if $DOMAIN points to this server..."

SERVER_IP=$(curl -s ifconfig.me)
DOMAIN_IP=$(dig +short "$DOMAIN" | tail -n1)

if [ "$SERVER_IP" = "$DOMAIN_IP" ]; then
    print_success "Domain $DOMAIN correctly points to this server ($SERVER_IP)"
else
    print_warning "Domain $DOMAIN points to $DOMAIN_IP, but this server is $SERVER_IP"
    print_info "Please ensure your domain's A record points to $SERVER_IP"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Install Certbot if not already installed
print_header "Installing Certbot"
if ! command -v certbot &> /dev/null; then
    print_info "Installing Certbot..."
    apt update
    apt install -y certbot python3-certbot-nginx
    print_success "Certbot installed"
else
    print_success "Certbot already installed"
fi

# Stop nginx temporarily
print_header "Preparing for Certificate Generation"
print_info "Stopping nginx temporarily..."
systemctl stop nginx

# Generate SSL certificate
print_header "Generating SSL Certificate"
print_info "Requesting SSL certificate for $DOMAIN..."

certbot certonly --standalone \
    --non-interactive \
    --agree-tos \
    --email admin@$DOMAIN \
    --domains $DOMAIN \
    --domains www.$DOMAIN

if [ $? -eq 0 ]; then
    print_success "SSL certificate generated successfully"
else
    print_error "Failed to generate SSL certificate"
    print_info "Starting nginx in HTTP mode..."
    systemctl start nginx
    exit 1
fi

# Update nginx configuration with SSL
print_header "Updating Nginx Configuration"
print_info "Updating nginx configuration with SSL settings..."

# Create SSL-enabled nginx configuration
cat > /etc/nginx/sites-available/$NGINX_SITE << EOF
# Nginx Configuration for Python Trading Application with SSL
# File: /etc/nginx/sites-available/py-trade

# HTTP server - redirect to HTTPS
server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN;
    
    # Redirect HTTP to HTTPS
    return 301 https://\$server_name\$request_uri;
}

# HTTPS server
server {
    listen 443 ssl http2;
    server_name $DOMAIN www.$DOMAIN;

    # SSL Configuration (Let's Encrypt)
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    
    # SSL Security Settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-SHA384;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    
    # Security Headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # Gzip Compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
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

    # Main application proxy
    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$server_name;
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # Buffer settings
        proxy_buffering on;
        proxy_buffer_size 128k;
        proxy_buffers 4 256k;
        proxy_busy_buffers_size 256k;
    }

    # Static files
    location /static/ {
        alias $APP_DIR/static/;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    # Health check endpoint
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }

    # Security: Block access to sensitive files
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }

    location ~ \.(env|log|db)$ {
        deny all;
        access_log off;
        log_not_found off;
    }
}
EOF

# Test nginx configuration
print_info "Testing nginx configuration..."
nginx -t

if [ $? -eq 0 ]; then
    print_success "Nginx configuration is valid"
else
    print_error "Nginx configuration test failed"
    exit 1
fi

# Start nginx
print_info "Starting nginx with SSL configuration..."
systemctl start nginx
systemctl reload nginx

if [ $? -eq 0 ]; then
    print_success "Nginx started successfully with SSL"
else
    print_error "Failed to start nginx"
    exit 1
fi

# Set up automatic certificate renewal
print_header "Setting up Automatic Certificate Renewal"
print_info "Adding certbot renewal to crontab..."

# Add renewal cron job if it doesn't exist
(crontab -l 2>/dev/null; echo "0 12 * * * /usr/bin/certbot renew --quiet --reload-nginx") | crontab -

print_success "Automatic certificate renewal configured"

print_header "SSL Setup Complete!"
print_success "Your application is now available at:"
print_info "🔒 https://$DOMAIN"
print_info "🔒 https://www.$DOMAIN"
print_info ""
print_info "SSL certificate will automatically renew every 90 days"
print_info "Certificate expires: $(openssl x509 -enddate -noout -in /etc/letsencrypt/live/$DOMAIN/cert.pem | cut -d= -f2)"

print_header "Next Steps"
print_info "1. Test your application: https://$DOMAIN"
print_info "2. Update your .env file with the HTTPS URL if needed"
print_info "3. Update any API callbacks to use HTTPS URLs"
print_info "4. Monitor certificate renewal: sudo certbot certificates"