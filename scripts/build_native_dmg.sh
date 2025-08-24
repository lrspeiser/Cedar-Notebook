#!/bin/bash
# Build Cedar Native DMG (Desktop App - No Browser)

echo "🌲 Cedar Native Desktop App Builder"
echo "====================================="
echo "Building Cedar as a native macOS application"
echo "  - Native UI using egui (no browser)"
echo "  - Standalone desktop app"
echo "  - Automatic API key fetching"
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Set build directory
BUILD_DIR="/tmp/cedar-native-build-$(date +%Y%m%d-%H%M%S)"
DMG_NAME="Cedar-Native-$(date +%Y%m%d).dmg"

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

echo -e "\n${YELLOW}Step 1: Building native Cedar app with egui...${NC}"
cd ~/Projects/cedarcli

# Build the native egui app
cargo build --release --bin cedar-egui

if [ $? -ne 0 ]; then
    echo "❌ Failed to build native app"
    exit 1
fi
echo -e "${GREEN}✓ Native app built successfully${NC}"

echo -e "\n${YELLOW}Step 2: Creating app bundle structure...${NC}"
mkdir -p "$BUILD_DIR"
mkdir -p "$BUILD_DIR/Cedar.app/Contents/MacOS"
mkdir -p "$BUILD_DIR/Cedar.app/Contents/Resources"

echo -e "${GREEN}✓ App bundle structure created${NC}"

echo -e "\n${YELLOW}Step 3: Copying native app binary...${NC}"
cp target/release/cedar-egui "$BUILD_DIR/Cedar.app/Contents/MacOS/Cedar"
chmod +x "$BUILD_DIR/Cedar.app/Contents/MacOS/Cedar"
echo -e "${GREEN}✓ Native app binary copied${NC}"

echo -e "\n${YELLOW}Step 4: Copying environment configuration...${NC}"
# Copy the .env file to the app bundle if it exists
if [ -f "apps/cedar-bundle/resources/.env" ]; then
    cp apps/cedar-bundle/resources/.env "$BUILD_DIR/Cedar.app/Contents/Resources/"
    echo -e "${GREEN}✓ Environment config copied${NC}"
else
    echo -e "${YELLOW}⚠ No .env file found, app will use defaults${NC}"
fi

echo -e "\n${YELLOW}Step 5: Copying app icon...${NC}"
# Copy the Cedar icon to the app bundle
if [ -f "images/icons/Cedar.icns" ]; then
    cp images/icons/Cedar.icns "$BUILD_DIR/Cedar.app/Contents/Resources/AppIcon.icns"
    echo -e "${GREEN}✓ App icon copied${NC}"
else
    echo -e "${YELLOW}⚠ No icon found, using default${NC}"
fi

echo -e "\n${YELLOW}Step 6: Creating Info.plist...${NC}"
cat > "$BUILD_DIR/Cedar.app/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Cedar</string>
    <key>CFBundleDisplayName</key>
    <string>Cedar Desktop</string>
    <key>CFBundleIdentifier</key>
    <string>com.cedar.desktop</string>
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

echo -e "\n${YELLOW}Step 7: Creating README...${NC}"
cat > "$BUILD_DIR/README.txt" << 'EOF'
Cedar Desktop - Native Application
===================================

This is the native desktop version of Cedar.
No web browser required!

Features:
- Native macOS application
- AI-powered data analysis
- File processing capabilities
- Automatic API key management
- Direct desktop integration

Installation:
1. Drag Cedar.app to your Applications folder
2. Double-click Cedar.app to launch

The app automatically fetches the API key from the Cedar server.
No manual configuration needed!

Usage:
- Launch the app directly from Applications
- All processing happens within the native app
- No browser or server components needed

For support: https://github.com/yourusername/cedar
EOF
echo -e "${GREEN}✓ README created${NC}"

echo -e "\n${YELLOW}Step 8: Creating DMG...${NC}"

# Clean up any existing Cedar volumes first
for volume in /Volumes/Cedar*; do
    if [ -d "$volume" ]; then
        echo "Unmounting existing Cedar volume: $volume"
        hdiutil detach "$volume" 2>/dev/null || true
    fi
done

# Create a folder with the app and readme
mkdir -p "$BUILD_DIR/dmg_contents"
cp -R "$BUILD_DIR/Cedar.app" "$BUILD_DIR/dmg_contents/"
cp "$BUILD_DIR/README.txt" "$BUILD_DIR/dmg_contents/"
ln -s /Applications "$BUILD_DIR/dmg_contents/Applications"

# Create the DMG directly from the folder
rm -f "$HOME/Desktop/$DMG_NAME" 2>/dev/null || true
hdiutil create -volname "Cedar" -srcfolder "$BUILD_DIR/dmg_contents" -ov -format UDZO "$HOME/Desktop/$DMG_NAME"

# Clean up
rm -rf "$BUILD_DIR"

echo -e "\n${GREEN}✅ Build complete!${NC}"
echo -e "DMG created: ~/Desktop/$DMG_NAME"
echo ""
echo "To install:"
echo "1. Open the DMG file on your Desktop"
echo "2. Drag Cedar.app to your Applications folder"
echo "3. Launch Cedar from Applications"
echo ""
echo "This is a native desktop app - no browser needed!"
