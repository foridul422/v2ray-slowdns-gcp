#!/bin/bash
# ============================================================
#  Phase 3 — SlowDNS (DNSTT) Server Install
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

banner "Phase 3: SlowDNS (DNSTT) Server Install"

# ─────────────────────────────────────────────────────────────
# 1. Download DNSTT/SlowDNS binary
# ─────────────────────────────────────────────────────────────
banner "Downloading DNSTT Server Binary"

SLOWDNS_DIR="$INSTALL_DIR/slowdns"
mkdir -p "$SLOWDNS_DIR"
SERVER_BIN="$SLOWDNS_DIR/server"

# Helper: download & verify binary (must be >50KB)
try_download() {
    local url="$1"
    local dest="$2"
    info "Trying: $url"
    curl -fsSL --max-time 40 --retry 2 -o "$dest" "$url" 2>>"$LOG_FILE" || return 1
    local size
    size=$(stat -c%s "$dest" 2>/dev/null || echo 0)
    if [[ "$size" -gt 50000 ]]; then
        return 0
    fi
    warn "File too small (${size}B), skipping"
    rm -f "$dest"
    return 1
}

BINARY_DOWNLOADED=false

# ── Attempt 1: Known working direct binary URLs ───────────────
info "Trying pre-built binaries..."
BINARY_URLS=(
    "https://github.com/powermx/dnstt/raw/main/dnstt-server"
    "https://github.com/jamesdev0353/dnstt-allport/raw/main/dnstt-server"
    "https://github.com/fisabiliyusri/slowdns/raw/main/server"
    "https://github.com/bagaskara815/slowdns/raw/main/server"
    "https://github.com/stellawills/slowdns/raw/main/server"
)

for url in "${BINARY_URLS[@]}"; do
    if try_download "$url" "$SERVER_BIN"; then
        BINARY_DOWNLOADED=true
        log "Downloaded from: $url"
        break
    fi
done

# ── Attempt 2: Build from source (download zip — no git auth) ─
if [[ "$BINARY_DOWNLOADED" == false ]]; then
    warn "All pre-built binaries failed. Building from source..."

    # Install Go if not present
    if ! command -v go &>/dev/null; then
        info "Installing Go 1.22.3..."
        curl -fsSL "https://go.dev/dl/go1.22.3.linux-amd64.tar.gz" -o /tmp/go.tar.gz
        sudo tar -C /usr/local -xzf /tmp/go.tar.gz 2>>"$LOG_FILE"
        export PATH="$PATH:/usr/local/go/bin"
    fi

    if command -v go &>/dev/null; then
        log "Go: $(go version)"

        ZIP_URLS=(
            "https://github.com/powermx/dnstt/archive/refs/heads/main.zip"
            "https://github.com/jamesdev0353/dnstt-allport/archive/refs/heads/main.zip"
        )

        for zip_url in "${ZIP_URLS[@]}"; do
            info "Downloading source: $zip_url"
            if curl -fsSL --max-time 90 -o /tmp/dnstt_src.zip "$zip_url" 2>>"$LOG_FILE"; then
                rm -rf /tmp/dnstt_build
                mkdir -p /tmp/dnstt_build
                unzip -q /tmp/dnstt_src.zip -d /tmp/dnstt_build 2>>"$LOG_FILE"
                SRC_DIR=$(find /tmp/dnstt_build -maxdepth 1 -mindepth 1 -type d | head -1)
                info "Source dir: $SRC_DIR"
                cd "$SRC_DIR"

                if [[ -d "dnstt-server" ]]; then
                    go build -o "$SERVER_BIN" ./dnstt-server/ 2>>"$LOG_FILE" && BINARY_DOWNLOADED=true
                elif [[ -d "server" ]]; then
                    go build -o "$SERVER_BIN" ./server/ 2>>"$LOG_FILE" && BINARY_DOWNLOADED=true
                else
                    go build -o "$SERVER_BIN" . 2>>"$LOG_FILE" && BINARY_DOWNLOADED=true
                fi

                cd "$INSTALL_DIR"
                [[ "$BINARY_DOWNLOADED" == true ]] && break
            fi
        done
    fi
fi

[[ "$BINARY_DOWNLOADED" == false ]] && err "Could not download or build DNSTT binary!"

chmod +x "$SERVER_BIN"
log "Binary ready: $SERVER_BIN"
log "File type: $(file "$SERVER_BIN" 2>/dev/null | cut -d: -f2)"

# ─────────────────────────────────────────────────────────────
# 2. Generate RSA Key Pair
# ─────────────────────────────────────────────────────────────
banner "Generating RSA Keys"

PRIVATE_KEY="$KEYS_DIR/slowdns_private.pem"
PUBLIC_KEY="$KEYS_DIR/slowdns_public.pem"
PUBLIC_KEY_B64_FILE="$KEYS_DIR/slowdns_public_b64.txt"

if [[ -f "$PRIVATE_KEY" ]] && [[ -f "$PUBLIC_KEY" ]]; then
    warn "Keys already exist. Skipping."
