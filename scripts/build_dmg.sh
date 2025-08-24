#!/bin/bash
# Build Cedar DMG with all improvements

echo "🌲 Cedar DMG Builder"
echo "===================="
echo "Building Cedar with enhanced features:"
echo "  - Dataset preview modal"
echo "  - Real-time progress (SSE ready)"
echo "  - Simplified frontend (backend handles everything)"
echo "  - DuckDB integration fixed"
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Set build directory
BUILD_DIR="/tmp/cedar-build-$(date +%Y%m%d-%H%M%S)"
DMG_NAME="Cedar-Enhanced-$(date +%Y%m%d).dmg"

# Step 0: Validate API key fetching before build
echo -e "${YELLOW}Step 0: Validating API key configuration...${NC}"
if [ -f "scripts/validate_api_key.sh" ]; then
    bash scripts/validate_api_key.sh
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ API key validation failed!${NC}"
        echo "The DMG build is cancelled because the API key cannot be fetched."
        echo "Please fix the API key configuration before building."
        exit 1
    fi
    echo -e "${GREEN}✓ API key validation passed${NC}"
else
    echo -e "${YELLOW}⚠ Validation script not found, proceeding anyway...${NC}"
fi

echo -e "\n${YELLOW}Step 1: Building Rust backend...${NC}"
cd ~/Projects/cedarcli
cargo build --release --bin notebook_server

if [ $? -ne 0 ]; then
    echo "❌ Failed to build backend"
    exit 1
fi
echo -e "${GREEN}✓ Backend built successfully${NC}"

echo -e "\n${YELLOW}Step 2: Creating app bundle structure...${NC}"
mkdir -p "$BUILD_DIR"
mkdir -p "$BUILD_DIR/Cedar.app/Contents/MacOS"
mkdir -p "$BUILD_DIR/Cedar.app/Contents/Resources"
mkdir -p "$BUILD_DIR/Cedar.app/Contents/Resources/web-ui"
mkdir -p "$BUILD_DIR/Cedar.app/Contents/Resources/julia_env"

echo -e "${GREEN}✓ App bundle structure created${NC}"

echo -e "\n${YELLOW}Step 3: Copying backend binary...${NC}"
cp target/release/notebook_server "$BUILD_DIR/Cedar.app/Contents/MacOS/Cedar"
chmod +x "$BUILD_DIR/Cedar.app/Contents/MacOS/Cedar"
echo -e "${GREEN}✓ Backend binary copied${NC}"

echo -e "\n${YELLOW}Step 4: Copying web UI files...${NC}"
cp apps/web-ui/index.html "$BUILD_DIR/Cedar.app/Contents/Resources/web-ui/"
echo -e "${GREEN}✓ Web UI copied${NC}"

echo -e "\n${YELLOW}Step 4b: Copying environment configuration...${NC}"
# Copy the .env file to the app bundle
if [ -f "apps/cedar-bundle/resources/.env" ]; then
    cp apps/cedar-bundle/resources/.env "$BUILD_DIR/Cedar.app/Contents/Resources/"
    echo -e "${GREEN}✓ Environment config copied${NC}"
else
    echo -e "${YELLOW}⚠ No .env file found, app will use defaults${NC}"
fi

echo -e "\n${YELLOW}Step 4c: Copying app icon...${NC}"
# Copy the Cedar icon to the app bundle
cp images/icons/Cedar.icns "$BUILD_DIR/Cedar.app/Contents/Resources/AppIcon.icns"
echo -e "${GREEN}✓ App icon copied${NC}"

echo -e "\n${YELLOW}Step 5: Creating Info.plist...${NC}"
cat > "$BUILD_DIR/Cedar.app/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Cedar</string>
    <key>CFBundleDisplayName</key>
    <string>Cedar Agent</string>
    <key>CFBundleIdentifier</key>
    <string>com.cedar.agent</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleSignature</key>
    <string>????</string>
    <key>CFBundleExecutable</key>
    <string>Cedar</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>10.15</string>
    <key>LSEnvironment</key>
    <dict>
        <key>CEDAR_KEY_URL</key>
        <string>https://cedar-notebook.onrender.com/v1/key</string>
        <key>APP_SHARED_TOKEN</key>
        <string>403-298-09345-023495</string>
    </dict>
</dict>
</plist>
EOF
echo -e "${GREEN}✓ Info.plist created${NC}"

echo -e "\n${YELLOW}Step 6: Creating launcher script...${NC}"
cat > "$BUILD_DIR/Cedar.app/Contents/MacOS/cedar-launcher.sh" << 'EOF'
#!/bin/bash
# Cedar launcher script

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
APP_DIR="$SCRIPT_DIR/.."

# Set up environment
# Load from bundled .env file if it exists
if [ -f "$APP_DIR/Resources/.env" ]; then
    export $(grep -v '^#' "$APP_DIR/Resources/.env" | xargs)
fi

# Start the backend server
cd "$APP_DIR/Resources"
"$SCRIPT_DIR/Cedar" &
SERVER_PID=$!

# Wait for server to start
sleep 2

# Open the browser to the local server
open "http://localhost:8080"

# Keep the script running
wait $SERVER_PID
EOF
chmod +x "$BUILD_DIR/Cedar.app/Contents/MacOS/cedar-launcher.sh"
echo -e "${GREEN}✓ Launcher script created${NC}"

echo -e "\n${YELLOW}Step 7: Creating README...${NC}"
cat > "$BUILD_DIR/README.txt" << 'EOF'
Cedar Agent - Enhanced Version
==============================

Features:
- AI-powered data analysis with Julia
- CSV/Excel/JSON/Parquet file processing
- Dataset preview with statistics
- DuckDB integration for data storage
- Real-time progress updates (coming soon)

Installation:
1. Drag Cedar.app to your Applications folder
2. Double-click Cedar.app to launch

The app automatically fetches the API key from the Cedar server.
No manual configuration needed!

Usage:
- Type queries in the Research tab
- Upload files via the Data tab or paperclip icon
- Click on datasets to see detailed preview
- View history in the History tab

The backend handles all processing - the frontend is just a UI.

For support: https://github.com/yourusername/cedar
EOF
echo -e "${GREEN}✓ README created${NC}"

echo -e "\n${YELLOW}Step 8: Creating DMG...${NC}"
# Create a temporary DMG
hdiutil create -size 100m -fs HFS+ -volname "Cedar" "$BUILD_DIR/temp.dmg"
hdiutil attach "$BUILD_DIR/temp.dmg"

# Copy files to the mounted volume
cp -R "$BUILD_DIR/Cedar.app" "/Volumes/Cedar/"
cp "$BUILD_DIR/README.txt" "/Volumes/Cedar/"

# Create a symbolic link to Applications
ln -s /Applications "/Volumes/Cedar/Applications"

# Unmount and convert to compressed DMG
hdiutil detach "/Volumes/Cedar"
hdiutil convert "$BUILD_DIR/temp.dmg" -format UDZO -o "~/Desktop/$DMG_NAME"

# Clean up
rm -rf "$BUILD_DIR"

echo -e "\n${GREEN}✅ Build complete!${NC}"
echo -e "DMG created: ~/Desktop/$DMG_NAME"
echo ""
echo "To test:"
echo "1. Make sure OPENAI_API_KEY is set in your environment"
echo "2. Open the DMG and drag Cedar to Applications"
echo "3. Launch Cedar from Applications"
echo ""
echo "The app will:"
echo "- Start the backend server locally"
echo "- Open your browser to http://localhost:8080"
echo "- All processing happens in the backend"
