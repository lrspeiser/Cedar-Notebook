#!/bin/bash
set -e

echo "📦 Embedding Julia into Cedar app..."

# Configuration
JULIA_VERSION="1.10.0"
JULIA_ARCH="aarch64"  # For Apple Silicon, use "x86_64" for Intel
JULIA_PLATFORM="mac"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Detect architecture if not specified
if [[ $(uname -m) == "arm64" ]]; then
    JULIA_ARCH="aarch64"
    echo -e "${BLUE}Detected Apple Silicon (ARM64)${NC}"
else
    JULIA_ARCH="x86_64"
    echo -e "${BLUE}Detected Intel (x86_64)${NC}"
fi

# Julia download URL
if [[ "$JULIA_ARCH" == "aarch64" ]]; then
    JULIA_URL="https://julialang-s3.julialang.org/bin/mac/aarch64/${JULIA_VERSION%.*}/julia-${JULIA_VERSION}-macaarch64.tar.gz"
else
    JULIA_URL="https://julialang-s3.julialang.org/bin/mac/x64/${JULIA_VERSION%.*}/julia-${JULIA_VERSION}-mac64.tar.gz"
fi

# Create resources directory
RESOURCES_DIR="apps/cedar-bundle/resources"
mkdir -p "$RESOURCES_DIR"

# Download Julia if not already cached
JULIA_ARCHIVE="$RESOURCES_DIR/julia-${JULIA_VERSION}-${JULIA_ARCH}.tar.gz"
if [ ! -f "$JULIA_ARCHIVE" ]; then
    echo -e "${BLUE}Downloading Julia ${JULIA_VERSION} for ${JULIA_ARCH}...${NC}"
    curl -L -o "$JULIA_ARCHIVE" "$JULIA_URL"
else
    echo -e "${GREEN}Using cached Julia archive${NC}"
fi

# Extract Julia
JULIA_DIR="$RESOURCES_DIR/julia"
if [ -d "$JULIA_DIR" ]; then
    echo -e "${YELLOW}Removing existing Julia installation...${NC}"
    rm -rf "$JULIA_DIR"
fi

echo -e "${BLUE}Extracting Julia...${NC}"
mkdir -p "$JULIA_DIR"
tar -xzf "$JULIA_ARCHIVE" -C "$JULIA_DIR" --strip-components=1

# Verify Julia installation
if [ -f "$JULIA_DIR/bin/julia" ]; then
    echo -e "${GREEN}✅ Julia embedded successfully at $JULIA_DIR${NC}"
    "$JULIA_DIR/bin/julia" --version
else
    echo -e "❌ Julia binary not found"
    exit 1
fi

# Create Julia environment for Cedar
echo -e "${BLUE}Setting up Julia environment for Cedar...${NC}"
JULIA_ENV_DIR="$RESOURCES_DIR/julia_env"
mkdir -p "$JULIA_ENV_DIR"

# Create a Project.toml for Cedar dependencies
cat > "$JULIA_ENV_DIR/Project.toml" << 'EOF'
[deps]
CSV = "336ed68f-0bac-5ca0-87d4-7b16caf5d00b"
DataFrames = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0"
JSON = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
Parquet2 = "98572fba-bba0-415d-956f-fa77e587d26d"
Plots = "91a5bcdd-55d7-5caf-9e0b-520d859cae80"
Statistics = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"
HTTP = "cd3eb016-35fb-5094-929b-558a96fad6f3"
EOF

# Pre-compile packages
echo -e "${BLUE}Pre-installing Julia packages...${NC}"
export JULIA_DEPOT_PATH="$JULIA_ENV_DIR/depot"
mkdir -p "$JULIA_DEPOT_PATH"

"$JULIA_DIR/bin/julia" --project="$JULIA_ENV_DIR" -e '
    using Pkg
    Pkg.instantiate()
    Pkg.precompile()
' || echo -e "${YELLOW}Warning: Some packages may not have installed correctly${NC}"

echo -e "${GREEN}✅ Julia environment prepared${NC}"

# Create a wrapper script that Cedar will use
cat > "$RESOURCES_DIR/julia-wrapper.sh" << 'EOF'
#!/bin/bash
# Julia wrapper for Cedar app
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
export JULIA_DEPOT_PATH="$SCRIPT_DIR/julia_env/depot"
export JULIA_PROJECT="$SCRIPT_DIR/julia_env"
exec "$SCRIPT_DIR/julia/bin/julia" "$@"
EOF

chmod +x "$RESOURCES_DIR/julia-wrapper.sh"

echo -e "${GREEN}✅ Julia embedding complete!${NC}"
echo ""
echo "Julia has been embedded with:"
echo "  - Julia ${JULIA_VERSION} for ${JULIA_ARCH}"
echo "  - Pre-installed packages: CSV, DataFrames, JSON, Parquet2, Plots, DuckDB"
echo "  - Wrapper script at: $RESOURCES_DIR/julia-wrapper.sh"
