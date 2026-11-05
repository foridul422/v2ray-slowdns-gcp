#!/bin/bash
# ============================================================
#  Phase 4 — V2Ray Install & Configure
#  V2Ray + SlowDNS on Google Cloud Shell
# ============================================================

# ── Load environment ─────────────────────────────────────────
ENV_FILE="$HOME/v2ray-slowdns-gcp/config/env.conf"
[[ ! -f "$ENV_FILE" ]] && echo "[✘] Run 01_setup_env.sh first!" && exit 1
source "$ENV_FILE"

# ── Colors ───────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log()    { echo -e "${GREEN}[✔]${NC} $1" | tee -a "$LOG_FILE"; }
warn()   { echo -e "${YELLOW}[⚠]${NC} $1" | tee -a "$LOG_FILE"; }
err()    { echo -e "${RED}[✘]${NC} $1" | tee -a "$LOG_FILE"; exit 1; }
info()   { echo -e "${CYAN}[i]${NC} $1" | tee -a "$LOG_FILE"; }
banner() {
    echo -e "\n${BOLD}${CYAN}═══════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}  $1${NC}"
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════${NC}\n"
}

banner "Phase 4: V2Ray Install & Configure"

# ── 1. Download V2Ray ────────────────────────────────────────
banner "Downloading V2Ray"

V2RAY_DIR="$INSTALL_DIR/v2ray"
mkdir -p "$V2RAY_DIR"

V2RAY_VERSION=$(curl -s "https://api.github.com/repos/v2fly/v2ray-core/releases/latest" \
    | jq -r '.tag_name' 2>/dev/null)
V2RAY_VERSION=${V2RAY_VERSION:-"v5.16.0"}
info "V2Ray version: $V2RAY_VERSION"

case "$ARCH_NAME" in
    amd64)  V2RAY_ARCH="64"         ;;
    arm64)  V2RAY_ARCH="arm64-v8a" ;;
    arm32)  V2RAY_ARCH="arm32-v7a" ;;
    *)      V2RAY_ARCH="64"         ;;
esac

V2RAY_ZIP="v2ray-linux-${V2RAY_ARCH}.zip"
V2RAY_URL="https://github.com/v2fly/v2ray-core/releases/download/${V2RAY_VERSION}/${V2RAY_ZIP}"

info "Downloading: $V2RAY_URL"
wget -q --show-progress -O "/tmp/$V2RAY_ZIP" "$V2RAY_URL" 2>>"$LOG_FILE" || \
    err "V2Ray download failed!"

unzip -o "/tmp/$V2RAY_ZIP" -d "$V2RAY_DIR" >>"$LOG_FILE" 2>&1
chmod +x "$V2RAY_DIR/v2ray"
log "V2Ray installed: $V2RAY_DIR/v2ray"

# ── 2. Generate UUID ─────────────────────────────────────────
banner "Generating V2Ray UUID"

V2RAY_UUID=$("$V2RAY_DIR/v2ray" uuid 2>/dev/null)
if [[ -z "$V2RAY_UUID" ]]; then
    V2RAY_UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || \
                 openssl rand -hex 16 | sed 's/\(.\{8\}\)\(.\{4\}\)\(.\{4\}\)\(.\{4\}\)\(.*\)/\1-\2-\3-\4-\5/')
fi
log "UUID generated: $V2RAY_UUID"

# ── 3. Create V2Ray config.json ──────────────────────────────
banner "Creating V2Ray Config"

V2RAY_PORT=10086
V2RAY_CONFIG="$CONFIG_DIR/v2ray_config.json"

cat > "$V2RAY_CONFIG" << EOF
{
  "log": {
    "loglevel": "warning",
    "access": "$OUTPUT_DIR/v2ray_access.log",
    "error": "$OUTPUT_DIR/v2ray_error.log"
  },
  "inbounds": [
    {
      "port": $V2RAY_PORT,
      "listen": "127.0.0.1",
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "$V2RAY_UUID",
            "alterId": 0,
            "security": "auto"
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "tcpSettings": {
          "header": {
            "type": "none"
          }
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ],
  "routing": {
    "rules": []
  }
}
EOF
log "V2Ray config saved: $V2RAY_CONFIG"

# ── 4. Save V2Ray info to env ────────────────────────────────
cat >> "$ENV_FILE" << EOF
V2RAY_UUID="$V2RAY_UUID"
V2RAY_PORT="$V2RAY_PORT"
V2RAY_DIR="$V2RAY_DIR"
V2RAY_CONFIG="$V2RAY_CONFIG"
EOF

# ── 5. Create start script ───────────────────────────────────
V2RAY_START="$INSTALL_DIR/start_v2ray.sh"
cat > "$V2RAY_START" << SCRIPT
#!/bin/bash
source "$ENV_FILE"
echo "[V2Ray] Starting on 127.0.0.1:$V2RAY_PORT..."
"$V2RAY_DIR/v2ray" run -config "$V2RAY_CONFIG" >> "$OUTPUT_DIR/v2ray.log" 2>&1 &
V2RAY_PID=\$!
echo "\$V2RAY_PID" > "$INSTALL_DIR/v2ray.pid"
echo "[V2Ray] Started with PID: \$V2RAY_PID"
SCRIPT
chmod +x "$V2RAY_START"
log "V2Ray start script: $V2RAY_START"

# ── 6. Launch V2Ray in screen session ────────────────────────
banner "Starting V2Ray Server"

screen -S v2ray -X quit &>/dev/null
sleep 1
screen -dmS v2ray bash "$V2RAY_START"
sleep 2

if screen -list | grep -q "v2ray"; then
    log "V2Ray running in screen session 'v2ray' ✓"
else
    warn "Starting V2Ray directly..."
    bash "$V2RAY_START"
fi

sleep 2

if ss -tlnp | grep -q ":$V2RAY_PORT" 2>/dev/null || \
   netstat -tlnp 2>/dev/null | grep -q ":$V2RAY_PORT"; then
    log "V2Ray listening on 127.0.0.1:$V2RAY_PORT ✓"
else
    warn "Could not verify V2Ray port (may still be starting...)"
fi

# ── 7. Summary ───────────────────────────────────────────────
echo ""
banner "Phase 4 — V2Ray Complete ✓"
echo -e "  Port    : ${BOLD}127.0.0.1:$V2RAY_PORT${NC}"
echo -e "  Protocol: ${BOLD}VMess${NC}"
echo -e "  UUID    : ${BOLD}$V2RAY_UUID${NC}"
echo ""
echo -e "${YELLOW}👉 Next: ${CYAN}bash 07_client_config.sh${NC}"
echo ""
