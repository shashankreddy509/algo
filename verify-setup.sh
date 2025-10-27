#!/bin/bash

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
if [[ $EUID -eq 0 ]]; then
    print_error "This script should NOT be run as root/sudo"
    print_info "Run it as: ./verify-setup.sh"
    exit 1
fi

print_header "Verifying EC2 Setup for py-trade Application"

# Check Python installation
print_header "Checking Python Installation"
if command -v python3 &> /dev/null; then
    PYTHON_VERSION=$(python3 --version)
    print_success "Python3 installed: $PYTHON_VERSION"
else
    print_error "Python3 not found"
    exit 1
fi

# Check if we can create virtual environments
print_header "Testing Virtual Environment Creation"
TEST_VENV="/tmp/test_py_trade_venv"
rm -rf "$TEST_VENV"

if python3 -m venv "$TEST_VENV"; then
    print_success "Virtual environment creation works"
    
    # Activate and test pip
    source "$TEST_VENV/bin/activate"
    
    # Test pip upgrade
    if "$TEST_VENV/bin/pip" install --upgrade pip setuptools wheel &> /dev/null; then
        print_success "Pip upgrade works in virtual environment"
    else
        print_error "Failed to upgrade pip in virtual environment"
    fi
    
    # Test aiohttp installation (key dependency that was failing)
    print_info "Testing aiohttp installation (this may take a moment)..."
    if "$TEST_VENV/bin/pip" install aiohttp &> /dev/null; then
        print_success "aiohttp installs successfully"
        
        # Test import
        if "$TEST_VENV/bin/python" -c "import aiohttp; print('aiohttp version:', aiohttp.__version__)" 2>/dev/null; then
            print_success "aiohttp imports and works correctly"
        else
            print_warning "aiohttp installed but import failed"
        fi
    else
        print_error "aiohttp installation failed"
    fi
    
    # Test fyers-apiv3 installation
    print_info "Testing fyers-apiv3 installation..."
    if "$TEST_VENV/bin/pip" install fyers-apiv3 &> /dev/null; then
        print_success "fyers-apiv3 installs successfully"
    else
        print_error "fyers-apiv3 installation failed"
    fi
    
    deactivate
    rm -rf "$TEST_VENV"
else
    print_error "Failed to create virtual environment"
    exit 1
fi

# Check build tools
print_header "Checking Build Tools"
BUILD_TOOLS=("gcc" "g++" "make" "pkg-config")
for tool in "${BUILD_TOOLS[@]}"; do
    if command -v "$tool" &> /dev/null; then
        print_success "$tool is installed"
    else
        print_error "$tool is missing"
    fi
done

# Check development libraries
print_header "Checking Development Libraries"
DEV_PACKAGES=("python3-dev" "libffi-dev" "libssl-dev")
for package in "${DEV_PACKAGES[@]}"; do
    if dpkg -l | grep -q "$package"; then
        print_success "$package is installed"
    else
        print_error "$package is missing"
    fi
done

# Check if project files exist
print_header "Checking Project Files"
PROJECT_FILES=("app.py" "requirements.txt" "deploy.sh" "gunicorn.conf.py" "py-trade.service" "nginx.conf")
for file in "${PROJECT_FILES[@]}"; do
    if [[ -f "$file" ]]; then
        print_success "$file exists"
    else
        print_error "$file is missing"
    fi
done

# Check if deploy.sh is executable
if [[ -x "deploy.sh" ]]; then
    print_success "deploy.sh is executable"
else
    print_warning "deploy.sh is not executable (run: chmod +x deploy.sh)"
fi

print_header "Verification Complete"
print_info "If all checks passed, you can now run:"
print_info "  sudo ./deploy.sh initial"
print_info ""
print_info "If there were any errors, please:"
print_info "  1. Run the fix-dependencies.sh script again"
print_info "  2. Check the TROUBLESHOOTING.md file"
print_info "  3. Ensure you're on a supported Ubuntu/Debian system"