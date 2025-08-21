#!/bin/bash
set -e

echo "🌲 Building Cedar Desktop App with Tauri..."

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Navigate to the Tauri app directory
cd apps/desktop

# Check if node modules are installed
if [ ! -d "node_modules" ]; then
    echo -e "${BLUE}Installing Node dependencies...${NC}"
    npm install
fi

# Check if Tauri CLI is installed
if ! npm list @tauri-apps/cli &>/dev/null; then
    echo -e "${BLUE}Installing Tauri CLI...${NC}"
    npm install --save-dev @tauri-apps/cli
fi

# Build the backend server first
echo -e "${BLUE}Building backend server...${NC}"
cd ../..
cargo build --release --bin notebook_server

# Go back to desktop app
cd apps/desktop

# Update the Tauri configuration to embed our server
echo -e "${BLUE}Updating Tauri configuration...${NC}"

# Build the Tauri app
echo -e "${BLUE}Building Tauri app...${NC}"
npm run tauri build

# The DMG should be created at src-tauri/target/release/bundle/dmg/
DMG_PATH=$(find src-tauri/target/release/bundle/dmg -name "*.dmg" -type f | head -n 1)

if [ -z "$DMG_PATH" ]; then
    echo -e "${YELLOW}DMG not found. Checking for app bundle...${NC}"
    
    # Check if the app bundle exists
    APP_BUNDLE=$(find src-tauri/target/release/bundle -name "*.app" -type d | head -n 1)
    
    if [ -n "$APP_BUNDLE" ]; then
        echo -e "${BLUE}Creating DMG from app bundle...${NC}"
        
        # Create DMG manually
        DMG_NAME="Cedar-$(date +%Y%m%d).dmg"
        DMG_TEMP="/tmp/cedar-dmg-$$"
        mkdir -p "$DMG_TEMP"
        
        cp -r "$APP_BUNDLE" "$DMG_TEMP/"
        ln -s /Applications "$DMG_TEMP/Applications"
        
        hdiutil create -volname "Cedar Desktop" \
            -srcfolder "$DMG_TEMP" \
            -ov -format UDZO \
            "../../$DMG_NAME"
        
        rm -rf "$DMG_TEMP"
        
        echo -e "${GREEN}✅ DMG created: $DMG_NAME${NC}"
    else
        echo "❌ No app bundle found"
        exit 1
    fi
else
    # Copy the DMG to the root directory
    cp "$DMG_PATH" "../../Cedar-$(date +%Y%m%d).dmg"
    echo -e "${GREEN}✅ DMG created: Cedar-$(date +%Y%m%d).dmg${NC}"
fi

echo ""
echo "To install Cedar Desktop:"
echo "1. Open the DMG file"
echo "2. Drag the app to your Applications folder"
echo "3. Launch from Applications"
echo ""
echo -e "${YELLOW}Note: On first launch, you may need to right-click and select 'Open' to bypass Gatekeeper${NC}"
