#!/usr/bin/env bash
# Build script for Render deployment
# This builds only the server component, not the DMG

set -e

echo "==> Building Cedar Server for Render..."

# Install Rust if not present
if ! command -v cargo &> /dev/null; then
    echo "Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source $HOME/.cargo/env
fi

# Build the server binary
echo "==> Building notebook_server..."
cargo build --release --bin notebook_server

echo "==> Build complete!"
echo "Binary location: target/release/notebook_server"
