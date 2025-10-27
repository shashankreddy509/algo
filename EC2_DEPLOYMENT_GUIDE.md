# EC2 Deployment Guide for Python Trading Application

## 🚀 Complete Setup Guide for AWS EC2

### 1. EC2 Instance Setup

#### Launch EC2 Instance
```bash
# Recommended Instance Type: t3.small or t3.medium
# Operating System: Ubuntu 22.04 LTS
# Storage: 20GB GP3 SSD minimum
```

#### Security Group Configuration
```bash
# Inbound Rules:
- SSH (22): Your IP address
- HTTP (80): 0.0.0.0/0
- HTTPS (443): 0.0.0.0/0
- Custom TCP (5000): 0.0.0.0/0 (for development, remove in production)

# Outbound Rules:
- All traffic: 0.0.0.0/0
```

### 2. Initial Server Setup

#### Connect to EC2 Instance
```bash
ssh -i your-key.pem ubuntu@your-ec2-public-ip
```

#### Update System
```bash
sudo apt update && sudo apt upgrade -y
```

#### Install Required Software
```bash
# Update system packages
sudo apt update && sudo apt upgrade -y

# Install Python and build dependencies
sudo apt install -y python3 python3-pip python3-venv python3-dev \
    build-essential gcc g++ make \
    libffi-dev libssl-dev \
    nginx git curl wget htop

# Install additional security tools
sudo apt install -y ufw fail2ban

# Install supervisor for process management
sudo apt install supervisor -y
```

### 3. Application Deployment

#### Clone Repository
```bash
cd /home/ubuntu
git clone <your-repository-url> py-trade
cd py-trade
```

#### Create Virtual Environment
```bash
python3.11 -m venv venv
source venv/bin/activate
```

#### Install Dependencies
```bash
pip install -r requirements.txt
pip install gunicorn  # Production WSGI server
```

#### Setup Environment Variables
```bash
# Create .env file
nano .env
```

Add your environment variables:
```env
FLASK_SECRET_KEY=your-super-secret-key-here
FYERS_CLIENT_ID=your-fyers-client-id
FYERS_SECRET_KEY=your-fyers-secret-key
FYERS_REDIRECT_URI=https://your-domain.com/auth/callback
FLASK_ENV=production
```

### 4. Production Configuration

#### Create Gunicorn Configuration
```bash
nano gunicorn.conf.py
```

```python
# gunicorn.conf.py
bind = "127.0.0.1:5000"
workers = 2
worker_class = "sync"
worker_connections = 1000
timeout = 30
keepalive = 2
max_requests = 1000
max_requests_jitter = 100
preload_app = True
```

#### Create Systemd Service
```bash
sudo nano /etc/systemd/system/py-trade.service
```

```ini
[Unit]
Description=Python Trading Application
After=network.target

[Service]
User=ubuntu
Group=ubuntu
WorkingDirectory=/home/ubuntu/py-trade
Environment=PATH=/home/ubuntu/py-trade/venv/bin
ExecStart=/home/ubuntu/py-trade/venv/bin/gunicorn --config gunicorn.conf.py app:app
ExecReload=/bin/kill -s HUP $MAINPID
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
```

#### Enable and Start Service
```bash
sudo systemctl daemon-reload
sudo systemctl enable py-trade
sudo systemctl start py-trade
sudo systemctl status py-trade
```

### 5. Nginx Configuration

#### Create Nginx Site Configuration
```bash
sudo nano /etc/nginx/sites-available/py-trade
```

```nginx
server {
    listen 80;
    server_name your-domain.com www.your-domain.com;

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    # Static files (if any)
    location /static {
        alias /home/ubuntu/py-trade/static;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
```

#### Enable Site
```bash
sudo ln -s /etc/nginx/sites-available/py-trade /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx
```

### 6. SSL/HTTPS Setup with Let's Encrypt

#### Install Certbot
```bash
sudo apt install certbot python3-certbot-nginx -y
```

