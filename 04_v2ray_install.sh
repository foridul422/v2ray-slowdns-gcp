#!/bin/bash
# ============================================================
#  Phase 3 — Xray (VLESS) install & configure
# ============================================================

ENV_FILE="$HOME/v2ray-slowdns-gcp/config/env.conf"
[[ ! -f "$ENV_FILE" ]] && echo "[✘] Run 01_setup_env.sh first!" && exit 1
source "$ENV_FILE"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
log()  { echo -e "${GREEN}[✔]${NC} $1" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YELLOW}[⚠]${NC} $1" | tee -a "$LOG_FILE"; }
err()  { echo -e "${RED}[✘]${NC} $1" | tee -a "$LOG_FILE"; exit 1; }
info() { echo -e "${CYAN}[i]${NC} $1" | tee -a "$LOG_FILE"; }
banner() {
    echo -e "\n${BOLD}${CYAN}═══════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}  $1${NC}"
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════${NC}\n"
}

banner "Phase 3: Xray (VLESS) Install"

V2RAY_DIR="$INSTALL_DIR/xray"
V2RAY_PORT=10086
mkdir -p "$V2RAY_DIR"

case "$ARCH_NAME" in
    amd64) XARCH="64" ;;
    arm64) XARCH="arm64-v8a" ;;
    arm32) XARCH="arm32-v7a" ;;
    *)     err "Unsupported arch" ;;
esac

if [[ ! -x "$V2RAY_DIR/xray" ]]; then
    XVER=$(curl -fsSL "https://api.github.com/repos/XTLS/Xray-core/releases/latest" | jq -r .tag_name 2>/dev/null)
    [[ -z "$XVER" || "$XVER" == "null" ]] && XVER="v1.8.24"
    info "Downloading Xray $XVER..."
    curl -fL --progress-bar -o /tmp/xray.zip "https://github.com/XTLS/Xray-core/releases/download/${XVER}/Xray-linux-${XARCH}.zip" \
        || err "Xray download failed"
    unzip -qo /tmp/xray.zip -d "$V2RAY_DIR" || err "unzip failed"
    chmod +x "$V2RAY_DIR/xray"
fi
log "Xray installed: $V2RAY_DIR/xray"

V2RAY_UUID=$("$V2RAY_DIR/xray" uuid 2>/dev/null)
[[ -z "$V2RAY_UUID" ]] && V2RAY_UUID=$(cat /proc/sys/kernel/random/uuid)
log "UUID: $V2RAY_UUID"

V2RAY_CONFIG="$CONFIG_DIR/xray_config.json"
cat > "$V2RAY_CONFIG" << EOF
{
  "log": { "loglevel": "warning" },
  "dns": {
    "servers": ["8.8.8.8", "1.1.1.1"]
  },
  "inbounds": [{
    "listen": "0.0.0.0",
    "port": $V2RAY_PORT,
    "protocol": "vless",
    "settings": {
      "clients": [{ "id": "$V2RAY_UUID" }],
      "decryption": "none"
    },
    "streamSettings": { "network": "tcp", "security": "none" }
  }],
  "outbounds": [{ "protocol": "freedom" }]
}
EOF
"$V2RAY_DIR/xray" run -test -config "$V2RAY_CONFIG" >>"$LOG_FILE" 2>&1 || err "Xray config test failed — see $LOG_FILE"
log "Config valid: $V2RAY_CONFIG"

{
    echo "V2RAY_UUID=\"$V2RAY_UUID\""
    echo "V2RAY_PORT=\"$V2RAY_PORT\""
    echo "V2RAY_DIR=\"$V2RAY_DIR\""
} >> "$ENV_FILE"

cat > "$INSTALL_DIR/start_v2ray.sh" << STARTSCRIPT
#!/bin/bash
exec "$V2RAY_DIR/xray" run -config "$V2RAY_CONFIG" >> "$OUTPUT_DIR/xray.log" 2>&1
STARTSCRIPT
chmod +x "$INSTALL_DIR/start_v2ray.sh"

screen -S v2ray -X quit &>/dev/null || true
pkill -f "$V2RAY_DIR/xray" &>/dev/null || true
sleep 1
screen -dmS v2ray bash "$INSTALL_DIR/start_v2ray.sh"
sleep 2
if ss -tlnp 2>/dev/null | grep -q ":$V2RAY_PORT "; then
    log "Xray listening on port $V2RAY_PORT ✓"
else
    warn "Xray not listening — check: tail $OUTPUT_DIR/xray.log"
fi

banner "Phase 3 — Complete ✓"
echo -e "  Protocol : ${BOLD}VLESS (tcp, no TLS — wrapped by dnstt)${NC}"
echo -e "  UUID     : ${BOLD}$V2RAY_UUID${NC}"
echo ""
