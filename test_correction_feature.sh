#!/bin/bash

# Test script for correction monitoring feature

echo "=== Testing Correction Monitoring Feature ==="
echo ""

# Test 1: Text Similarity
echo "Test 1: Text Similarity Calculation"
echo "Expected: High similarity for minor edits, low for different text"
echo ""

# Test 2: Correction Store
echo "Test 2: Correction Store"
echo "Location: ~/Library/Application Support/AnotherTypeless/corrections.json"
if [ -f ~/Library/Application\ Support/AnotherTypeless/corrections.json ]; then
    echo "✓ Corrections file exists"
    echo "Records: $(cat ~/Library/Application\ Support/AnotherTypeless/corrections.json | python3 -c "import sys, json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")"
else
    echo "✗ Corrections file not found (will be created on first correction)"
fi
echo ""

# Test 3: Build verification
echo "Test 3: Build Verification"
if [ -f .build/debug/AnotherTypeless ]; then
    echo "✓ Binary built successfully"
    echo "Size: $(ls -lh .build/debug/AnotherTypeless | awk '{print $5}')"
else
    echo "✗ Binary not found"
fi
echo ""

# Test 4: Source files
echo "Test 4: New Source Files"
files=(
    "Sources/AnotherTypeless/CorrectionRecord.swift"
    "Sources/AnotherTypeless/TextSimilarity.swift"
    "Sources/AnotherTypeless/TextChangeMonitor.swift"
    "Sources/AnotherTypeless/TextContextReader.swift"
)

for file in "${files[@]}"; do
    if [ -f "$file" ]; then
        lines=$(wc -l < "$file")
        echo "✓ $file ($lines lines)"
    else
        echo "✗ $file missing"
    fi
done
echo ""

# Test 5: Documentation
echo "Test 5: Documentation"
if [ -f "CORRECTION_FEATURE.md" ]; then
    echo "✓ Feature documentation exists"
    echo "Size: $(wc -l < CORRECTION_FEATURE.md) lines"
else
    echo "✗ Documentation missing"
fi
echo ""

echo "=== Manual Testing Instructions ==="
echo ""
echo "1. Build and run the app:"
echo "   ./scripts/build_app.sh"
echo "   open /Applications/another-typelessi.app"
echo ""
echo "2. Grant Accessibility permission in System Settings"
echo ""
echo "3. Test the correction monitoring:"
echo "   a. Open TextEdit or any text editor"
echo "   b. Press Fn and say something (e.g., 'hello world')"
echo "   c. Wait for the text to be pasted"
echo "   d. Edit the pasted text within 30 seconds"
echo "   e. Check Settings -> Correction History to see if it was recorded"
echo ""
echo "4. Test correction context in Polish:"
echo "   a. Create a correction (e.g., 'cube control' -> 'kubectl')"
echo "   b. Say 'cube control' again in a new dictation"
echo "   c. Check if the Polish output uses 'kubectl'"
echo ""
echo "5. Monitor logs:"
echo "   tail -f ~/Library/Application\\ Support/AnotherTypeless/dictation.log | grep -E 'monitor|correction'"
echo ""