#### Obtain SSL Certificate
```bash
sudo certbot --nginx -d your-domain.com -d www.your-domain.com
```

#### Auto-renewal Setup
```bash
sudo crontab -e
# Add this line:
0 12 * * * /usr/bin/certbot renew --quiet
```

### 7. Database Setup (if needed)

#### Create Database Directory
```bash
mkdir -p /home/ubuntu/py-trade/data
```

#### Set Permissions
```bash
sudo chown -R ubuntu:ubuntu /home/ubuntu/py-trade
chmod 755 /home/ubuntu/py-trade/data
```

### 8. Monitoring and Logs

#### View Application Logs
```bash
sudo journalctl -u py-trade -f
```

#### View Nginx Logs
```bash
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log
```

#### Monitor System Resources
```bash
htop
df -h
free -h
```

### 9. Firewall Configuration (Optional)

#### Setup UFW
```bash
sudo ufw enable
sudo ufw allow ssh
sudo ufw allow 'Nginx Full'
sudo ufw status
```

### 10. Backup Strategy

#### Create Backup Script
```bash
nano /home/ubuntu/backup.sh
```

```bash
#!/bin/bash
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/home/ubuntu/backups"
mkdir -p $BACKUP_DIR

# Backup database
cp /home/ubuntu/py-trade/paper_trading.db $BACKUP_DIR/paper_trading_$DATE.db

# Backup environment file
cp /home/ubuntu/py-trade/.env $BACKUP_DIR/env_$DATE.backup

# Keep only last 7 days of backups
find $BACKUP_DIR -name "*.db" -mtime +7 -delete
find $BACKUP_DIR -name "*.backup" -mtime +7 -delete
```

```bash
chmod +x /home/ubuntu/backup.sh
# Add to crontab for daily backups
crontab -e
# Add: 0 2 * * * /home/ubuntu/backup.sh
```

### 11. Deployment Commands Summary

```bash
# Quick deployment commands
cd /home/ubuntu/py-trade
git pull origin main
source venv/bin/activate
pip install -r requirements.txt
sudo systemctl restart py-trade
sudo systemctl restart nginx
```

### 12. Troubleshooting

#### Common Issues:
1. **Service won't start**: Check logs with `sudo journalctl -u py-trade -f`
2. **Permission denied**: Ensure ubuntu user owns all files
3. **Port already in use**: Check with `sudo netstat -tlnp | grep :5000`
4. **SSL issues**: Verify domain DNS and firewall settings

#### Health Check Commands:
```bash
# Check service status
sudo systemctl status py-trade
sudo systemctl status nginx

# Test application
curl http://localhost:5000
curl https://your-domain.com

# Check ports
sudo netstat -tlnp | grep :80
sudo netstat -tlnp | grep :443
```

### 13. Security Best Practices

1. **Regular Updates**: `sudo apt update && sudo apt upgrade`
2. **Strong Passwords**: Use SSH keys instead of passwords
3. **Firewall**: Enable UFW with minimal required ports
4. **SSL**: Always use HTTPS in production
5. **Environment Variables**: Never commit secrets to git
6. **Backup**: Regular automated backups
7. **Monitoring**: Set up CloudWatch or similar monitoring

---

## 🎯 Quick Start Commands

```bash
# 1. Launch EC2 instance (t3.small, Ubuntu 22.04)
# 2. Configure security groups (SSH, HTTP, HTTPS)
# 3. Connect and run:

sudo apt update && sudo apt upgrade -y
sudo apt install python3.11 python3.11-venv python3-pip nginx git supervisor -y
cd /home/ubuntu
git clone <your-repo> py-trade
cd py-trade
python3.11 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
pip install gunicorn

# 4. Setup .env file with your credentials
# 5. Create and start systemd service
# 6. Configure Nginx
# 7. Setup SSL with Let's Encrypt
# 8. Your app is live! 🚀
```

**Your trading application will be accessible at: `https://your-domain.com`**