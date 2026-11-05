#!/bin/bash
# ============================================================
#  Phase 1 — Environment Setup (No pause, full auto)
#  V2Ray + SlowDNS on Google Cloud Shell
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

         V2Ray + SlowDNS | Google Cloud Shell Setup
EOF
echo -e "${NC}"

banner "Phase 1: Environment Setup"

# ── 1. Architecture ─────────────────────────────────────────
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)   ARCH_NAME="amd64" ;;
    aarch64)  ARCH_NAME="arm64" ;;
    armv7l)   ARCH_NAME="arm32" ;;
    *)        err "Unsupported architecture: $ARCH" ;;
esac
log "Architecture: $ARCH ($ARCH_NAME)"

OS=$(uname -s | tr '[:upper:]' '[:lower:]')
log "OS: $OS"

if [[ -n "$CLOUD_SHELL" ]] || [[ -f /etc/google_cloud_shell ]]; then
    log "Running inside Google Cloud Shell ✓"
    IS_CLOUDSHELL=true
else
    warn "Not GCP Cloud Shell — continuing anyway"
    IS_CLOUDSHELL=false
fi

# ── 2. Install tools ────────────────────────────────────────
banner "Installing required tools"

TOOLS=(curl wget unzip openssl jq screen socat)
MISSING=()
for tool in "${TOOLS[@]}"; do
    command -v "$tool" &>/dev/null && log "$tool ✓" || MISSING+=("$tool")
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
    info "Installing: ${MISSING[*]}"
    sudo apt-get update -qq 2>>"$LOG_FILE"
    sudo apt-get install -y "${MISSING[@]}" -qq 2>>"$LOG_FILE"
fi

# ── 3. Detect Public IP ──────────────────────────────────────
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
    read -r PUBLIC_IP
fi

# ── 4. Get domain info ──────────────────────────────────────
banner "Domain Configuration"

echo -ne "${CYAN}তোমার domain enter করো${NC} (example: yourdomain.com): "
read -r USER_DOMAIN
USER_DOMAIN=$(echo "$USER_DOMAIN" | tr '[:upper:]' '[:lower:]' | sed 's/^www\.//')

echo -ne "${CYAN}Tunnel subdomain${NC} [default: tunnel]: "
read -r TUNNEL_SUB
TUNNEL_SUB=${TUNNEL_SUB:-tunnel}

echo -ne "${CYAN}NS subdomain${NC} [default: ns1]: "
read -r NS_SUB
NS_SUB=${NS_SUB:-ns1}

TUNNEL_DOMAIN="${TUNNEL_SUB}.${USER_DOMAIN}"
NS_DOMAIN="${NS_SUB}.${USER_DOMAIN}"

log "Domain: $USER_DOMAIN"
log "Tunnel: $TUNNEL_DOMAIN"
log "NS    : $NS_DOMAIN → $PUBLIC_IP"

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

echo ""
banner "Phase 1 — Complete ✓"
echo -e "  IP     : ${BOLD}$PUBLIC_IP${NC}"
echo -e "  Domain : ${BOLD}$USER_DOMAIN${NC}"
echo -e "  Tunnel : ${BOLD}$TUNNEL_DOMAIN${NC}"
echo ""
echo -e "${CYAN}[i] NS record info will be shown at the END of setup.${NC}"
echo ""
