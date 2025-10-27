# 🚀 EC2 Deployment Steps for py-trade

## 📋 Pre-Deployment Checklist

Before starting deployment, ensure you have:
- [ ] EC2 instance running Ubuntu 20.04+ or Debian 11+
- [ ] SSH access to the instance
- [ ] Domain name (optional, for SSL)
- [ ] Fyers API credentials

## 🔧 Step-by-Step Deployment Process

### Step 1: Upload Files to EC2
```bash
# Upload all files to your EC2 instance
scp -r * ubuntu@your-ec2-ip:/home/ubuntu/py-trade/
```

### Step 2: Make Scripts Executable
```bash
ssh ubuntu@your-ec2-ip
cd py-trade
chmod +x *.sh
```

### Step 3: Choose Your Deployment Strategy

#### Option A: Standard Deployment (Try First)
```bash
sudo ./deploy.sh initial
```

#### Option B: If aiohttp Build Fails (Advanced Fix)
```bash
# Run the advanced fix script first
sudo ./fix-aiohttp-advanced.sh

# Then run deployment
sudo ./deploy.sh initial
```

#### Option C: Manual Verification Before Deployment
```bash
# Verify environment first
./verify-setup.sh

# If verification passes, deploy
sudo ./deploy.sh initial

# If verification fails, run advanced fix
sudo ./fix-aiohttp-advanced.sh
./verify-setup.sh  # Verify again
sudo ./deploy.sh initial
```

## 🛠️ Troubleshooting aiohttp Build Issues

### Quick Fixes (Try in Order)

1. **Install Rust Compiler**
   ```bash
   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
   source ~/.cargo/env
   ```

2. **Use Pre-compiled Wheels**
   ```bash
   pip install --only-binary=all aiohttp
   ```

3. **Use Older Stable Version**
   ```bash
   pip install 'aiohttp==3.8.6'
   ```

4. **Install Dependencies Separately**
   ```bash
   pip install yarl multidict async-timeout aiosignal frozenlist attrs
   pip install aiohttp
   ```

### Advanced Solutions

If quick fixes don't work, the deployment scripts now include:

- **Multi-stage installation** with automatic fallbacks
- **Comprehensive build environment** setup
- **Rust compiler installation** for newer aiohttp versions
- **Dependency separation** strategy
- **Automatic verification** of installations

## 📊 Post-Deployment Configuration

### Step 4: Configure Environment Variables
```bash
sudo nano /opt/py-trade/.env
```

Use the `.env.example` as a template and fill in your values:
```bash
# Copy example and edit
sudo cp /opt/py-trade/.env.example /opt/py-trade/.env
sudo nano /opt/py-trade/.env
```

### Step 5: Set Up SSL (Optional but Recommended)
```bash
sudo ./ssl-setup.sh your-domain.com
```

### Step 6: Verify Deployment
```bash
# Check service status
sudo ./deploy.sh status

# View logs
sudo ./deploy.sh logs

# Test the application
curl http://localhost:5000
```

## 🔍 Verification Commands

### Check Service Status
```bash
sudo systemctl status py-trade
sudo systemctl status nginx
```

### View Application Logs
```bash
sudo journalctl -u py-trade -f
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log
```

### Test Application Endpoints
```bash
# Health check
curl http://localhost:5000/

# API test (if applicable)
curl http://localhost:5000/api/health
```

## 🚨 Emergency Recovery

If deployment fails completely:

1. **Stop services**
   ```bash
   sudo systemctl stop py-trade
   sudo systemctl stop nginx
   ```

2. **Clean up and retry**
   ```bash
   sudo rm -rf /opt/py-trade
   sudo ./deploy.sh initial
   ```

3. **Check system resources**
   ```bash
   free -h  # Check memory
   df -h    # Check disk space
   ```

## 📈 Performance Optimization

After successful deployment:

1. **Monitor resource usage**
   ```bash
   htop
   sudo ./deploy.sh status
   ```

2. **Adjust Gunicorn workers** (edit `/opt/py-trade/gunicorn.conf.py`)
   ```python
   workers = 2  # Adjust based on CPU cores
   ```

3. **Configure log rotation**
   ```bash
   sudo logrotate -d /etc/logrotate.d/py-trade
   ```

## 🔄 Updates and Maintenance

### Update Application Code
```bash
sudo ./deploy.sh update
```

### Restart Services
```bash
sudo ./deploy.sh restart
```

### View Recent Logs
```bash
sudo ./deploy.sh logs
```

## 📞 Support

If you encounter issues:

1. Check `TROUBLESHOOTING.md` for common solutions
2. Run `./verify-setup.sh` to diagnose environment issues
3. Use `sudo ./fix-aiohttp-advanced.sh` for persistent build problems
4. Review logs with `sudo ./deploy.sh logs`

## 🎯 Success Indicators

Deployment is successful when:
- [ ] `sudo systemctl status py-trade` shows "active (running)"
- [ ] `sudo systemctl status nginx` shows "active (running)"
- [ ] `curl http://localhost:5000` returns a response
- [ ] No errors in `sudo ./deploy.sh logs`
- [ ] Application accessible via browser (if domain configured)