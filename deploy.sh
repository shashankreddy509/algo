#!/bin/bash
# Deployment Script for Python Trading Application on EC2
# Usage: ./deploy.sh [initial|update|restart|status|logs]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
APP_NAME="py-trade"
APP_DIR="/home/ubuntu/py-trade"
SERVICE_NAME="py-trade"
NGINX_SITE="py-trade"
VENV_DIR="$APP_DIR/venv"
BACKUP_DIR="/home/ubuntu/backups"
LOG_DIR="/var/log/gunicorn"

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

print_header() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE} $1${NC}"
    echo -e "${BLUE}================================${NC}"
}

# Function to check if running as correct user
check_user() {
    if [[ "$1" == "initial" ]] && [[ $EUID -ne 0 ]]; then
        print_error "Initial deployment must be run as root (use sudo)"
        exit 1
    elif [[ "$1" != "initial" ]] && [[ $EUID -eq 0 ]]; then
        print_error "Updates should be run as ubuntu user, not root"
        exit 1
    fi
}

# Function to create backup
create_backup() {
    if [ -d "$APP_DIR" ]; then
        print_status "Creating backup..."
        mkdir -p "$BACKUP_DIR"
        BACKUP_NAME="$APP_NAME-$(date +%Y%m%d-%H%M%S).tar.gz"
        tar -czf "$BACKUP_DIR/$BACKUP_NAME" -C "$(dirname $APP_DIR)" "$(basename $APP_DIR)" 2>/dev/null || true
        print_status "Backup created: $BACKUP_DIR/$BACKUP_NAME"
    fi
}

# Function to setup system dependencies
setup_system() {
    print_header "Setting up system dependencies"
    
    # Update system
    apt update && apt upgrade -y
    
    # Install required packages including build dependencies
    apt install -y python3 python3-pip python3-venv python3-dev \
        build-essential gcc g++ make \
        libffi-dev libssl-dev \
        nginx git curl wget htop
    
    # Create ubuntu user if not exists
    if ! id "ubuntu" &>/dev/null; then
        useradd -m -s /bin/bash ubuntu
        usermod -aG sudo ubuntu
    fi
    
    # Create log directories
    mkdir -p "$LOG_DIR"
    chown ubuntu:ubuntu "$LOG_DIR"
    
    # Setup firewall
    ufw --force enable
    ufw allow ssh
    ufw allow 'Nginx Full'
    
    print_status "System setup completed"
}