else
    info "Generating 2048-bit RSA key pair..."
    openssl genrsa -out "$PRIVATE_KEY" 2048 2>>"$LOG_FILE"
    openssl rsa -in "$PRIVATE_KEY" -pubout -out "$PUBLIC_KEY" 2>>"$LOG_FILE"
    log "Private Key: $PRIVATE_KEY"
    log "Public Key:  $PUBLIC_KEY"
fi

PUBLIC_KEY_B64_STR=$(openssl rsa -in "$PRIVATE_KEY" -pubout 2>/dev/null \
    | grep -v "BEGIN\|END" | tr -d '\n')
echo "$PUBLIC_KEY_B64_STR" > "$PUBLIC_KEY_B64_FILE"
log "Public Key (Base64) saved"

# ─────────────────────────────────────────────────────────────
# 3. Detect binary type (dnstt vs classic slowdns)
# ─────────────────────────────────────────────────────────────
banner "Detecting Binary Type"

BINARY_HELP=$("$SERVER_BIN" -help 2>&1 || "$SERVER_BIN" --help 2>&1 || true)

if echo "$BINARY_HELP" | grep -qi "udp\|privkey-file\|dnstt"; then
    BINARY_TYPE="dnstt"
    log "Binary type: DNSTT"
elif echo "$BINARY_HELP" | grep -qi "nameserver\|privkey"; then
    BINARY_TYPE="slowdns"
    log "Binary type: SlowDNS (classic)"
else
    BINARY_TYPE="dnstt"
    warn "Could not detect type, defaulting to: dnstt"
fi

# Save to env
{
    echo "BINARY_TYPE=\"$BINARY_TYPE\""
    echo "SLOWDNS_DIR=\"$SLOWDNS_DIR\""
    echo "SERVER_BIN=\"$SERVER_BIN\""
    echo "PRIVATE_KEY=\"$PRIVATE_KEY\""
    echo "PUBLIC_KEY=\"$PUBLIC_KEY\""
} >> "$ENV_FILE"

# ─────────────────────────────────────────────────────────────
# 4. Check port 53
# ─────────────────────────────────────────────────────────────
banner "Checking Port 53 (UDP)"

if ss -ulnp 2>/dev/null | grep -q ":53 "; then
    warn "Port 53 in use. Trying to free it..."
    if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
        sudo systemctl stop systemd-resolved 2>>"$LOG_FILE"
        sudo systemctl disable systemd-resolved 2>>"$LOG_FILE"
        log "systemd-resolved stopped"
    fi
    sleep 1
fi
log "Port 53 check done ✓"

# ─────────────────────────────────────────────────────────────
# 5. Create start script
# ─────────────────────────────────────────────────────────────
SLOWDNS_START="$INSTALL_DIR/start_slowdns.sh"

cat > "$SLOWDNS_START" << 'STARTSCRIPT'
#!/bin/bash
ENV_FILE="$HOME/v2ray-slowdns-gcp/config/env.conf"
source "$ENV_FILE"

echo "[SlowDNS] Starting | domain: $TUNNEL_DOMAIN | fwd: 127.0.0.1:10086"

if [[ "$BINARY_TYPE" == "dnstt" ]]; then
    sudo "$SERVER_BIN" \\
        -udp 0.0.0.0:53 \\
        -privkey-file "$PRIVATE_KEY" \\
        "$TUNNEL_DOMAIN=127.0.0.1:10086" \\
        >> "$OUTPUT_DIR/slowdns.log" 2>&1 &
else
    sudo "$SERVER_BIN" \\
        -nameserver "$TUNNEL_DOMAIN" \\
        -privkey "$PRIVATE_KEY" \\
        -listen 0.0.0.0:53 \\
        -udpforwardaddr 127.0.0.1:10086 \\
        >> "$OUTPUT_DIR/slowdns.log" 2>&1 &
fi

SPID=$!
echo "$SPID" > "$INSTALL_DIR/slowdns.pid"
echo "[SlowDNS] PID: $SPID"
STARTSCRIPT

chmod +x "$SLOWDNS_START"
log "Start script: $SLOWDNS_START"

# ─────────────────────────────────────────────────────────────
# 6. Launch in screen session
# ─────────────────────────────────────────────────────────────
banner "Starting SlowDNS Server"

screen -S slowdns -X quit &>/dev/null 2>&1 || true
sleep 1
screen -dmS slowdns bash "$SLOWDNS_START"
sleep 2

if screen -list 2>/dev/null | grep -q "slowdns"; then
    log "SlowDNS running in screen session 'slowdns' ✓"
else
    warn "Screen not detected. Launching directly..."
    bash "$SLOWDNS_START" &
fi

# ─────────────────────────────────────────────────────────────
# 7. Summary
# ─────────────────────────────────────────────────────────────
echo ""
banner "Phase 3 — SlowDNS Complete ✓"
echo -e "  Binary   : ${BOLD}$SERVER_BIN${NC}"
echo -e "  Type     : ${BOLD}$BINARY_TYPE${NC}"
echo -e "  Tunnel   : ${BOLD}$TUNNEL_DOMAIN${NC}"
echo -e "  Forward  : ${BOLD}127.0.0.1:10086${NC} (V2Ray)"
echo ""
echo -e "${YELLOW}👉 Next: ${CYAN}bash 04_v2ray_install.sh${NC}"
echo ""
