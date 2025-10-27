#!/bin/bash

# Fix SSL Certificate and Nginx Issues
# This script handles existing certificate expansion and nginx configuration problems

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
    print_info "Run it as: sudo ./fix-ssl-issue.sh"
    exit 1
fi

DOMAIN="algo.gshashank.com"
APP_DIR="/opt/py-trade"
NGINX_SITE="py-trade"

print_header "Fixing SSL Certificate and Nginx Issues"

# Stop nginx if running
print_info "Stopping nginx..."
systemctl stop nginx 2>/dev/null || true

# Fix the existing certificate by expanding it
print_header "Expanding Existing SSL Certificate"
print_info "Expanding certificate to include www subdomain..."

certbot certonly --standalone \
    --non-interactive \
    --agree-tos \
    --email admin@$DOMAIN \
    --domains $DOMAIN \
    --domains www.$DOMAIN \
    --expand

if [ $? -eq 0 ]; then
    print_success "SSL certificate expanded successfully"
else
    print_warning "Certificate expansion failed, trying with existing certificate only..."
    
    # Try with just the main domain
    certbot certonly --standalone \
        --non-interactive \
        --agree-tos \
        --email admin@$DOMAIN \
        --domains $DOMAIN \
        --force-renewal
    
    if [ $? -eq 0 ]; then
        print_success "SSL certificate renewed for main domain"
        WWW_DOMAIN=""
    else
        print_error "Failed to handle SSL certificate"
        exit 1
    fi
fi

# Check if www certificate exists
if [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
    # Check if certificate includes www subdomain
    if openssl x509 -in /etc/letsencrypt/live/$DOMAIN/fullchain.pem -text -noout | grep -q "www.$DOMAIN"; then
        WWW_DOMAIN="www.$DOMAIN"
        print_success "Certificate includes www subdomain"
    else
        WWW_DOMAIN=""
        print_info "Certificate is for main domain only"
    fi
else
    print_error "Certificate file not found"
    exit 1
fi

# Create proper nginx configuration
print_header "Creating Nginx Configuration"
print_info "Creating SSL-enabled nginx configuration..."

if [ -n "$WWW_DOMAIN" ]; then
    SERVER_NAMES="$DOMAIN $WWW_DOMAIN"
else
    SERVER_NAMES="$DOMAIN"
fi

cat > /etc/nginx/sites-available/$NGINX_SITE << EOF
# Nginx Configuration for Python Trading Application with SSL
# File: /etc/nginx/sites-available/py-trade

# HTTP server - redirect to HTTPS
server {
    listen 80;
    server_name $SERVER_NAMES;
    
    # Redirect HTTP to HTTPS
    return 301 https://\$server_name\$request_uri;
}

# HTTPS server
server {
    listen 443 ssl http2;
    server_name $SERVER_NAMES;

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

print_success "Nginx configuration created"

# Remove any conflicting configurations
print_header "Cleaning Up Nginx Configuration"
rm -f /etc/nginx/sites-enabled/default
rm -f /etc/nginx/sites-enabled/$NGINX_SITE

# Enable the site
ln -sf /etc/nginx/sites-available/$NGINX_SITE /etc/nginx/sites-enabled/

# Test nginx configuration
print_info "Testing nginx configuration..."
nginx -t

if [ $? -eq 0 ]; then
    print_success "Nginx configuration is valid"
else
    print_error "Nginx configuration test failed"
    print_info "Checking nginx error log..."
    tail -n 20 /var/log/nginx/error.log
    exit 1
fi

# Start nginx
print_header "Starting Nginx"
print_info "Starting nginx with SSL configuration..."
systemctl start nginx

if [ $? -eq 0 ]; then
    print_success "Nginx started successfully"
    systemctl enable nginx
    systemctl reload nginx
else
    print_error "Failed to start nginx"
    print_info "Checking nginx status..."
    systemctl status nginx --no-pager -l
    print_info "Checking nginx error log..."
    tail -n 20 /var/log/nginx/error.log
    exit 1
fi

# Verify SSL certificate
print_header "Verifying SSL Setup"
print_info "Testing SSL certificate..."

# Wait a moment for nginx to fully start
sleep 2

# Test HTTPS connection
if curl -s -I https://$DOMAIN | grep -q "HTTP/2 200"; then
    print_success "HTTPS is working correctly"
else
    print_warning "HTTPS test failed, but nginx is running"
fi

# Set up automatic certificate renewal
print_header "Setting up Automatic Certificate Renewal"
print_info "Adding certbot renewal to crontab..."

# Add renewal cron job if it doesn't exist
(crontab -l 2>/dev/null | grep -v "certbot renew"; echo "0 12 * * * /usr/bin/certbot renew --quiet --reload-nginx") | crontab -

print_success "Automatic certificate renewal configured"

print_header "SSL Setup Complete!"
print_success "Your application is now available at:"
print_info "🔒 https://$DOMAIN"
if [ -n "$WWW_DOMAIN" ]; then
    print_info "🔒 https://$WWW_DOMAIN"
fi
print_info ""
print_info "SSL certificate will automatically renew every 90 days"

# Show certificate details
print_info "Certificate details:"
certbot certificates | grep -A 10 "$DOMAIN"

print_header "Next Steps"
print_info "1. Test your application: https://$DOMAIN"
print_info "2. Update your .env file with the HTTPS URL if needed"
print_info "3. Update any API callbacks to use HTTPS URLs"