# Function to deploy application
deploy_app() {
    print_header "Deploying application"
    
    # Create application directory
    mkdir -p "$APP_DIR"
    cd "$APP_DIR"
    
    # Setup virtual environment
    if [ ! -d "$VENV_DIR" ]; then
        print_status "Creating virtual environment..."
        python3 -m venv "$VENV_DIR"
    fi
    
    # Activate virtual environment
    source "$VENV_DIR/bin/activate"
    
    # Upgrade pip
    pip install --upgrade pip
    
    # Install dependencies
    if [ -f "requirements.txt" ]; then
        print_status "Installing Python dependencies..."
        pip install -r requirements.txt
    else
        print_error "requirements.txt not found!"
        exit 1
    fi
    
    # Set permissions
    chown -R ubuntu:ubuntu "$APP_DIR"
    chmod +x "$APP_DIR"/*.sh 2>/dev/null || true
    
    print_status "Application deployment completed"
}

# Function to setup systemd service
setup_service() {
    print_header "Setting up systemd service"
    
    # Copy service file
    if [ -f "$APP_DIR/py-trade.service" ]; then
        cp "$APP_DIR/py-trade.service" "/etc/systemd/system/"
        systemctl daemon-reload
        systemctl enable "$SERVICE_NAME"
        print_status "Systemd service configured"
    else
        print_error "Service file not found: $APP_DIR/py-trade.service"
        exit 1
    fi
}

# Function to setup Nginx
setup_nginx() {
    print_header "Setting up Nginx"
    
    # Copy Nginx configuration
    if [ -f "$APP_DIR/nginx.conf" ]; then
        cp "$APP_DIR/nginx.conf" "/etc/nginx/sites-available/$NGINX_SITE"
        
        # Enable site
        ln -sf "/etc/nginx/sites-available/$NGINX_SITE" "/etc/nginx/sites-enabled/"
        
        # Remove default site
        rm -f /etc/nginx/sites-enabled/default
        
        # Test configuration
        nginx -t
        
        # Restart Nginx
        systemctl restart nginx
        systemctl enable nginx
        
        print_status "Nginx configured and started"
    else
        print_error "Nginx configuration not found: $APP_DIR/nginx.conf"
        exit 1
    fi
}

# Function to start services
start_services() {
    print_header "Starting services"
    
    # Start application service
    systemctl start "$SERVICE_NAME"
    systemctl restart nginx
    
    print_status "Services started successfully"
}

# Function to update application
update_app() {
    print_header "Updating application"
    
    # Create backup
    create_backup
    
    # Stop service
    sudo systemctl stop "$SERVICE_NAME"
    
    # Update dependencies
    cd "$APP_DIR"
    source "$VENV_DIR/bin/activate"
    pip install --upgrade pip
    pip install -r requirements.txt
    
    # Restart service
    sudo systemctl start "$SERVICE_NAME"
    sudo systemctl reload nginx
    
    print_status "Application updated successfully"
}

# Function to show status
show_status() {
    print_header "Service Status"
    
    echo -e "${BLUE}Application Service:${NC}"
    systemctl status "$SERVICE_NAME" --no-pager -l
    
    echo -e "\n${BLUE}Nginx Service:${NC}"
    systemctl status nginx --no-pager -l
    
    echo -e "\n${BLUE}Disk Usage:${NC}"
    df -h "$APP_DIR"
    
    echo -e "\n${BLUE}Memory Usage:${NC}"
    free -h
    
    echo -e "\n${BLUE}Active Connections:${NC}"
    ss -tuln | grep :443
    ss -tuln | grep :80
}

# Function to show logs
show_logs() {
    print_header "Application Logs"
    
    echo -e "${BLUE}Application Logs (last 50 lines):${NC}"
    journalctl -u "$SERVICE_NAME" -n 50 --no-pager
    
    echo -e "\n${BLUE}Nginx Error Logs (last 20 lines):${NC}"
    tail -n 20 /var/log/nginx/error.log
    
    echo -e "\n${BLUE}Gunicorn Logs (last 20 lines):${NC}"
    if [ -f "$LOG_DIR/error.log" ]; then
        tail -n 20 "$LOG_DIR/error.log"
    else
        echo "No Gunicorn logs found"
    fi
}

# Function to restart services
restart_services() {
    print_header "Restarting services"
    
    sudo systemctl restart "$SERVICE_NAME"
    sudo systemctl reload nginx
    
    print_status "Services restarted successfully"
}

# Main script logic
case "$1" in
    "initial")
        check_user "$1"
        print_header "Initial Deployment"
        setup_system
        deploy_app
        setup_service
        setup_nginx
        start_services
        show_status
        print_status "Initial deployment completed!"
        print_warning "Don't forget to:"
        echo "  1. Update domain name in nginx.conf"
        echo "  2. Configure SSL with: sudo ./ssl-setup.sh"
        echo "  3. Set up environment variables in .env file"
        echo "  4. Configure Fyers API credentials"
        ;;
    "update")
        check_user "$1"
        update_app
        ;;
    "restart")
        restart_services
        ;;
    "status")
        show_status
        ;;
    "logs")
        show_logs
        ;;
    *)
        echo "Usage: $0 {initial|update|restart|status|logs}"
        echo ""
        echo "Commands:"
        echo "  initial  - Initial deployment (run as root)"
        echo "  update   - Update application (run as ubuntu)"
        echo "  restart  - Restart services"
        echo "  status   - Show service status"
        echo "  logs     - Show application logs"
        exit 1
        ;;
esac