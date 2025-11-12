#!/bin/bash

set -euo pipefail

# Configuration
OPENWEBUI_PORT="${OPENWEBUI_PORT:-3333}"
LM_STUDIO_PORT="${LM_STUDIO_PORT:-1234}"

# === DEFAULT CONSTANTS ===
PROJECT_DIR="$HOME/open-webui"

echo "🚀 Starting Open WebUI Setup ..."

# === 1. Define Project Directory ===
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

# === 3. Create docker-compose.yml (Only Open WebUI, Connects to LM Studio) ===
cat > docker-compose.yml << EOF
services:
  openwebui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: openwebui
    restart: unless-stopped
    ports:
      - "$OPENWEBUI_PORT:8080"
    environment:
      # Connect to your LM Studio API
      - OLLAMA_BASE_URL=http://localhost:$LM_STUDIO_PORT/v1
      - WEBUI_HOST=0.0.0.0
      - WEBUI_PORT=8080
      - WEBUI_SECRET_KEY=your-very-secret-key-change-this-in-prod  # 🔐 Change in production!
      - DEBUG=true
    volumes:
      - openwebui_data:/app/backend/data
      # - ./models:/app/models  # Optional: Mount GGUF models for local use
    # No depends_on needed — Open WebUI connects to external LM Studio

volumes:
  openwebui_data:
EOF

echo "✅ docker-compose.yml created. Connected to LM Studio at http://localhost:$LM_STUDIO_PORT/v1."

# === 4. Create Start Script (One-Click) ===
cat > start_openwebui.sh << EOF
#!/bin/bash
cd "$HOME/open-webui"

docker compose up -d
echo "🚀 Open WebUI is now running at http://localhost:$OPENWEBUI_PORT"
echo "🔗 Connected to LM Studio API at http://localhost:$LM_STUDIO_PORT/v1"
EOF

chmod +x start_openwebui.sh

# === 5. Start Services ===
echo "🚀 Starting Open WebUI..."
docker compose up -d

sleep 10 # Wait for service to initialize

if docker ps | grep openwebui > /dev/null; then
    echo "✅ Open WebUI is running and connected to LM Studio!"
else
    echo "❌ Failed to start. Check logs with: docker compose logs"
    exit 1
fi

# === 6. Final Instructions ===
echo ""
echo "🎉 SUCCESS! Open WebUI installed successfully."
echo ""
echo "🔹 Access the UI at: http://localhost:$OPENWEBUI_PORT"
echo ""
echo "🔗 Connected to LM Studio API at: http://localhost:$LM_STUDIO_PORT/v1"
echo ""
echo "🔧 To manage your instance:"
echo "   - Start:  ./start_openwebui.sh"
echo "   - Stop:   docker compose down"
echo "   - Logs:   docker compose logs -f"
echo ""
echo "🔐 IMPORTANT: Change WEBUI_SECRET_KEY and admin password in docker-compose.yml!"
echo "🛠️  Tool Calling & MCP Support:"
echo "   - Enable function calling in Open WebUI prompt via JSON schema."
echo "   - Set custom endpoints under Settings > API for MCP servers or proxies."
echo ""
echo "💡 Tip: LM Studio must be running before starting Open WebUI. Start it with 'lmstudio' command from terminal."

# Start openwebui
echo "Starting via start_openwebui.sh now ..."
./start_openwebui.sh