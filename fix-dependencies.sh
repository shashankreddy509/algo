#!/bin/bash
# Fix Dependencies Script for aiohttp Build Issues
# This script addresses common build failures for Python packages with C extensions

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root (use sudo)"
   exit 1
fi

print_header "Fixing Python Build Dependencies"

# Update package lists
print_status "Updating package lists..."
apt update

# Install comprehensive build dependencies including python3-full
print_status "Installing build dependencies..."
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
    liblzma-dev

# Create a test virtual environment to verify setup
print_status "Creating test virtual environment..."
python3 -m venv /tmp/test_venv
source /tmp/test_venv/bin/activate

# Upgrade pip, setuptools, and wheel in virtual environment
print_status "Upgrading pip, setuptools, and wheel in virtual environment..."
/tmp/test_venv/bin/pip install --upgrade pip setuptools wheel

# Install Rust (sometimes needed for newer Python packages)
print_status "Installing Rust compiler (for some modern Python packages)..."
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source ~/.cargo/env || true

# Alternative: Install pre-compiled wheels if available
print_status "Attempting to install aiohttp with pre-compiled wheels in test environment..."
/tmp/test_venv/bin/pip install --only-binary=all aiohttp || {
    print_warning "Pre-compiled wheels not available, will compile from source"
}

# Set environment variables for compilation
export CFLAGS="-I/usr/include/python3.$(python3 -c 'import sys; print(sys.version_info.minor)')"
export LDFLAGS="-L/usr/lib/python3/dist-packages"

print_status "Build environment setup completed!"

print_header "Verification"

# Verify installations
print_status "Verifying build tools..."
gcc --version | head -1
python3 --version
pip3 --version

print_status "Testing aiohttp installation in virtual environment..."
/tmp/test_venv/bin/python -c "
try:
    import aiohttp
    print('✅ aiohttp is installed and working in virtual environment')
except ImportError:
    print('❌ aiohttp not installed, but build environment is ready')
"

# Clean up test environment
deactivate 2>/dev/null || true
rm -rf /tmp/test_venv

print_header "Next Steps"
print_status "Build dependencies are now installed. Try installing your requirements:"
echo "  cd /path/to/your/project"
echo "  python3 -m venv venv"
echo "  source venv/bin/activate"
echo "  pip install --upgrade pip setuptools wheel"
echo "  pip install -r requirements.txt"

print_warning "If you still encounter issues, try these alternatives:"
echo "  1. Use --no-cache-dir flag: pip install --no-cache-dir -r requirements.txt"
echo "  2. Install packages individually: pip install aiohttp"
echo "  3. Use conda instead of pip: conda install aiohttp"
echo "  4. Try older version: pip install 'aiohttp<4.0.0'"