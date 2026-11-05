#!/bin/bash
# ============================================================
#  Phase 2 — SlowDNS (dnstt) server install
#  Uses the OFFICIAL dnstt source (www.bamsoftware.com) via the Go module proxy.
#  dnstt keys are Noise/Curve25519 (hex) — NOT RSA.
# ============================================================

ENV_FILE="$HOME/v2ray-slowdns-gcp/config/env.conf"
[[ ! -f "$ENV_FILE" ]] && echo "[✘] env.conf not found. Run 01_setup_env.sh first!" && exit 1
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

banner "Phase 2: SlowDNS (dnstt) Server"

SLOWDNS_DIR="$INSTALL_DIR/slowdns"
SERVER_BIN="$SLOWDNS_DIR/dnstt-server"
mkdir -p "$SLOWDNS_DIR"

# ── 1. Go toolchain (no sudo needed) ────────────────────────
if ! command -v go &>/dev/null; then
    [[ -x "$HOME/go-sdk/go/bin/go" ]] || {
        info "Installing Go into ~/go-sdk ..."
        case "$ARCH_NAME" in amd64) GOARCH=amd64;; arm64) GOARCH=arm64;; *) err "Unsupported arch";; esac
        mkdir -p "$HOME/go-sdk"
        curl -fsSL "https://go.dev/dl/go1.22.5.linux-${GOARCH}.tar.gz" | tar -C "$HOME/go-sdk" -xz \
            || err "Go download failed"
    }
    export PATH="$HOME/go-sdk/go/bin:$PATH"
fi
log "Go: $(go version)"

# ── 2. Build dnstt-server from the official module ──────────
if [[ ! -x "$SERVER_BIN" ]]; then
    info "Building dnstt-server (official source)..."
    GIT_TERMINAL_PROMPT=0 GOPROXY="https://proxy.golang.org,direct" GOBIN="$SLOWDNS_DIR" \
        go install www.bamsoftware.com/git/dnstt.git/dnstt-server@latest 2>>"$LOG_FILE" \
        || err "dnstt build failed — see $LOG_FILE"
fi
[[ -x "$SERVER_BIN" ]] || err "dnstt-server binary missing after build"
log "Binary ready: $SERVER_BIN"

# ── 3. Generate dnstt keypair ───────────────────────────────
banner "Generating dnstt Keys"
PRIVATE_KEY="$KEYS_DIR/server.key"
PUBLIC_KEY="$KEYS_DIR/server.pub"
if [[ -s "$PRIVATE_KEY" && -s "$PUBLIC_KEY" ]]; then
    warn "Keys already exist — reusing"
else
    "$SERVER_BIN" -gen-key -privkey-file "$PRIVATE_KEY" -pubkey-file "$PUBLIC_KEY" >>"$LOG_FILE" 2>&1 \
        || err "Key generation failed"
fi
chmod 600 "$PRIVATE_KEY"
DNSTT_PUBKEY=$(tr -d '[:space:]' < "$PUBLIC_KEY")
log "Public key: $DNSTT_PUBKEY"

# ── 4. Start script ─────────────────────────────────────────
DNS_PORT=53
V2RAY_PORT=10086
{
    echo "DNSTT_PUBKEY=\"$DNSTT_PUBKEY\""
    echo "SERVER_BIN=\"$SERVER_BIN\""
    echo "PRIVATE_KEY=\"$PRIVATE_KEY\""
    echo "DNS_PORT=\"$DNS_PORT\""
} >> "$ENV_FILE"

cat > "$INSTALL_DIR/start_slowdns.sh" << 'STARTSCRIPT'
#!/bin/bash
source "$HOME/v2ray-slowdns-gcp/config/env.conf"
echo "[dnstt] domain=$TUNNEL_DOMAIN udp=:$DNS_PORT -> 127.0.0.1:10086"
exec sudo "$SERVER_BIN" -udp ":$DNS_PORT" -privkey-file "$PRIVATE_KEY" \
    "$TUNNEL_DOMAIN" 127.0.0.1:10086 >> "$OUTPUT_DIR/slowdns.log" 2>&1
STARTSCRIPT
chmod +x "$INSTALL_DIR/start_slowdns.sh"

# ── 5. Free port 53 if needed, then launch in screen ────────
if ss -ulnp 2>/dev/null | grep -q ":53 "; then
    warn "UDP 53 already in use"
    if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
        sudo systemctl stop systemd-resolved 2>>"$LOG_FILE" && log "Stopped systemd-resolved"
    fi
fi

screen -S slowdns -X quit &>/dev/null || true
screen -dmS slowdns bash "$INSTALL_DIR/start_slowdns.sh"
sleep 3
if ss -ulnp 2>/dev/null | grep -q ":$DNS_PORT "; then
    log "dnstt-server listening on UDP :$DNS_PORT ✓"
else
    warn "dnstt-server not listening yet — check: tail $OUTPUT_DIR/slowdns.log"
fi

banner "Phase 2 — Complete ✓"
echo -e "  Tunnel domain : ${BOLD}$TUNNEL_DOMAIN${NC}"
echo -e "  Forward to    : ${BOLD}127.0.0.1:$V2RAY_PORT${NC} (Xray VLESS)"
echo ""
