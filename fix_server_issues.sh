#!/bin/bash

echo "Fixing Cedar Server Issues..."
echo "=============================="

# 1. Fix the multipart dependency
echo "Step 1: Adding multipart support to notebook_server..."
cd /Users/leonardspeiser/Projects/cedarcli

# Check if multipart is already in Cargo.toml
if ! grep -q "axum-multipart" crates/notebook_server/Cargo.toml; then
    echo "Adding axum-multipart dependency..."
    # Add to the dependencies section
    sed -i '' '/\[dependencies\]/a\
axum-multipart = "0.7"\
' crates/notebook_server/Cargo.toml
fi

# 2. Create a startup script that handles API key fetching
echo "Step 2: Creating startup script with API key management..."
cat > start_cedar_server.sh << 'EOF'
#!/bin/bash

echo "Starting Cedar Server..."
echo "========================"

# Load environment variables from .env if it exists
if [ -f .env ]; then
    echo "Loading .env file..."
    export $(cat .env | grep -v '^#' | xargs)
fi

# Try to fetch API key from server if configured
if [ -n "$CEDAR_KEY_URL" ] && [ -n "$APP_SHARED_TOKEN" ]; then
    echo "Fetching API key from server..."
    RESPONSE=$(curl -s -H "x-app-token: $APP_SHARED_TOKEN" "$CEDAR_KEY_URL")
    
    if [ $? -eq 0 ]; then
        # Extract the API key from JSON response
        API_KEY=$(echo "$RESPONSE" | grep -o '"openai_api_key":"[^"]*' | cut -d'"' -f4)
        
        if [ -n "$API_KEY" ]; then
            export OPENAI_API_KEY="$API_KEY"
            echo "✅ API key fetched from server"
        else
            echo "⚠️  Failed to extract API key from server response"
        fi
    else
        echo "⚠️  Failed to fetch API key from server"
    fi
fi

# Check if API key is available from any source
if [ -z "$OPENAI_API_KEY" ]; then
    # Try to get from keychain (macOS)
    if command -v security &> /dev/null; then
        echo "Trying to get API key from keychain..."
        KEYCHAIN_KEY=$(security find-generic-password -s "cedar-cli" -a "OPENAI_API_KEY" -w 2>/dev/null)
        if [ -n "$KEYCHAIN_KEY" ]; then
            export OPENAI_API_KEY="$KEYCHAIN_KEY"
            echo "✅ API key loaded from keychain"
        fi
    fi
fi

# Check if API key is available from config file
if [ -z "$OPENAI_API_KEY" ]; then
    CONFIG_FILE="$HOME/Library/Preferences/com.CedarAI.cedar-cli/.env"
    if [ -f "$CONFIG_FILE" ]; then
        echo "Loading API key from config file..."
        source "$CONFIG_FILE"
        if [ -n "$OPENAI_API_KEY" ]; then
            echo "✅ API key loaded from config file"
        fi
    fi
fi

# Final check
if [ -z "$OPENAI_API_KEY" ]; then
    echo ""
    echo "❌ ERROR: No OpenAI API key found!"
    echo ""
    echo "Please set your API key using one of these methods:"
    echo "1. Set OPENAI_API_KEY in your .env file"
    echo "2. Export OPENAI_API_KEY=your-key-here"
    echo "3. Configure CEDAR_KEY_URL and APP_SHARED_TOKEN for server-based key"
    echo ""
    echo "For more info, see README.md section: 'OpenAI configuration and key flow'"
    exit 1
fi

echo ""
echo "✅ API key configured"
echo "📦 Starting notebook server on http://localhost:8080"
echo ""

# Build if needed
if [ ! -f "target/release/notebook_server" ]; then
    echo "Building notebook_server..."
    cargo build --release --bin notebook_server
fi

# Run the server with the API key set
exec cargo run --release --bin notebook_server
EOF

chmod +x start_cedar_server.sh

# 3. Update the web UI to handle errors better
echo "Step 3: Creating improved web UI error handling..."
cat > apps/web-ui/upload-fix.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Cedar - File Upload Test</title>
    <style>
        body { 
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            max-width: 800px;
            margin: 40px auto;
            padding: 20px;
        }
        .upload-area {
            border: 2px dashed #ccc;
            border-radius: 8px;
            padding: 40px;
            text-align: center;
            cursor: pointer;
            transition: all 0.3s;
        }
        .upload-area:hover {
            border-color: #007AFF;
            background: #f0f8ff;
        }
        .upload-area.dragover {
            border-color: #007AFF;
            background: #e6f3ff;
        }
        button {
            background: #007AFF;
            color: white;
            border: none;
            padding: 10px 20px;
            border-radius: 6px;
            cursor: pointer;
            font-size: 16px;
            margin: 10px;
        }
        button:hover {
            background: #0056b3;
        }
        .status {
            margin: 20px 0;
            padding: 15px;
            border-radius: 6px;
            display: none;
        }
        .status.success {
            background: #d4edda;
            color: #155724;
            border: 1px solid #c3e6cb;
            display: block;
        }
        .status.error {
            background: #f8d7da;
            color: #721c24;
            border: 1px solid #f5c6cb;
            display: block;
        }
        .status.info {
            background: #d1ecf1;
            color: #0c5460;
            border: 1px solid #bee5eb;
            display: block;
        }
        .file-list {
            margin: 20px 0;
            text-align: left;
        }
        .file-item {
            padding: 10px;
            background: #f8f9fa;
            margin: 5px 0;
            border-radius: 4px;
        }
        .instructions {
            background: #fff3cd;
            border: 1px solid #ffeeba;
            color: #856404;
            padding: 15px;
            border-radius: 6px;
            margin-bottom: 20px;
        }
    </style>
