#!/bin/bash
set -e

# Check configuration provided by deploy.sh.
: "${DATABASE_URL:?DATABASE_URL is required}"
: "${API_REPOSITORY_URL:?API_REPOSITORY_URL is required}"
: "${API_PORT:?API_PORT is required}"

PROJECT_DIR="/opt/journal-starter"

# Install tools needed to download and run the API.
apt-get update
apt-get install -y git curl

# Clone the application repository.
git clone "$API_REPOSITORY_URL" "$PROJECT_DIR"

# Install uv and the project dependencies.
curl -LsSf https://astral.sh/uv/install.sh | sh
export PATH="/root/.local/bin:$PATH"

cd "$PROJECT_DIR"
uv sync

# Configure the database connection used by the API.
printf 'DATABASE_URL=%s\n' "$DATABASE_URL" > .env
printf 'OPENAI_API_KEY=not-used-for-crud\n' >> .env
chmod 600 .env

# Run the API as a background service.
cat > /etc/systemd/system/journal-api.service <<EOF
[Unit]
Description=Journal API
After=network.target

[Service]
WorkingDirectory=$PROJECT_DIR
Environment=PYTHONPATH=$PROJECT_DIR
Environment=PATH=/root/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin
ExecStart=/root/.local/bin/uv run uvicorn api.main:app --host 0.0.0.0 --port $API_PORT
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now journal-api

# Check that the API can connect to the database.
sleep 5
curl --fail "http://localhost:${API_PORT}/entries"

echo
echo "API setup completed."
