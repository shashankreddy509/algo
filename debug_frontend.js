// Frontend Debug Script for Scanner Button Visibility
// Paste this into your browser's console on the scanner page

console.log("🔍 Scanner Button Debug Tool");
console.log("=" * 50);

// Check if elements exist
const saveFirestoreBtn = document.getElementById('saveFirestoreBtn');
const downloadBtn = document.getElementById('downloadCsvBtn');
const createWishlistBtn = document.getElementById('createWishlistBtn');

console.log("📋 Button Elements:");
console.log("Save to Firestore button:", saveFirestoreBtn);
console.log("Download CSV button:", downloadBtn);
console.log("Create Wishlist button:", createWishlistBtn);

if (saveFirestoreBtn) {
    console.log("✅ Save to Firestore button found");
    console.log("Classes:", saveFirestoreBtn.className);
    console.log("Style display:", saveFirestoreBtn.style.display);
    console.log("Computed style:", window.getComputedStyle(saveFirestoreBtn).display);
    console.log("Has d-none class:", saveFirestoreBtn.classList.contains('d-none'));
} else {
    console.log("❌ Save to Firestore button NOT found");
}

// Check for recent scanner results
console.log("\n📊 Scanner Results Check:");
const resultsContainer = document.getElementById('scannerResults');
if (resultsContainer) {
    console.log("Results container found");
    console.log("Results HTML length:", resultsContainer.innerHTML.length);
    console.log("Has results:", resultsContainer.innerHTML.trim() !== '');
} else {
    console.log("❌ Results container NOT found");
}

// Check for JavaScript errors
console.log("\n🐛 JavaScript Error Check:");
window.addEventListener('error', function(e) {
    console.error('JavaScript Error:', e.error);
});

// Monitor fetch requests
console.log("\n🌐 Network Monitor:");
const originalFetch = window.fetch;
window.fetch = function(...args) {
    console.log('Fetch request:', args[0]);
    return originalFetch.apply(this, args)
        .then(response => {
            console.log('Fetch response:', response.status, response.url);
            return response;
        })
        .catch(error => {
            console.error('Fetch error:', error);
            throw error;
        });
};

// Test button visibility function
function testButtonVisibility() {
    console.log("\n🧪 Testing Button Visibility Logic:");
    
    const mockResults = [
        { symbol: 'RELIANCE', price: 2500 },
        { symbol: 'TCS', price: 3200 }
    ];
    
    console.log("Simulating results:", mockResults);
    
    if (saveFirestoreBtn && mockResults.length > 0) {
        console.log("Removing d-none class...");
        saveFirestoreBtn.classList.remove('d-none');
        console.log("Button should now be visible");
        console.log("New classes:", saveFirestoreBtn.className);
    }
}

// Run the test
testButtonVisibility();

console.log("\n💡 Next Steps:");
console.log("1. Run a scanner search and watch the console");
console.log("2. Check if any JavaScript errors appear");
console.log("3. Verify the API response contains results");
console.log("4. Test manual button visibility with testButtonVisibility()");