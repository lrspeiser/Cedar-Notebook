# Cedar App Icons

This directory contains all icon versions for the Cedar macOS application, generated from the cedar-brain.png image.

## Icon Files

### PNG Files (Individual Sizes)
- `icon_16x16.png` - 16x16 pixels
- `icon_16x16@2x.png` - 32x32 pixels (Retina)
- `icon_32x32.png` - 32x32 pixels
- `icon_32x32@2x.png` - 64x64 pixels (Retina)
- `icon_64x64.png` - 64x64 pixels
- `icon_64x64@2x.png` - 128x128 pixels (Retina)
- `icon_128x128.png` - 128x128 pixels
- `icon_128x128@2x.png` - 256x256 pixels (Retina)
- `icon_256x256.png` - 256x256 pixels
- `icon_256x256@2x.png` - 512x512 pixels (Retina)
- `icon_512x512.png` - 512x512 pixels
- `icon_512x512@2x.png` - 1024x1024 pixels (Retina)

### macOS Icon Files
- `Cedar.icns` - macOS icon bundle containing all sizes
- `Cedar.iconset/` - Directory with individual PNG files used to generate the .icns file

## Usage in Build Scripts

The build scripts automatically copy the appropriate icon files:
- DMG builds use `Cedar.icns` for the app bundle
- The icon is copied to `Cedar.app/Contents/Resources/AppIcon.icns`
- The Info.plist references the icon with `CFBundleIconFile` key

## Regenerating Icons

If you need to regenerate the icons from a new source image:

```bash
# Generate all PNG sizes using sips (macOS built-in tool)
sips -z 16 16 source.png --out icon_16x16.png
sips -z 32 32 source.png --out icon_16x16@2x.png
# ... continue for all sizes

# Create iconset directory
mkdir Cedar.iconset
cp icon_*.png Cedar.iconset/

# Generate .icns file
iconutil -c icns Cedar.iconset -o Cedar.icns
```

## Source Image
The original image is `../cedar-brain.png` (1024x1024 PNG with transparency)
