#!/bin/bash
# Script to check template deployment status on EC2
# Run this on EC2 to verify if templates are properly deployed

echo "🔍 Checking Template Deployment Status"
echo "======================================"

# Check if scanner.html exists
SCANNER_FILE="/home/ubuntu/py-trade/templates/scanner.html"
if [ -f "$SCANNER_FILE" ]; then
    echo "✅ scanner.html exists"
    
    # Check for Save to Firestore button
    if grep -q "saveFirestoreBtn" "$SCANNER_FILE"; then
        echo "✅ saveFirestoreBtn found in template"
        
        # Show the button HTML
        echo ""
        echo "📄 Button HTML:"
        grep -A 2 -B 2 "saveFirestoreBtn" "$SCANNER_FILE" | head -10
        
    else
        echo "❌ saveFirestoreBtn NOT found in template"
    fi
    
    # Check file modification time
    echo ""
    echo "📅 Template file info:"
    ls -la "$SCANNER_FILE"
    
else
    echo "❌ scanner.html does not exist at $SCANNER_FILE"
fi

echo ""
echo "🔍 Checking Service Status"
echo "========================="
systemctl status py-trade --no-pager -l

echo ""
echo "🔍 Checking Recent Deployments"
echo "=============================="
if [ -f "/home/ubuntu/py-trade/deploy.sh" ]; then
    echo "✅ deploy.sh exists"
    ls -la /home/ubuntu/py-trade/deploy.sh
else
    echo "❌ deploy.sh not found"
fi

echo ""
echo "🔍 Checking Template Directory"
echo "============================="
ls -la /home/ubuntu/py-trade/templates/

echo ""
echo "🔍 Checking for Template Backup/Cache Issues"
echo "==========================================="
# Check if there are any cached or backup template files
find /home/ubuntu/py-trade -name "*.html*" -type f

echo ""
echo "💡 Next Steps:"
echo "1. If saveFirestoreBtn is missing from template, redeploy"
echo "2. If template is old, check deployment process"
echo "3. If service is not running latest code, restart service"