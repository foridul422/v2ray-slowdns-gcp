#!/bin/bash
# ============================================================
#  Phase 3 — SlowDNS Server Install
#  V2Ray + SlowDNS on Google Cloud Shell
# ============================================================

# ── Load environment ─────────────────────────────────────────
ENV_FILE="$HOME/v2ray-slowdns-gcp/config/env.conf"
if [[ ! -f "$ENV_FILE" ]]; then
    echo "[✘] env.conf not found. Run 01_setup_env.sh first!"
    exit 1
fi
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

banner "Phase 3: SlowDNS Server Install"

# ── 1. Download SlowDNS ─────────────────────────────────────
banner "Downloading SlowDNS"

SLOWDNS_DIR="$INSTALL_DIR/slowdns"
mkdir -p "$SLOWDNS_DIR"

case "$ARCH_NAME" in
    amd64)
        SLOWDNS_DOWNLOAD_URL="https://github.com/flashvpn-org/slowdns/releases/latest/download/server-linux-amd64"
        ;;
    arm64)
        SLOWDNS_DOWNLOAD_URL="https://github.com/flashvpn-org/slowdns/releases/latest/download/server-linux-arm64"
        ;;
    *)
        err "No SlowDNS binary for arch: $ARCH_NAME"
        ;;
esac

info "Downloading SlowDNS binary for $ARCH_NAME..."
wget -q --show-progress -O "$SLOWDNS_DIR/server" "$SLOWDNS_DOWNLOAD_URL" 2>>"$LOG_FILE" || {
    warn "Primary download failed. Trying alternative..."
    if command -v go &>/dev/null; then
        info "Building SlowDNS from source..."
        git clone --depth=1 https://github.com/krlc/slowdns "$SLOWDNS_DIR/src" 2>>"$LOG_FILE"
        cd "$SLOWDNS_DIR/src" && go build -o "$SLOWDNS_DIR/server" ./server/ 2>>"$LOG_FILE"
        cd "$INSTALL_DIR"
    else
        info "Trying mirror download..."
        curl -sL "https://raw.githubusercontent.com/bagaskara815/slowdns/main/server" \
            -o "$SLOWDNS_DIR/server" 2>>"$LOG_FILE" || \
        err "SlowDNS download failed from all sources."
    fi
}

chmod +x "$SLOWDNS_DIR/server"
log "SlowDNS binary ready: $SLOWDNS_DIR/server"

# ── 2. Generate RSA Key Pair ─────────────────────────────────
banner "Generating RSA Keys"

PRIVATE_KEY="$KEYS_DIR/slowdns_private.pem"
PUBLIC_KEY="$KEYS_DIR/slowdns_public.pem"
PUBLIC_KEY_B64="$KEYS_DIR/slowdns_public_b64.txt"

if [[ -f "$PRIVATE_KEY" ]] && [[ -f "$PUBLIC_KEY" ]]; then
    warn "Keys already exist. Skipping generation."
else
    info "Generating 2048-bit RSA key pair..."
    openssl genrsa -out "$PRIVATE_KEY" 2048 2>>"$LOG_FILE"
    openssl rsa -in "$PRIVATE_KEY" -pubout -out "$PUBLIC_KEY" 2>>"$LOG_FILE"
    log "RSA Private Key: $PRIVATE_KEY"
    log "RSA Public Key:  $PUBLIC_KEY"
fi

PUBLIC_KEY_B64_STR=$(openssl rsa -in "$PRIVATE_KEY" -pubout 2>/dev/null \
    | grep -v "BEGIN\|END" | tr -d '\n')
echo "$PUBLIC_KEY_B64_STR" > "$PUBLIC_KEY_B64"
log "Public Key (Base64) saved: $PUBLIC_KEY_B64"

# ── 3. Check UDP port 53 ─────────────────────────────────────
banner "Checking Port 53 (UDP)"

if sudo lsof -iUDP:53 &>/dev/null 2>&1; then
    warn "Port 53 is in use. Trying to free it..."
    if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
        sudo systemctl stop systemd-resolved 2>>"$LOG_FILE"
        sudo systemctl disable systemd-resolved 2>>"$LOG_FILE"
        log "systemd-resolved stopped"
    fi
    sleep 1
fi

if sudo lsof -iUDP:53 &>/dev/null 2>&1; then
    warn "Port 53 still in use by another process (non-critical on some setups)"
else
    log "Port 53 (UDP) is free ✓"
fi

# ── 4. Create start script ───────────────────────────────────
SLOWDNS_START="$INSTALL_DIR/start_slowdns.sh"
cat > "$SLOWDNS_START" << SCRIPT
#!/bin/bash
source "$ENV_FILE"
echo "[SlowDNS] Starting on port 53..."
echo "[SlowDNS] Tunnel domain: $TUNNEL_DOMAIN"
echo "[SlowDNS] Forwarding to: 127.0.0.1:10086 (V2Ray)"

sudo "$SLOWDNS_DIR/server" \\
    -nameserver "$TUNNEL_DOMAIN" \\
    -privkey "$PRIVATE_KEY" \\
    -listen 0.0.0.0:53 \\
    -udpforwardaddr 127.0.0.1:10086 \\
    >> "$OUTPUT_DIR/slowdns.log" 2>&1 &

SLOWDNS_PID=\$!
echo "\$SLOWDNS_PID" > "$INSTALL_DIR/slowdns.pid"
echo "[SlowDNS] Started with PID: \$SLOWDNS_PID"
SCRIPT
chmod +x "$SLOWDNS_START"
log "SlowDNS start script: $SLOWDNS_START"

# ── 5. Launch SlowDNS in screen session ──────────────────────
banner "Starting SlowDNS Server"

screen -S slowdns -X quit &>/dev/null
sleep 1
screen -dmS slowdns bash "$SLOWDNS_START"
sleep 2

if screen -list | grep -q "slowdns"; then
    log "SlowDNS running in screen session 'slowdns' ✓"
else
    warn "SlowDNS screen session not detected. Trying direct launch..."
    bash "$SLOWDNS_START"
fi

# ── 6. Summary ───────────────────────────────────────────────
echo ""
banner "Phase 3 — SlowDNS Complete ✓"
echo -e "  Binary      : ${BOLD}$SLOWDNS_DIR/server${NC}"
echo -e "  Private Key : ${BOLD}$PRIVATE_KEY${NC}"
echo -e "  Public Key  : ${BOLD}$PUBLIC_KEY${NC}"
echo -e "  Tunnel NS   : ${BOLD}$TUNNEL_DOMAIN${NC}"
echo -e "  Forwarding  : ${BOLD}127.0.0.1:10086${NC} (V2Ray)"
echo ""
echo -e "${YELLOW}👉 Next: ${CYAN}bash 04_v2ray_install.sh${NC}"
echo ""
