# Troubleshooting Guide

## 🔧 Common Issues and Solutions

### 1. aiohttp Build Failures

**Error Messages:**
```
ERROR: Failed building wheel for aiohttp
× Failed to build installable wheels for some pyproject.toml based projects
error: command '/usr/bin/x86_64-linux-gnu-gcc' failed with exit code 1
```

**Solutions (try in order):**

#### Option A: Use the Fix Script
```bash
sudo chmod +x fix-dependencies.sh
sudo ./fix-dependencies.sh
```

#### Option B: Manual Build Dependencies
```bash
sudo apt update
sudo apt install -y python3-dev build-essential gcc g++ make \
    libffi-dev libssl-dev pkg-config cmake
pip install --upgrade pip setuptools wheel
```

#### Option C: Use Pre-compiled Wheels Only
```bash
pip install --only-binary=:all: -r requirements.txt
```

#### Option D: Install Without Cache
```bash
pip install --no-cache-dir -r requirements.txt
```

#### Option E: Use Older aiohttp Version
```bash
pip install 'aiohttp==3.8.6'
pip install fyers-apiv3
```

### 2. Memory Issues During Installation

**Error:** `MemoryError` or `Killed` during pip install

**Solution:**
```bash
# Create swap file if not exists
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# Add to /etc/fstab for persistence
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

### 3. Permission Issues

**Error:** `Permission denied` errors

**Solution:**
```bash
# Fix ownership
sudo chown -R ubuntu:ubuntu /home/ubuntu/py-trade

# Fix permissions
chmod +x /home/ubuntu/py-trade/*.sh
```

### 4. Service Won't Start

**Check service status:**
```bash
sudo systemctl status py-trade
sudo journalctl -u py-trade -f
```

**Common fixes:**
```bash
# Check if port is in use
sudo netstat -tlnp | grep :5000

# Restart service
sudo systemctl restart py-trade

# Check Gunicorn logs
tail -f /var/log/gunicorn/error.log
```

### 5. Nginx Issues

**Test configuration:**
```bash
sudo nginx -t
```

**Common fixes:**
```bash
# Restart Nginx
sudo systemctl restart nginx

# Check error logs
sudo tail -f /var/log/nginx/error.log

# Verify site is enabled
sudo ls -la /etc/nginx/sites-enabled/
```

### 6. SSL Certificate Issues

**Check certificate status:**
```bash
sudo certbot certificates
```

**Renew certificates:**
```bash
sudo certbot renew --dry-run
sudo certbot renew
```

### 7. Environment Variables

**Check if .env file exists:**
```bash
ls -la /home/ubuntu/py-trade/.env
```

**Create from template:**
```bash
cp /home/ubuntu/py-trade/.env.example /home/ubuntu/py-trade/.env
# Edit with your actual values
nano /home/ubuntu/py-trade/.env
```

### 8. Database Issues

**Check database file:**
```bash
ls -la /home/ubuntu/py-trade/*.db
```

**Fix permissions:**
```bash
sudo chown ubuntu:ubuntu /home/ubuntu/py-trade/*.db
```

### 9. Firewall Issues

**Check UFW status:**
```bash
sudo ufw status
```

**Open required ports:**
```bash
sudo ufw allow ssh
sudo ufw allow 'Nginx Full'
sudo ufw enable
```

### 10. Python Version Issues

**Check Python version:**
```bash
python3 --version
pip3 --version
```

**Install specific Python version (if needed):**
```bash
sudo apt install python3.11 python3.11-venv python3.11-dev
```

## 🚨 Emergency Recovery

### Complete Reset
```bash
# Stop services
sudo systemctl stop py-trade nginx

# Remove application
sudo rm -rf /home/ubuntu/py-trade

# Re-deploy
# Upload your project files again and run:
sudo ./deploy.sh initial
```

### Service Recovery
```bash
# Reset systemd service
sudo systemctl daemon-reload
sudo systemctl reset-failed py-trade
sudo systemctl restart py-trade
```

## 📊 Monitoring Commands

### Check System Resources
```bash
# CPU and Memory
htop

# Disk usage
df -h

# Network connections
ss -tuln
```

### Check Application Health
```bash
# Service status
./deploy.sh status

# View logs
./deploy.sh logs

# Test application
curl -I http://localhost:5000
```

## 🔍 Debug Mode

### Enable Debug Logging
Edit `/home/ubuntu/py-trade/.env`:
```
FLASK_DEBUG=True
LOG_LEVEL=DEBUG
```

Then restart:
```bash
sudo systemctl restart py-trade
```

### Manual Testing
```bash
# Test Gunicorn directly
cd /home/ubuntu/py-trade
source venv/bin/activate
gunicorn --config gunicorn.conf.py app:app

# Test Flask directly
python3 app.py
```

## 📞 Getting Help

1. **Check logs first:** `./deploy.sh logs`
2. **Verify system status:** `./deploy.sh status`
3. **Test connectivity:** `curl -I http://your-domain.com`
4. **Check this guide** for similar issues
5. **Search error messages** online with "Ubuntu 22.04" + your error

## 🔄 Update Process

### Safe Update Procedure
```bash
# 1. Create backup
./deploy.sh status  # Verify current state

# 2. Update code
git pull  # or upload new files

# 3. Update application
./deploy.sh update

# 4. Verify
./deploy.sh status
```