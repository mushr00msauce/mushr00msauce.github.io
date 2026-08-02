#!/usr/bin/env bash

set -euo pipefail

echo "========================================"
echo " Moblink Rust Installer"
echo "========================================"

cd /tmp

TAG="v1.0.0"
BASE="https://github.com/datagutt/moblink-rust/releases/download/$TAG"

echo
echo "Downloading Moblink binaries..."
wget -O moblink-streamer      "$BASE/moblink-streamer-aarch64-unknown-linux-musl"
wget -O moblink-relay-service "$BASE/moblink-relay-service-aarch64-unknown-linux-musl"
wget -O moblink-relay         "$BASE/moblink-relay-aarch64-unknown-linux-musl"

echo
echo "Making binaries executable..."
chmod +x moblink-streamer moblink-relay-service moblink-relay

echo
echo "Installing binaries..."
sudo mv moblink-streamer      /usr/local/bin/moblink-streamer
sudo mv moblink-relay-service /usr/local/bin/moblink-relay-service
sudo mv moblink-relay         /usr/local/bin/moblink-relay

echo
echo "Creating moblink-relay-service systemd service..."
sudo tee /etc/systemd/system/moblink-relay-service.service > /dev/null << 'EOF'
[Unit]
Description=Moblink Relay Service
After=network.target

[Service]
ExecStart=/usr/local/bin/moblink-relay-service --network-interfaces-to-ignore "mob\d+-.*|tailscale.*|docker.*"
Restart=always
User=user

[Install]
WantedBy=multi-user.target
EOF

echo
echo "Creating moblink-streamer systemd service..."
sudo tee /etc/systemd/system/moblink-streamer.service > /dev/null << 'EOF'
[Unit]
Description=Moblink Streamer
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/moblink-streamer --belabox --no-log-timestamps
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

echo
echo "Reloading systemd..."
sudo systemctl daemon-reload

echo
echo "Enabling services..."
sudo systemctl enable moblink-relay-service moblink-streamer

echo
echo "Starting services..."
sudo systemctl start moblink-relay-service moblink-streamer

echo
echo "Checking if relay service is listening on port 7777..."
sudo ss -tlnp | grep 7777 || {
    echo "WARNING: Nothing is listening on port 7777."
    exit 1
}

echo
echo "========================================"
echo " Installation Complete!"
echo "========================================"

echo
echo "Service Status:"
systemctl --no-pager --full status moblink-relay-service --lines=3 || true
echo
systemctl --no-pager --full status moblink-streamer --lines=3 || true