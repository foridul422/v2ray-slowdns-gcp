#!/bin/bash
# ============================================================
#  Phase 1 — Environment Setup (No pause, full auto)
#  V2Ray + SlowDNS on Google Cloud Shell / Ubuntu VPS
# ============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

LOG_FILE="$HOME/v2ray-slowdns-gcp/output/install.log"
mkdir -p "$HOME/v2ray-slowdns-gcp/output/keys"
mkdir -p "$HOME/v2ray-slowdns-gcp/config"

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

         V2Ray + SlowDNS | Auto Setup Script
EOF
echo -e "${NC}"

# ── 1. Ask Domain FIRST (so user doesn't wait for apt-get) ──
banner "Step 1: Domain Configuration"

# Flush any leftover Enter keystrokes from pasting command
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
info "এখন বাকি সব অটোমেটিক ইনস্টল হবে, কিছু করতে হবে না..."

# ── 2. Architecture & OS ────────────────────────────────────
banner "Checking System & Installing Tools"

ARCH=$(uname -m)
case "$ARCH" in
    x86_64)   ARCH_NAME="amd64" ;;
    aarch64)  ARCH_NAME="arm64" ;;
    armv7l)   ARCH_NAME="arm32" ;;
    *)        err "Unsupported architecture: $ARCH" ;;
esac
log "Architecture: $ARCH ($ARCH_NAME)"

OS=$(uname -s | tr '[:upper:]' '[:lower:]')
if [[ -n "$CLOUD_SHELL" ]] || [[ -f /etc/google_cloud_shell ]]; then
    IS_CLOUDSHELL=true
else
    IS_CLOUDSHELL=false
fi

# ── 3. Install tools ────────────────────────────────────────
TOOLS=(curl wget unzip openssl jq screen socat)
MISSING=()
for tool in "${TOOLS[@]}"; do
    command -v "$tool" &>/dev/null && log "$tool ✓" || MISSING+=("$tool")
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
    info "Installing packages: ${MISSING[*]}"
    sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq </dev/null 2>>"$LOG_FILE"
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${MISSING[@]}" -qq </dev/null 2>>"$LOG_FILE"
fi

# ── 4. Detect Public IP ──────────────────────────────────────
banner "Detecting Public IP"

PUBLIC_IP=""
for src in "https://ifconfig.me" "https://api.ipify.org" "https://icanhazip.com" "https://ident.me"; do
    IP=$(curl -s --max-time 5 "$src" 2>/dev/null | tr -d '[:space:]')
    if [[ "$IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        PUBLIC_IP="$IP"
        log "Public IP: ${BOLD}$PUBLIC_IP${NC} (via $src)"
        break
    fi
done

if [[ -z "$PUBLIC_IP" ]]; then
    echo -ne "${YELLOW}Could not auto-detect IP. Enter manually: ${NC}"
    read -r PUBLIC_IP </dev/tty
fi

# ── 5. Save env config ──────────────────────────────────────
ENV_FILE="$HOME/v2ray-slowdns-gcp/config/env.conf"
cat > "$ENV_FILE" << EOF
# Auto-generated — Phase 1
PUBLIC_IP="$PUBLIC_IP"
ARCH_NAME="$ARCH_NAME"
OS="$OS"
IS_CLOUDSHELL="$IS_CLOUDSHELL"
LOG_FILE="$LOG_FILE"
INSTALL_DIR="$HOME/v2ray-slowdns-gcp"
CONFIG_DIR="$HOME/v2ray-slowdns-gcp/config"
OUTPUT_DIR="$HOME/v2ray-slowdns-gcp/output"
KEYS_DIR="$HOME/v2ray-slowdns-gcp/output/keys"
USER_DOMAIN="$USER_DOMAIN"
TUNNEL_DOMAIN="$TUNNEL_DOMAIN"
NS_DOMAIN="$NS_DOMAIN"
NS_SUB="$NS_SUB"
TUNNEL_SUB="$TUNNEL_SUB"
EOF

log "Config saved → $ENV_FILE"
