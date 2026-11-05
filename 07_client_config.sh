#!/bin/bash
# ============================================================
#  Phase 7 — Client Config Generator & Final Output
#  V2Ray + SlowDNS on Google Cloud Shell
# ============================================================

# ── Load environment ─────────────────────────────────────────
ENV_FILE="$HOME/v2ray-slowdns-gcp/config/env.conf"
[[ ! -f "$ENV_FILE" ]] && echo "[✘] Run setup phases first!" && exit 1
source "$ENV_FILE"

# ── Colors ───────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log()    { echo -e "${GREEN}[✔]${NC} $1" | tee -a "$LOG_FILE"; }
info()   { echo -e "${CYAN}[i]${NC} $1" | tee -a "$LOG_FILE"; }
banner() {
    echo -e "\n${BOLD}${CYAN}═══════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}  $1${NC}"
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════${NC}\n"
}

banner "Phase 7: Generating Client Config"

# ── 1. Read Public Key ───────────────────────────────────────
PUBLIC_KEY_B64=$(cat "$KEYS_DIR/slowdns_public_b64.txt" 2>/dev/null)
if [[ -z "$PUBLIC_KEY_B64" ]]; then
    PUBLIC_KEY_B64=$(openssl rsa -in "$KEYS_DIR/slowdns_private.pem" \
        -pubout 2>/dev/null | grep -v "BEGIN\|END" | tr -d '\n')
fi

# ── 2. Generate VMess Link ───────────────────────────────────
banner "Generating V2Ray VMess Link"

VMESS_JSON=$(cat << EOF
{
  "v": "2",
  "ps": "GCP-SlowDNS",
  "add": "$PUBLIC_IP",
  "port": "10086",
  "id": "$V2RAY_UUID",
  "aid": "0",
  "scy": "auto",
  "net": "tcp",
  "type": "none",
  "host": "",
  "path": "",
  "tls": "",
  "sni": "",
  "alpn": "",
  "fp": ""
}
EOF
)

VMESS_B64=$(echo -n "$VMESS_JSON" | base64 -w 0)
VMESS_LINK="vmess://$VMESS_B64"
log "VMess link generated ✓"

# ── 3. Write Final Output File ───────────────────────────────
OUTPUT_FILE="$OUTPUT_DIR/client_config.txt"

cat > "$OUTPUT_FILE" << EOF
╔══════════════════════════════════════════════════════════════════╗
║           V2Ray + SlowDNS — Client Configuration                ║
║                Generated: $(date '+%Y-%m-%d %H:%M:%S')                     ║
╚══════════════════════════════════════════════════════════════════╝

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 🌐 SERVER INFORMATION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Server IP   : $PUBLIC_IP
  Domain      : $USER_DOMAIN
  NS Record   : ns1.$USER_DOMAIN → $PUBLIC_IP
  Tunnel NS   : $TUNNEL_DOMAIN → NS → ns1.$USER_DOMAIN

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 📡 SLOWDNS CLIENT CONFIG (Android App)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  App         : SlowDNS (Play Store / APKPure)
  Server IP   : $PUBLIC_IP
  Nameserver  : $TUNNEL_DOMAIN
  Public Key  : $PUBLIC_KEY_B64

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 🚀 V2RAY CLIENT CONFIG
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Protocol  : VMess
  Address   : 127.0.0.1  (via SlowDNS tunnel)
  Port      : 10086
  UUID      : $V2RAY_UUID
  AlterId   : 0
  Security  : auto
  Network   : tcp
  TLS       : none

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 🔗 VMESS LINK
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
$VMESS_LINK

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 📋 DNS RECORD SETUP
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Type: A     | Host: ns1    | Value: $PUBLIC_IP       | TTL: 300
  Type: NS    | Host: tunnel | Value: ns1.$USER_DOMAIN | TTL: 300

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 📱 HOW TO USE (Android)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Step 1: Install SlowDNS app
  Step 2: Enter:
          Server: $PUBLIC_IP
          Nameserver: $TUNNEL_DOMAIN
          Public Key: (copy from above)
  Step 3: Install V2RayNG app
  Step 4: Import VMess link (copy from above)
  Step 5: In SlowDNS → set Local Port = 10086
  Step 6: Connect SlowDNS first, then V2RayNG

EOF

log "Client config saved: $OUTPUT_FILE"

# ── 4. Display on Terminal ───────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${GREEN}  ✅ SETUP COMPLETE! Client Info Below:${NC}"
echo -e "${BOLD}${GREEN}════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${BOLD}📌 DNS Record Setup:${NC}"
echo -e "   ${CYAN}Type: A   | ns1.$USER_DOMAIN     → $PUBLIC_IP${NC}"
echo -e "   ${CYAN}Type: NS  | $TUNNEL_DOMAIN → ns1.$USER_DOMAIN${NC}"
echo ""
echo -e "${BOLD}📡 SlowDNS App Settings:${NC}"
echo -e "   Server IP   : ${YELLOW}$PUBLIC_IP${NC}"
echo -e "   Nameserver  : ${YELLOW}$TUNNEL_DOMAIN${NC}"
echo -e "   Public Key  : ${YELLOW}$PUBLIC_KEY_B64${NC}"
echo ""
echo -e "${BOLD}🔗 VMess Link:${NC}"
echo -e "   ${YELLOW}$VMESS_LINK${NC}"
echo ""
echo -e "${BOLD}📄 Full config saved at:${NC}"
echo -e "   ${CYAN}$OUTPUT_FILE${NC}"
echo ""
echo -e "${BOLD}📺 Screen sessions:${NC}"
screen -list 2>/dev/null | grep -E "slowdns|v2ray" | while read line; do
    echo -e "   ${GREEN}$line${NC}"
done
echo ""
echo -e "${YELLOW}💡 Logs:${NC}"
echo -e "   ${CYAN}screen -r slowdns${NC}  |  ${CYAN}screen -r v2ray${NC}  |  Detach: ${CYAN}Ctrl+A, D${NC}"
echo ""
