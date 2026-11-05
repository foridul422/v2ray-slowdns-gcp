#!/bin/bash
# ============================================================
#  Phase 4 — Final output: VLESS link + NS records + Public Key
# ============================================================

ENV_FILE="$HOME/v2ray-slowdns-gcp/config/env.conf"
[[ ! -f "$ENV_FILE" ]] && echo "[✘] Run setup phases first!" && exit 1
source "$ENV_FILE"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

LOCAL_PORT=1080
VLESS_LINK="vless://${V2RAY_UUID}@${PUBLIC_IP}:${V2RAY_PORT}?encryption=none&security=none&type=tcp#GCP-SlowDNS"
VLESS_LOCAL_LINK="vless://${V2RAY_UUID}@127.0.0.1:${LOCAL_PORT}?encryption=none&security=none&type=tcp#GCP-SlowDNS-Local"

OUTPUT_FILE="$OUTPUT_DIR/client_config.txt"
cat > "$OUTPUT_FILE" << EOF
==================== V2Ray (VLESS) + SlowDNS (dnstt) ====================
Generated: $(date '+%Y-%m-%d %H:%M:%S')

1) DNS Records (Add these in your Domain / Cloudflare panel)
   Type: A    | Name: $NS_SUB      | Value: $PUBLIC_IP  (Proxy: OFF / DNS Only)
   Type: NS   | Name: $TUNNEL_SUB  | Value: $NS_DOMAIN

2) SlowDNS (dnstt) Info
   Server IP   : $PUBLIC_IP
   Nameserver  : $TUNNEL_DOMAIN
   Public Key  : $DNSTT_PUBKEY

3) VLESS Link (Server IP)
   $VLESS_LINK

4) VLESS Link (Local 127.0.0.1:$LOCAL_PORT — when using standalone dnstt-client)
   $VLESS_LOCAL_LINK

5) Standalone dnstt-client command
   dnstt-client -udp <RESOLVER_IP>:53 -pubkey $DNSTT_PUBKEY $TUNNEL_DOMAIN 127.0.0.1:$LOCAL_PORT
=========================================================================
EOF

echo ""
echo -e "${BOLD}${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${GREEN}  ✅ FULL INSTALL COMPLETE! নিচে সব তথ্য দেওয়া হলো:${NC}"
echo -e "${BOLD}${GREEN}════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${BOLD}🌐 1. Domain DNS Records (এখন তোমার Domain-এ এই ২টা record বসাও):${NC}"
echo -e "   ${CYAN}A Record  :${NC}  Host: ${YELLOW}$NS_SUB${NC}      →  Value: ${YELLOW}$PUBLIC_IP${NC} (DNS Only)"
echo -e "   ${CYAN}NS Record :${NC}  Host: ${YELLOW}$TUNNEL_SUB${NC}  →  Value: ${YELLOW}$NS_DOMAIN${NC}"
echo ""
echo -e "${BOLD}📡 2. SlowDNS / DNSTT Info:${NC}"
echo -e "   ${CYAN}Server IP  :${NC}  ${YELLOW}$PUBLIC_IP${NC}"
echo -e "   ${CYAN}Nameserver :${NC}  ${YELLOW}$TUNNEL_DOMAIN${NC}"
echo -e "   ${CYAN}Public Key :${NC}  ${YELLOW}$DNSTT_PUBKEY${NC}"
echo ""
echo -e "${BOLD}🔗 3. VLESS Link:${NC}"
echo -e "   ${YELLOW}$VLESS_LINK${NC}"
echo ""
echo -e "${BOLD}🔗 4. VLESS Link (Local 127.0.0.1 — dnstt-client আলাদা চালালে):${NC}"
echo -e "   ${YELLOW}$VLESS_LOCAL_LINK${NC}"
echo ""
echo -e "📄 সব তথ্য সেভ করা আছে: ${CYAN}$OUTPUT_FILE${NC}"
echo ""
