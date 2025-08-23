#!/bin/bash
# Simplified Cedar DMG Builder

echo "🌲 Building Cedar DMG..."

# Variables
DMG_NAME="Cedar-$(date +%Y%m%d).dmg"
APP_NAME="Cedar.app"
BUILD_DIR="/tmp/cedar-dmg"

# Clean and create build directory
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/$APP_NAME/Contents/MacOS"
mkdir -p "$BUILD_DIR/$APP_NAME/Contents/Resources/web-ui"

echo "Building backend..."
cd ~/Projects/cedarcli
cargo build --release --bin notebook_server || exit 1

echo "Copying files..."
# Copy backend
cp target/release/notebook_server "$BUILD_DIR/$APP_NAME/Contents/MacOS/Cedar"
chmod +x "$BUILD_DIR/$APP_NAME/Contents/MacOS/Cedar"

# Copy web UI
cp apps/web-ui/index.html "$BUILD_DIR/$APP_NAME/Contents/Resources/web-ui/"

# Create Info.plist
cat > "$BUILD_DIR/$APP_NAME/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Cedar</string>
    <key>CFBundleExecutable</key>
    <string>Cedar</string>
    <key>CFBundleIdentifier</key>
    <string>com.cedar.agent</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
</dict>
</plist>
EOF

# Create README
cat > "$BUILD_DIR/README.txt" << 'EOF'
Cedar Agent
===========

To use Cedar:
1. Set your OpenAI API key in terminal:
   export OPENAI_API_KEY="your-key-here"
   
2. Run Cedar from terminal:
   /Applications/Cedar.app/Contents/MacOS/Cedar

3. Open browser to http://localhost:8080

Features:
- Ask questions in natural language
- Process CSV/Excel/JSON files
- Click datasets to see statistics & preview
- All processing happens in the backend
EOF

echo "Creating DMG..."
# Use create-dmg if available, otherwise use hdiutil
if command -v create-dmg &> /dev/null; then
    create-dmg \
        --volname "Cedar" \
        --window-size 500 300 \
        --icon-size 100 \
        --app-drop-link 350 100 \
        "~/Desktop/$DMG_NAME" \
        "$BUILD_DIR"
else
    # Simple DMG creation
    hdiutil create -volname "Cedar" -srcfolder "$BUILD_DIR" -ov "~/Desktop/$DMG_NAME"
fi

# Clean up
rm -rf "$BUILD_DIR"

echo "✅ DMG created: ~/Desktop/$DMG_NAME"
echo ""
echo "Installation:"
echo "1. Open the DMG"
echo "2. Drag Cedar.app to Applications"
echo "3. Set OPENAI_API_KEY in your shell"
echo "4. Run from terminal: /Applications/Cedar.app/Contents/MacOS/Cedar"
echo "5. Open browser to http://localhost:8080"
