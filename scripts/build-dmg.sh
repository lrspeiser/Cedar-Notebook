#!/bin/bash
set -e

echo "🌲 Building Cedar App Bundle and DMG..."

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check prerequisites
echo -e "${BLUE}Checking prerequisites...${NC}"

if ! command -v cargo &> /dev/null; then
    echo "❌ Cargo is not installed. Please install Rust."
    exit 1
fi

if ! command -v cargo-bundle &> /dev/null; then
    echo -e "${YELLOW}cargo-bundle not found. Installing...${NC}"
    cargo install cargo-bundle
fi

# Embed Julia if not already done
if [ ! -d "apps/cedar-bundle/resources/julia" ]; then
    echo -e "${BLUE}Embedding Julia...${NC}"
    ./scripts/embed-julia.sh
else
    echo -e "${GREEN}Julia already embedded${NC}"
fi

# Build the release binary
echo -e "${BLUE}Building Cedar release binary...${NC}"
cd apps/cedar-bundle
cargo build --release

# Create the app bundle
echo -e "${BLUE}Creating app bundle...${NC}"
cargo bundle --release

# The bundle should be created at target/release/bundle/osx/Cedar.app
BUNDLE_PATH="../../target/release/bundle/osx/Cedar.app"

if [ ! -d "$BUNDLE_PATH" ]; then
    echo "❌ Bundle not found at $BUNDLE_PATH"
    exit 1
fi

# Copy web UI resources into the bundle
echo -e "${BLUE}Copying web UI resources...${NC}"
mkdir -p "$BUNDLE_PATH/Contents/Resources/web-ui"
cp -r ../../apps/web-ui/* "$BUNDLE_PATH/Contents/Resources/web-ui/"

# Copy embedded Julia into the bundle
echo -e "${BLUE}Copying embedded Julia...${NC}"
if [ -d "resources/julia" ]; then
    cp -r resources/julia "$BUNDLE_PATH/Contents/Resources/"
    cp resources/julia-wrapper.sh "$BUNDLE_PATH/Contents/Resources/"
    chmod +x "$BUNDLE_PATH/Contents/Resources/julia-wrapper.sh"
    
    # Copy Julia environment if it exists
    if [ -d "resources/julia_env" ]; then
        cp -r resources/julia_env "$BUNDLE_PATH/Contents/Resources/"
    fi
    
    echo -e "${GREEN}Julia embedded in app bundle${NC}"
else
    echo -e "${YELLOW}Warning: Embedded Julia not found. App will use system Julia.${NC}"
fi

# Copy the icon to the bundle
echo -e "${BLUE}Copying app icon...${NC}"
cp ../../images/icons/Cedar.icns "$BUNDLE_PATH/Contents/Resources/AppIcon.icns"

# Create a DMG using create-dmg if available, otherwise use hdiutil
if command -v create-dmg &> /dev/null; then
    echo -e "${BLUE}Creating DMG with create-dmg...${NC}"
    create-dmg \
        --volname "Cedar" \
        --volicon "../../images/icons/Cedar.icns" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 100 \
        --icon "Cedar.app" 175 190 \
        --hide-extension "Cedar.app" \
        --app-drop-link 425 190 \
        "Cedar-$(date +%Y%m%d).dmg" \
        "$BUNDLE_PATH"
else
    echo -e "${BLUE}Creating DMG with hdiutil...${NC}"
    
    # Create a temporary directory for the DMG contents
    DMG_TEMP="/tmp/cedar-dmg-$$"
    mkdir -p "$DMG_TEMP"
    
    # Copy the app bundle
    cp -r "$BUNDLE_PATH" "$DMG_TEMP/"
    
    # Create a symbolic link to Applications
    ln -s /Applications "$DMG_TEMP/Applications"
    
    # Create the DMG
    DMG_NAME="Cedar-$(date +%Y%m%d).dmg"
    hdiutil create -volname "Cedar" \
        -srcfolder "$DMG_TEMP" \
        -ov -format UDZO \
        "$DMG_NAME"
    
    # Clean up
    rm -rf "$DMG_TEMP"
fi

echo -e "${GREEN}✅ DMG created successfully!${NC}"
echo -e "${GREEN}📦 Output: $(pwd)/$DMG_NAME${NC}"
echo ""
echo "To install Cedar:"
echo "1. Open the DMG file"
echo "2. Drag Cedar.app to your Applications folder"
echo "3. Launch Cedar from Applications"
echo ""
echo -e "${YELLOW}Note: You may need to allow the app in System Preferences > Security & Privacy${NC}"
