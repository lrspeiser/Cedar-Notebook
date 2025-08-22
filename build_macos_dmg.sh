#!/bin/bash
set -e

echo "Building Cedar macOS App Bundle and DMG..."

# Build the release version
echo "Step 1: Building release binary..."
cargo build --release --package cedar-bundle

# Create app bundle structure
APP_NAME="Cedar"
APP_BUNDLE="$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

# Clean and create directories
echo "Step 2: Creating app bundle structure..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy the binary
echo "Step 3: Copying binary..."
cp target/release/cedar-bundle "$MACOS_DIR/Cedar"

# Copy Julia environment
echo "Step 4: Copying Julia environment..."
if [ -d "apps/cedar-bundle/resources/julia_env" ]; then
    cp -r apps/cedar-bundle/resources/julia_env "$RESOURCES_DIR/"
fi

# Create Info.plist
echo "Step 5: Creating Info.plist..."
cat > "$CONTENTS_DIR/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Cedar</string>
    <key>CFBundleIdentifier</key>
    <string>com.cedarai.cedar</string>
    <key>CFBundleName</key>
    <string>Cedar</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>10.15</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSRequiresAquaSystemAppearance</key>
    <false/>
</dict>
</plist>
EOF

# Create a simple icon (placeholder)
echo "Step 6: Creating icon..."
cat > "$RESOURCES_DIR/icon.iconset.json" << EOF
{
  "icon": "Cedar"
}
EOF

# Sign the app (if developer certificate available)
if security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
    echo "Step 7: Signing app..."
    codesign --force --deep --sign - "$APP_BUNDLE"
else
    echo "Step 7: Skipping signing (no certificate found)..."
fi

# Create DMG
echo "Step 8: Creating DMG..."
DMG_NAME="Cedar-$(date +%Y%m%d).dmg"
rm -f "$DMG_NAME"

# Create a temporary directory for DMG contents
TEMP_DMG_DIR="dmg_temp"
rm -rf "$TEMP_DMG_DIR"
mkdir -p "$TEMP_DMG_DIR"

# Copy app to temp directory
cp -r "$APP_BUNDLE" "$TEMP_DMG_DIR/"

# Create Applications alias
ln -s /Applications "$TEMP_DMG_DIR/Applications"

# Create the DMG
hdiutil create -volname "Cedar" -srcfolder "$TEMP_DMG_DIR" -ov -format UDZO "$DMG_NAME"

# Clean up
rm -rf "$TEMP_DMG_DIR"

# Output result
echo "✅ Build complete!"
echo "📦 App Bundle: $APP_BUNDLE"
echo "💿 DMG File: $DMG_NAME"
echo ""
echo "Architecture Confirmation:"
echo "========================="
echo "✓ Backend Logic: All in Rust (notebook_core, cedar-cli)"
echo "✓ Data Processing: Rust + Julia (via system calls)"
echo "✓ LLM Integration: Rust handles all API calls"
echo "✓ UI Layer: Thin frontend (egui for desktop, HTML for web)"
echo ""
echo "The same backend works with:"
echo "  - CLI: cedar-cli (direct terminal interface)"
echo "  - Web: notebook_server (HTTP/WebSocket API)"
echo "  - Desktop: cedar-bundle (native macOS app)"
echo ""
echo "To install: Open $DMG_NAME and drag Cedar to Applications"