</head>
<body>
    <h1>Cedar File Upload Test</h1>
    
    <div class="instructions">
        <strong>⚠️ Before uploading:</strong> Make sure the server is running with:
        <pre>./start_cedar_server.sh</pre>
        This will ensure your API key is properly configured.
    </div>

    <div class="upload-area" id="uploadArea">
        <h2>📁 Drop files here or click to select</h2>
        <p>Supports CSV, Excel, JSON, and Parquet files</p>
        <input type="file" id="fileInput" multiple style="display: none" accept=".csv,.xlsx,.xls,.json,.parquet">
    </div>

    <div class="file-list" id="fileList"></div>
    
    <button onclick="testConnection()">Test Server Connection</button>
    <button onclick="checkApiKey()">Check API Key Status</button>
    
    <div id="status" class="status"></div>

    <script>
        const API_BASE = 'http://localhost:8080';
        const uploadArea = document.getElementById('uploadArea');
        const fileInput = document.getElementById('fileInput');
        const fileList = document.getElementById('fileList');
        const status = document.getElementById('status');

        // Click to select files
        uploadArea.addEventListener('click', () => fileInput.click());
        
        // Handle file selection
        fileInput.addEventListener('change', handleFiles);
        
        // Drag and drop
        uploadArea.addEventListener('dragover', (e) => {
            e.preventDefault();
            uploadArea.classList.add('dragover');
        });
        
        uploadArea.addEventListener('dragleave', () => {
            uploadArea.classList.remove('dragover');
        });
        
        uploadArea.addEventListener('drop', (e) => {
            e.preventDefault();
            uploadArea.classList.remove('dragover');
            handleFiles({ target: { files: e.dataTransfer.files } });
        });

        async function handleFiles(event) {
            const files = Array.from(event.target.files);
            if (files.length === 0) return;
            
            // Display selected files
            fileList.innerHTML = '<h3>Selected Files:</h3>';
            files.forEach(file => {
                const item = document.createElement('div');
                item.className = 'file-item';
                item.textContent = `${file.name} (${(file.size / 1024).toFixed(2)} KB)`;
                fileList.appendChild(item);
            });
            
            // Upload files
            await uploadFiles(files);
        }

        async function uploadFiles(files) {
            showStatus('info', 'Uploading files...');
            
            const formData = new FormData();
            files.forEach(file => formData.append('files', file));
            
            try {
                const response = await fetch(`${API_BASE}/datasets/upload`, {
                    method: 'POST',
                    body: formData
                });
                
                if (!response.ok) {
                    const errorText = await response.text();
                    
                    // Parse error message
                    if (errorText.includes('No API key')) {
                        throw new Error('API key not configured on server. Please restart the server with: ./start_cedar_server.sh');
                    } else if (errorText.includes('multipart')) {
                        throw new Error('Server multipart support issue. Please rebuild the server after running: ./fix_server_issues.sh');
                    } else {
                        throw new Error(errorText || `Upload failed with status ${response.status}`);
                    }
                }
                
                const result = await response.json();
                showStatus('success', `✅ Successfully uploaded ${result.datasets.length} file(s)`);
                
            } catch (error) {
                showStatus('error', `❌ Upload failed: ${error.message}`);
            }
        }

        async function testConnection() {
            try {
                const response = await fetch(`${API_BASE}/health`);
                if (response.ok) {
                    showStatus('success', '✅ Server is running and accessible');
                } else {
                    showStatus('error', '❌ Server responded with error');
                }
            } catch (error) {
                showStatus('error', '❌ Cannot connect to server. Make sure it\'s running on port 8080');
            }
        }

        async function checkApiKey() {
            try {
                // Try a simple query that requires API key
                const response = await fetch(`${API_BASE}/commands/submit_query`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ prompt: 'test' })
                });
                
                if (response.ok) {
                    showStatus('success', '✅ API key is configured on server');
                } else {
                    const error = await response.text();
                    if (error.includes('API key') || error.includes('OPENAI_API_KEY')) {
                        showStatus('error', '❌ API key not configured. Restart server with: ./start_cedar_server.sh');
                    } else {
                        showStatus('error', `❌ Server error: ${error}`);
                    }
                }
            } catch (error) {
                showStatus('error', `❌ Error checking API key: ${error.message}`);
            }
        }

        function showStatus(type, message) {
            status.className = `status ${type}`;
            status.textContent = message;
        }
    </script>
</body>
</html>
EOF

echo ""
echo "✅ Fixes applied!"
echo ""
echo "Next steps:"
echo "1. Rebuild the server to include multipart support:"
echo "   cargo build --release --bin notebook_server"
echo ""
echo "2. Start the server with API key management:"
echo "   ./start_cedar_server.sh"
echo ""
echo "3. Test file upload with the new test page:"
echo "   open apps/web-ui/upload-fix.html"
echo ""
echo "The startup script will:"
echo "  - Load API key from .env file"
echo "  - Or fetch from server if CEDAR_KEY_URL is configured"
echo "  - Or load from keychain if previously cached"
echo "  - Ensure the server has the key before starting"
