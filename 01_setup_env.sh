#!/bin/bash
# ============================================================
#  Phase 1 — Environment, Domain & Key Generation
#  V2Ray (VLESS) + SlowDNS GCP VM Auto-Deployer
# ============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

INSTALL_DIR="$HOME/v2ray-slowdns-gcp"
CONFIG_DIR="$INSTALL_DIR/config"
OUTPUT_DIR="$INSTALL_DIR/output"
KEYS_DIR="$OUTPUT_DIR/keys"
LOG_FILE="$OUTPUT_DIR/install.log"

mkdir -p "$KEYS_DIR" "$CONFIG_DIR"

log()    { echo -e "${GREEN}[✔]${NC} $1" | tee -a "$LOG_FILE"; }
warn()   { echo -e "${YELLOW}[⚠]${NC} $1" | tee -a "$LOG_FILE"; }
err()    { echo -e "${RED}[✘]${NC} $1" | tee -a "$LOG_FILE"; exit 1; }
info()   { echo -e "${CYAN}[i]${NC} $1" | tee -a "$LOG_FILE"; }
banner() {
    echo -e "\n${BOLD}${CYAN}═══════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}  $1${NC}"
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════${NC}\n"
}

clear
echo -e "${BOLD}${CYAN}"
cat << 'EOF'
 __   ____  ____  __   _  _     ___  __    __   _  _  ____  __ _  _  _ 
 \ \ / /  \/  _ \/ /  | \/ |   / __||  |  /  \ | || ||  _ \|  \ || \/ |
  \ V /   /   __/ /   |    |   \__ \|  |_| () || \/ ||  _ <|     ||    |
   \_/ |_|  \___|_|   |_/\_|   |___/|____|\__/  \__/ |____/|_|\__||_/\_|

      V2Ray (VLESS) + SlowDNS | GCP VM Auto-Deployer
EOF
echo -e "${NC}"

# ── 1. Ask Domain FIRST ─────────────────────────────────────
banner "Step 1: Domain Configuration"

while read -r -t 0.1 -n 10000 _ </dev/tty 2>/dev/null; do :; done

USER_DOMAIN="${1:-}"
while [[ -z "$USER_DOMAIN" ]]; do
    echo -ne "${BOLD}${YELLOW}👉 তোমার Domain নাম লেখো (যেমন: example.com): ${NC}"
    read -r USER_DOMAIN </dev/tty
    USER_DOMAIN=$(echo "$USER_DOMAIN" | tr '[:upper:]' '[:lower:]' | sed 's|^https\?://||; s|^www\.||; s|/.*||; s|[[:space:]]||g')
    if [[ -z "$USER_DOMAIN" || "$USER_DOMAIN" != *.* ]]; then
        warn "সঠিক Domain নাম দাও! (যেমন: mydomain.com)"
        USER_DOMAIN=""
    fi
done

TUNNEL_SUB="tunnel"
NS_SUB="ns1"
TUNNEL_DOMAIN="${TUNNEL_SUB}.${USER_DOMAIN}"
NS_DOMAIN="${NS_SUB}.${USER_DOMAIN}"

log "Domain     : ${BOLD}$USER_DOMAIN${NC}"
log "Tunnel NS  : ${BOLD}$TUNNEL_DOMAIN${NC}"
log "NS Record  : ${BOLD}$NS_DOMAIN${NC}"

# ── 2. Detect GCP Project ID ────────────────────────────────
banner "Detecting GCP Project"

PROJECT_ID=$(gcloud config get-value project 2>/dev/null || true)
[[ "$PROJECT_ID" == "(unset)" ]] && PROJECT_ID=""
if [[ -z "$PROJECT_ID" ]]; then
    err "GCP Project ID পাওয়া যায়নি! আগে Google Cloud Shell-এ প্রজেক্ট সিলেক্ট করো।"
fi
log "GCP Project ID: ${BOLD}$PROJECT_ID${NC}"

# ── 3. Generate dnstt Keys & VLESS UUID ─────────────────────
banner "Generating SlowDNS Keys & VLESS UUID"

PRIV_FILE="$KEYS_DIR/server.key"
PUB_FILE="$KEYS_DIR/server.pub"
UUID_FILE="$KEYS_DIR/vless.uuid"

if [[ -s "$PRIV_FILE" && -s "$PUB_FILE" ]]; then
    DNSTT_PRIVKEY=$(tr -d '[:space:]' < "$PRIV_FILE")
    DNSTT_PUBKEY=$(tr -d '[:space:]' < "$PUB_FILE")
    log "Reusing existing SlowDNS Keypair ✓"
else
    PEM=$(openssl genpkey -algorithm X25519 2>/dev/null)
    DNSTT_PRIVKEY=$(echo "$PEM" | openssl pkey -outform DER 2>/dev/null | tail -c 32 | od -An -tx1 | tr -d ' \n')
    DNSTT_PUBKEY=$(echo "$PEM" | openssl pkey -pubout -outform DER 2>/dev/null | tail -c 32 | od -An -tx1 | tr -d ' \n')
    echo "$DNSTT_PRIVKEY" > "$PRIV_FILE"
    echo "$DNSTT_PUBKEY" > "$PUB_FILE"
    chmod 600 "$PRIV_FILE"
    log "Generated new X25519 SlowDNS Keypair ✓"
fi
log "Public Key : ${BOLD}$DNSTT_PUBKEY${NC}"

if [[ -s "$UUID_FILE" ]]; then
    V2RAY_UUID=$(tr -d '[:space:]' < "$UUID_FILE")
else
    V2RAY_UUID=$(cat /proc/sys/kernel/random/uuid)
    echo "$V2RAY_UUID" > "$UUID_FILE"
fi
V2RAY_PORT=10086
log "VLESS UUID : ${BOLD}$V2RAY_UUID${NC}"

# ── 4. Save env config ──────────────────────────────────────
ENV_FILE="$CONFIG_DIR/env.conf"
cat > "$ENV_FILE" << EOF
PROJECT_ID="$PROJECT_ID"
INSTALL_DIR="$INSTALL_DIR"
CONFIG_DIR="$CONFIG_DIR"
OUTPUT_DIR="$OUTPUT_DIR"
KEYS_DIR="$KEYS_DIR"
LOG_FILE="$LOG_FILE"
USER_DOMAIN="$USER_DOMAIN"
TUNNEL_DOMAIN="$TUNNEL_DOMAIN"
NS_DOMAIN="$NS_DOMAIN"
NS_SUB="$NS_SUB"
TUNNEL_SUB="$TUNNEL_SUB"
DNSTT_PRIVKEY="$DNSTT_PRIVKEY"
DNSTT_PUBKEY="$DNSTT_PUBKEY"
V2RAY_UUID="$V2RAY_UUID"
V2RAY_PORT="$V2RAY_PORT"
VM_NAME="slowdns-v2ray"
EOF

log "Environment config saved ✓"
