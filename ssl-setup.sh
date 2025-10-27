#!/bin/bash
# SSL Setup Script for Let's Encrypt
# Run this script on your EC2 instance after domain setup

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
DOMAIN="your-domain.com"
EMAIL="your-email@example.com"
WEBROOT="/var/www/html"

echo -e "${GREEN}Starting SSL setup for $DOMAIN${NC}"

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root (use sudo)"
   exit 1
fi

# Update system packages
print_status "Updating system packages..."
apt update && apt upgrade -y

# Install Certbot
print_status "Installing Certbot..."
apt install -y certbot python3-certbot-nginx

# Stop Nginx temporarily
print_status "Stopping Nginx temporarily..."
systemctl stop nginx

# Obtain SSL certificate
print_status "Obtaining SSL certificate for $DOMAIN..."
certbot certonly --standalone \
    --email $EMAIL \
    --agree-tos \
    --no-eff-email \
    --domains $DOMAIN \
    --domains www.$DOMAIN

# Start Nginx
print_status "Starting Nginx..."
systemctl start nginx

# Test Nginx configuration
print_status "Testing Nginx configuration..."
nginx -t

if [ $? -eq 0 ]; then
    print_status "Nginx configuration is valid"
    systemctl reload nginx
else
    print_error "Nginx configuration test failed"
    exit 1
fi

# Set up automatic renewal
print_status "Setting up automatic certificate renewal..."
cat > /etc/cron.d/certbot << EOF
# Renew Let's Encrypt certificates twice daily
0 */12 * * * root certbot renew --quiet --post-hook "systemctl reload nginx"
EOF

# Test certificate renewal
print_status "Testing certificate renewal..."
certbot renew --dry-run

# Create SSL renewal script
cat > /usr/local/bin/ssl-renew.sh << 'EOF'
#!/bin/bash
# SSL Certificate Renewal Script

LOG_FILE="/var/log/ssl-renewal.log"
DATE=$(date '+%Y-%m-%d %H:%M:%S')

echo "[$DATE] Starting certificate renewal check..." >> $LOG_FILE

# Renew certificates
certbot renew --quiet --post-hook "systemctl reload nginx" >> $LOG_FILE 2>&1

if [ $? -eq 0 ]; then
    echo "[$DATE] Certificate renewal completed successfully" >> $LOG_FILE
else
    echo "[$DATE] Certificate renewal failed" >> $LOG_FILE
    # Send notification (optional)
    # mail -s "SSL Certificate Renewal Failed" admin@example.com < $LOG_FILE
fi
EOF

chmod +x /usr/local/bin/ssl-renew.sh

# Display certificate information
print_status "SSL Certificate Information:"
certbot certificates

print_status "SSL setup completed successfully!"
print_warning "Please update the following in your Nginx configuration:"
echo "  - Replace 'your-domain.com' with your actual domain"
echo "  - Update SSL certificate paths if different"
echo "  - Test your SSL configuration at: https://www.ssllabs.com/ssltest/"

print_status "Certificate will auto-renew every 12 hours via cron job"
print_status "Manual renewal command: sudo certbot renew"
print_status "Check renewal status: sudo certbot certificates"

# Security recommendations
print_warning "Security Recommendations:"
echo "  1. Enable UFW firewall: sudo ufw enable"
echo "  2. Configure fail2ban: sudo apt install fail2ban"
echo "  3. Regular security updates: sudo apt update && sudo apt upgrade"
echo "  4. Monitor SSL certificate expiry"
echo "  5. Use strong passwords and SSH keys only"

print_status "SSL setup script completed!"