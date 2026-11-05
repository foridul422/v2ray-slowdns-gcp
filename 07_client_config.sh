#!/bin/bash
# ============================================================
#  Phase 4 — Final Output (Asked ONLY AFTER Server is Ready!)
#  VM IP + Domain NS Records + Public Key + VLESS Links
# ============================================================

ENV_FILE="$HOME/v2ray-slowdns-gcp/config/env.conf"
[[ ! -f "$ENV_FILE" ]] && echo "[✘] Run setup phases first!" && exit 1
source "$ENV_FILE"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

# Ask for domain ONLY NOW, after VM creation & server installation are 100% finished
while read -r -t 0.1 -n 10000 _ </dev/tty 2>/dev/null; do :; done

USER_DOMAIN="${1:-}"
if [[ -z "$USER_DOMAIN" ]]; then
    echo ""
    echo -ne "${BOLD}${YELLOW}👉 সার্ভার তৈরি সম্পন্ন! এখন তোমার Domain নাম লেখো (যেমন: example.com): ${NC}"
    read -r USER_DOMAIN </dev/tty
    USER_DOMAIN=$(echo "$USER_DOMAIN" | tr '[:upper:]' '[:lower:]' | sed 's|^https\?://||; s|^www\.||; s|/.*||; s|[[:space:]]||g')
fi
[[ -z "$USER_DOMAIN" ]] && USER_DOMAIN="yourdomain.com"

NS_SUB="ns1"
TUNNEL_SUB="tunnel"
NS_DOMAIN="${NS_SUB}.${USER_DOMAIN}"
TUNNEL_DOMAIN="${TUNNEL_SUB}.${USER_DOMAIN}"

# 1) For SlowDNS Tunnel apps (HTTP Custom / Netmod / DarkTunnel): address MUST be 127.0.0.1:10086
VLESS_SLOWDNS_LINK="vless://${V2RAY_UUID}@127.0.0.1:${V2RAY_PORT}?encryption=none&security=none&type=tcp#GCP-SlowDNS-VLESS"

# 2) For Direct TCP connection (V2RayNG / NekoBox without SlowDNS): address is VM Public IP
VLESS_DIRECT_LINK="vless://${V2RAY_UUID}@${PUBLIC_IP}:${V2RAY_PORT}?encryption=none&security=none&type=tcp#GCP-Direct-VLESS"

OUTPUT_FILE="$OUTPUT_DIR/client_config.txt"
cat > "$OUTPUT_FILE" << EOF
==================== GCP V2Ray (VLESS) + SlowDNS ====================
Generated   : $(date '+%Y-%m-%d %H:%M:%S')
GCP Project : $PROJECT_ID
VM Zone     : ${DEPLOYED_ZONE:-unknown}
VM IP       : $PUBLIC_IP

1) DNS Records (Add these in your Domain / Cloudflare panel)
   Type: A    | Name: $NS_SUB      | Value: $PUBLIC_IP  (Proxy: OFF / DNS Only)
   Type: NS   | Name: $TUNNEL_SUB  | Value: $NS_DOMAIN

2) SlowDNS (DNSTT) Settings (HTTP Custom / Netmod / DarkTunnel)
   NS Domain           : $NS_DOMAIN
   DNS / Tunnel Domain : $TUNNEL_DOMAIN
   Public Key          : $DNSTT_PUBKEY
   DNS Server          : 8.8.8.8 or 1.1.1.1

3) VLESS Link for SlowDNS Tunnel (127.0.0.1:$V2RAY_PORT)
   $VLESS_SLOWDNS_LINK

4) VLESS Link for Direct Connection ($PUBLIC_IP:$V2RAY_PORT)
   $VLESS_DIRECT_LINK
=====================================================================
EOF

echo ""
echo -e "${BOLD}${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${GREEN}  ✅ GCP VM DEPLOYMENT COMPLETE! নিচে সব তথ্য দেওয়া হলো:${NC}"
echo -e "${BOLD}${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${BOLD}🖥️  GCP VM Info:${NC}"
echo -e "   ${CYAN}Project    :${NC}  ${YELLOW}$PROJECT_ID${NC}"
echo -e "   ${CYAN}Zone       :${NC}  ${YELLOW}${DEPLOYED_ZONE:-us-central1}${NC}"
echo -e "   ${CYAN}Server IP  :${NC}  ${BOLD}${GREEN}$PUBLIC_IP${NC}"
echo ""
echo -e "${BOLD}🌐 1. Domain DNS Records (এখন তোমার Domain/Cloudflare-এ এই ২টা record বসাও):${NC}"
echo -e "   ${CYAN}A Record  :${NC}  Name: ${YELLOW}$NS_SUB${NC}      →  IPv4: ${BOLD}${GREEN}$PUBLIC_IP${NC}  ${YELLOW}(Proxy OFF / DNS Only)${NC}"
echo -e "   ${CYAN}NS Record :${NC}  Name: ${YELLOW}$TUNNEL_SUB${NC}  →  Target: ${YELLOW}$NS_DOMAIN${NC}"
echo ""
echo -e "${BOLD}📡 2. SlowDNS / DNSTT Settings:${NC}"
echo -e "   ${CYAN}NS Domain     :${NC}  ${YELLOW}$NS_DOMAIN${NC}"
echo -e "   ${CYAN}Tunnel Domain :${NC}  ${YELLOW}$TUNNEL_DOMAIN${NC}"
echo -e "   ${CYAN}Public Key    :${NC}  ${YELLOW}$DNSTT_PUBKEY${NC}"
echo -e "   ${CYAN}DNS Server    :${NC}  ${YELLOW}8.8.8.8 / 1.1.1.1${NC}"
echo ""
echo -e "${BOLD}🔗 3. VLESS Link (SlowDNS Tunnel — HTTP Custom / Netmod এর জন্য):${NC}"
echo -e "   ${YELLOW}$VLESS_SLOWDNS_LINK${NC}"
echo ""
echo -e "${BOLD}🔗 4. VLESS Link (Direct IP — V2RayNG / NekoBox ডিরেক্ট কানেক্টের জন্য):${NC}"
echo -e "   ${YELLOW}$VLESS_DIRECT_LINK${NC}"
echo ""
echo -e "📄 সব তথ্য সেভ করা আছে: ${CYAN}$OUTPUT_FILE${NC}"
echo ""
