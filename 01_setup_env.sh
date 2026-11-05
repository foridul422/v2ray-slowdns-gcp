#!/bin/bash
# ============================================================
#  Phase 1 — Environment, GCP Project & Key Generation
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

# ── 1. Detect Active GCP Project ID ─────────────────────────
banner "Detecting GCP Project"

CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null || true)
[[ "$CURRENT_PROJECT" == "(unset)" ]] && CURRENT_PROJECT=""

ALL_PROJECTS=$(gcloud projects list --format="value(projectId)" 2>/dev/null || true)
PROJECT_ID=""

# 1st pass: Pick a project where user has Editor/Owner/Compute Admin role or an existing VM
for P in $ALL_PROJECTS $CURRENT_PROJECT; do
    [[ -z "$P" ]] && continue
    ROLES=$(gcloud projects get-iam-policy "$P" --flatten="bindings[].members" --format="value(bindings.role)" 2>/dev/null || true)
    if echo "$ROLES" | grep -qiE "editor|owner|compute\.admin|compute\.instanceAdmin"; then
        PROJECT_ID="$P"
        break
    fi
done

# 2nd pass: Fallback to any project where compute zones list works
if [[ -z "$PROJECT_ID" ]]; then
    for P in $ALL_PROJECTS $CURRENT_PROJECT; do
        [[ -z "$P" ]] && continue
        if gcloud compute zones list --project="$P" --limit=1 --quiet >/dev/null 2>&1; then
            PROJECT_ID="$P"
            break
        fi
    done
fi

if [[ -z "$PROJECT_ID" ]]; then
    PROJECT_ID=$(echo "$ALL_PROJECTS" | head -n 1)
    [[ -z "$PROJECT_ID" ]] && PROJECT_ID="$CURRENT_PROJECT"
fi

if [[ -z "$PROJECT_ID" ]]; then
    err "কোনো অ্যাক্টিভ GCP Project পাওয়া যায়নি! নতুন ল্যাব স্টার্ট করে আবার চেষ্টা করো।"
fi

gcloud config set project "$PROJECT_ID" --quiet 2>/dev/null || true
log "GCP Project ID: ${BOLD}$PROJECT_ID${NC}"

# ── 2. Fixed Permanent dnstt Keys & VLESS UUID (No need to copy every time!) ──
banner "Setting Permanent SlowDNS Keys & VLESS UUID"

PRIV_FILE="$KEYS_DIR/server.key"
PUB_FILE="$KEYS_DIR/server.pub"
UUID_FILE="$KEYS_DIR/vless.uuid"

# Permanent X25519 keypair & UUID so V2RayNG / NekoBox / Termux config NEVER changes across VMs!
DNSTT_PRIVKEY="8495481fe11a602c664c4b923dc115437507022f4bd4bef890e08ba3dcfe7659"
DNSTT_PUBKEY="58a0eeb51c71ad9fe39997ded7cf4e1f9700d497edd47af5c2c42a66611bc34c"
V2RAY_UUID="60c44ed2-4dd4-43ab-9a66-a0b40623a1d4"
V2RAY_PORT=10086

echo "$DNSTT_PRIVKEY" > "$PRIV_FILE"
echo "$DNSTT_PUBKEY" > "$PUB_FILE"
echo "$V2RAY_UUID" > "$UUID_FILE"
chmod 600 "$PRIV_FILE"

log "Public Key : ${BOLD}$DNSTT_PUBKEY${NC}"
log "VLESS UUID : ${BOLD}$V2RAY_UUID${NC}"

# ── 3. Save env config (NO domain yet!) ─────────────────────
ENV_FILE="$CONFIG_DIR/env.conf"
cat > "$ENV_FILE" << EOF
PROJECT_ID="$PROJECT_ID"
INSTALL_DIR="$INSTALL_DIR"
CONFIG_DIR="$CONFIG_DIR"
OUTPUT_DIR="$OUTPUT_DIR"
KEYS_DIR="$KEYS_DIR"
LOG_FILE="$LOG_FILE"
DNSTT_PRIVKEY="$DNSTT_PRIVKEY"
DNSTT_PUBKEY="$DNSTT_PUBKEY"
V2RAY_UUID="$V2RAY_UUID"
V2RAY_PORT="$V2RAY_PORT"
VM_NAME="slowdns-v2ray"
EOF

log "Environment config saved ✓"
