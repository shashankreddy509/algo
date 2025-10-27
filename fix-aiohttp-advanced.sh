#!/bin/bash

# Advanced aiohttp Fix Script for EC2 Deployment
# This script addresses persistent aiohttp build failures

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
    print_info "Run it as: sudo ./fix-aiohttp-advanced.sh"
    exit 1
fi

print_header "Advanced aiohttp Build Fix for EC2"

# Update system
print_info "Updating system packages..."
apt update && apt upgrade -y

# Install comprehensive build environment
print_header "Installing Comprehensive Build Environment"
apt install -y \
    python3-full \
    python3-dev \
    python3-pip \
    python3-venv \
    python3-setuptools \
    python3-wheel \
    build-essential \
    gcc \
    g++ \
    make \
    cmake \
    pkg-config \
    libffi-dev \
    libssl-dev \
    libc6-dev \
    zlib1g-dev \
    libbz2-dev \
    libreadline-dev \
    libsqlite3-dev \
    libncurses5-dev \
    libncursesw5-dev \
    xz-utils \
    tk-dev \
    libxml2-dev \
    libxmlsec1-dev \
    liblzma-dev \
    libgdbm-dev \
    libnss3-dev \
    libssl-dev \
    libreadline-dev \
    libffi-dev \
    libsqlite3-dev \
    wget \
    curl \
    llvm \
    libncursesw5-dev \
    xz-utils \
    tk-dev \
    libxml2-dev \
    libxmlsec1-dev \
    libffi-dev \
    liblzma-dev

# Install Rust (required for newer aiohttp versions)
print_header "Installing Rust Compiler"
if ! command -v rustc &> /dev/null; then
    print_info "Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source ~/.cargo/env
    export PATH="$HOME/.cargo/bin:$PATH"
    print_success "Rust installed successfully"
else
    print_success "Rust already installed"
fi

# Ensure Rust is in PATH for all users
echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> /etc/environment
source /etc/environment

# Create test environment
print_header "Testing aiohttp Installation"
TEST_VENV="/tmp/aiohttp_test"
rm -rf "$TEST_VENV"

python3 -m venv "$TEST_VENV"
source "$TEST_VENV/bin/activate"

# Upgrade pip and build tools
print_info "Upgrading pip and build tools..."
"$TEST_VENV/bin/pip" install --upgrade pip setuptools wheel

# Set environment variables for compilation
export CFLAGS="-I/usr/include/openssl"
export LDFLAGS="-L/usr/lib/x86_64-linux-gnu"
export RUSTFLAGS="-C target-cpu=native"

# Try multiple installation strategies
print_header "Attempting aiohttp Installation Strategies"

# Strategy 1: Try with pre-compiled wheels
print_info "Strategy 1: Pre-compiled wheels..."
if "$TEST_VENV/bin/pip" install --only-binary=all aiohttp 2>/dev/null; then
    print_success "Strategy 1 succeeded: Pre-compiled wheels"
    INSTALL_METHOD="precompiled"
else
    print_warning "Strategy 1 failed: No pre-compiled wheels available"
    
    # Strategy 2: Try older stable version
    print_info "Strategy 2: Older stable version..."
    if "$TEST_VENV/bin/pip" install 'aiohttp==3.8.6' 2>/dev/null; then
        print_success "Strategy 2 succeeded: Older version (3.8.6)"
        INSTALL_METHOD="older_version"
    else
        print_warning "Strategy 2 failed: Older version compilation failed"
        
        # Strategy 3: Build from source with optimizations
        print_info "Strategy 3: Build from source with optimizations..."
        export CC=gcc
        export CXX=g++
        export MAKEFLAGS="-j$(nproc)"
        
        if "$TEST_VENV/bin/pip" install --no-cache-dir --no-binary aiohttp aiohttp 2>/dev/null; then
            print_success "Strategy 3 succeeded: Source build with optimizations"
            INSTALL_METHOD="source_optimized"
        else
            print_warning "Strategy 3 failed: Source build failed"
            
            # Strategy 4: Install dependencies separately
            print_info "Strategy 4: Installing dependencies separately..."
            "$TEST_VENV/bin/pip" install --no-cache-dir yarl multidict async-timeout aiosignal frozenlist attrs
            
            if "$TEST_VENV/bin/pip" install --no-cache-dir aiohttp 2>/dev/null; then
                print_success "Strategy 4 succeeded: Separate dependency installation"
                INSTALL_METHOD="separate_deps"
            else
                print_error "All strategies failed. Manual intervention required."
                INSTALL_METHOD="failed"
            fi
        fi
    fi
fi

# Test the installation
if [[ "$INSTALL_METHOD" != "failed" ]]; then
    print_header "Testing aiohttp Import"
    if "$TEST_VENV/bin/python" -c "import aiohttp; print('aiohttp version:', aiohttp.__version__)" 2>/dev/null; then
        print_success "aiohttp imports successfully"
        
        # Test fyers-apiv3 with working aiohttp
        print_info "Testing fyers-apiv3 installation..."
        if "$TEST_VENV/bin/pip" install fyers-apiv3 2>/dev/null; then
            print_success "fyers-apiv3 installed successfully"
        else
            print_warning "fyers-apiv3 installation failed"
        fi
    else
        print_error "aiohttp installed but import failed"
        INSTALL_METHOD="failed"
    fi
fi

# Clean up test environment
deactivate 2>/dev/null || true
rm -rf "$TEST_VENV"

print_header "Results and Recommendations"

if [[ "$INSTALL_METHOD" != "failed" ]]; then
    print_success "aiohttp build issue resolved using: $INSTALL_METHOD"
    
    case $INSTALL_METHOD in
        "precompiled")
            print_info "Recommendation: Use --only-binary=all flag in requirements installation"
            ;;
        "older_version")
            print_info "Recommendation: Pin aiohttp to version 3.8.6 in requirements.txt"
            ;;
        "source_optimized")
            print_info "Recommendation: Use current build environment for source compilation"
            ;;
        "separate_deps")
            print_info "Recommendation: Install aiohttp dependencies separately first"
            ;;
    esac
    
    print_header "Next Steps"
    print_info "1. Run the deployment script: sudo ./deploy.sh initial"
    print_info "2. The build environment is now properly configured"
    print_info "3. If issues persist, check the updated requirements.txt"
    
else
    print_error "Unable to resolve aiohttp build issues automatically"
    print_info "Manual steps required:"
    print_info "1. Check system architecture: uname -a"
    print_info "2. Verify Python version: python3 --version"
    print_info "3. Check available memory: free -h"
    print_info "4. Consider using a different EC2 instance type"
fi

print_header "Build Environment Summary"
print_info "Rust compiler: $(rustc --version 2>/dev/null || echo 'Not available')"
print_info "GCC version: $(gcc --version | head -n1)"
print_info "Python version: $(python3 --version)"
print_info "Available memory: $(free -h | grep Mem | awk '{print $2}')"