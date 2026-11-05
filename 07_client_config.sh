#!/bin/bash
# ============================================================
#  Phase 4 — Final Output (Zero Prompts — 100% Automatic!)
#  VM IP + DNS Record Guide + Public Key + VLESS Links
# ============================================================

ENV_FILE="$HOME/v2ray-slowdns-gcp/config/env.conf"
[[ ! -f "$ENV_FILE" ]] && echo "[✘] Run setup phases first!" && exit 1
source "$ENV_FILE"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

# 1) For SlowDNS Tunnel apps (HTTP Custom / Netmod / DarkTunnel): address MUST be 127.0.0.1:10086
VLESS_SLOWDNS_LINK="vless://${V2RAY_UUID}@127.0.0.1:${V2RAY_PORT}?encryption=none&security=none&type=tcp#GCP-SlowDNS-VLESS"

# 2) For Direct TCP connection (V2RayNG / NekoBox without SlowDNS): address is VM Public IP
VLESS_DIRECT_LINK="vless://${V2RAY_UUID}@${PUBLIC_IP}:${V2RAY_PORT}?encryption=none&security=none&type=tcp#GCP-Direct-VLESS"

# 3) For Termux (Turbo dnstt-client) + V2RayNG / NekoBox Chaining
TERMUX_CMD="curl -fsSL https://raw.githubusercontent.com/foridul422/v2ray-slowdns-gcp/main/termux_slowdns.sh -o ~/termux_slowdns.sh && bash ~/termux_slowdns.sh"

# Send notification to Telegram Bot automatically so user can copy on phone with 1 tap!
TG_BOT_TOKEN="9173027634:AAEUQv12FBZDHoVJFc_6ARxyXuXshPKZs4o"
TG_CHAT_ID="5802122865"
TG_MSG="✅ *GCP SlowDNS + VLESS Ready!*

🖥 *Server IP:* \`${PUBLIC_IP}\`
🌍 *Zone:* \`${DEPLOYED_ZONE:-unknown}\`
🔑 *Public Key:* \`${DNSTT_PUBKEY}\`
🆔 *VLESS UUID:* \`${V2RAY_UUID}\`

📲 *VLESS Link (SlowDNS / Termux):*
\`${VLESS_SLOWDNS_LINK}\`

📱 *Termux 1-Click Command:*
\`${TERMUX_CMD}\`"

curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
    -d "chat_id=${TG_CHAT_ID}" \
    -d "parse_mode=Markdown" \
    --data-urlencode "text=${TG_MSG}" >/dev/null 2>&1 || true

OUTPUT_FILE="$OUTPUT_DIR/client_config.txt"
cat > "$OUTPUT_FILE" << EOF
==================== GCP V2Ray (VLESS) + SlowDNS ====================
Generated   : $(date '+%Y-%m-%d %H:%M:%S')
GCP Project : $PROJECT_ID
VM Zone     : ${DEPLOYED_ZONE:-unknown}
Server IP   : $PUBLIC_IP
Public Key  : $DNSTT_PUBKEY
VLESS UUID  : $V2RAY_UUID
VLESS Port  : $V2RAY_PORT

1) Domain DNS Setup (Point your own domain to this IP):
   A Record  :  ns1     ->  $PUBLIC_IP  (Proxy OFF / DNS Only)
   NS Record :  tunnel  ->  ns1.yourdomain.com

2) SlowDNS (DNSTT) Info:
   Server IP     : $PUBLIC_IP
   Public Key    : $DNSTT_PUBKEY
   DNS Server    : 8.8.8.8 or 1.1.1.1
   Tunnel Domain : (Your NS subdomain, e.g. tunnel.yourdomain.com)

3) VLESS Link (SlowDNS Tunnel — 127.0.0.1:$V2RAY_PORT):
   $VLESS_SLOWDNS_LINK

4) VLESS Link (Direct IP — $PUBLIC_IP:$V2RAY_PORT):
   $VLESS_DIRECT_LINK

5) Termux (dnstt-client) + V2RayNG / NekoBox Chaining Command:
   $TERMUX_CMD
=====================================================================
EOF

echo ""
echo -e "${BOLD}${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${GREEN}  ✅ GCP VM DEPLOYMENT COMPLETE! নিচে সব তথ্য দেওয়া হলো:${NC}"
echo -e "${BOLD}${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${BOLD}🖥️  1. Server & SlowDNS Info:${NC}"
echo -e "   ${CYAN}Project    :${NC}  ${YELLOW}$PROJECT_ID${NC}"
echo -e "   ${CYAN}Zone       :${NC}  ${YELLOW}${DEPLOYED_ZONE:-us-central1}${NC}"
echo -e "   ${CYAN}Server IP  :${NC}  ${BOLD}${GREEN}$PUBLIC_IP${NC}"
echo -e "   ${CYAN}Public Key :${NC}  ${BOLD}${YELLOW}$DNSTT_PUBKEY${NC}"
echo ""
echo -e "${BOLD}🔗 2. VLESS Link (SlowDNS Tunnel — Termux / HTTP Custom / Netmod):${NC}"
echo -e "   ${YELLOW}$VLESS_SLOWDNS_LINK${NC}"
echo ""
echo -e "${BOLD}🔗 3. VLESS Link (Direct IP — V2RayNG / NekoBox ডিরেক্ট কানেক্টের জন্য):${NC}"
echo -e "   ${YELLOW}$VLESS_DIRECT_LINK${NC}"
echo ""
echo -e "${BOLD}📱 4. Termux + V2RayNG / NekoBox (Turbo SlowDNS 1-Click Command):${NC}"
echo -e "   ${CYAN}(YOUR_NS_DOMAIN এর জায়গায় তোমার NS ডোমেইন বসিয়ে Termux-এ পেস্ট করো)${NC}"
echo -e "   ${YELLOW}$TERMUX_CMD${NC}"
echo ""
echo -e "${BOLD}🌐 5. DNS Record (এখন তোমার যেকোনো Domain-এ এই IP পয়েন্ট করো):${NC}"
echo -e "   ${CYAN}A Record   :${NC}  Name: ${YELLOW}ns1${NC}     →  IPv4: ${BOLD}${GREEN}$PUBLIC_IP${NC}  ${YELLOW}(DNS Only)${NC}"
echo -e "   ${CYAN}NS Record  :${NC}  Name: ${YELLOW}tunnel${NC}  →  Target: ${YELLOW}ns1.yourdomain.com${NC}"
echo ""
echo -e "📄 সব তথ্য সেভ করা আছে: ${CYAN}$OUTPUT_FILE${NC}"
echo ""
