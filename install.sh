#!/bin/bash
# ============================================================
#  MASTER INSTALL SCRIPT — No pause, full auto
#  V2Ray + SlowDNS Server on Google Cloud Shell
#  Usage: bash install.sh [yourdomain.com]
# ============================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

phase_header() {
    echo ""
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║  $1${NC}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════╝${NC}"
    echo ""
}

chmod +x "$SCRIPT_DIR"/*.sh

# ══════════════════════════════════════════
#  PHASE 1: Environment Setup
# ══════════════════════════════════════════
phase_header "Phase 1/4 — Environment Setup"
bash "$SCRIPT_DIR/01_setup_env.sh" "$@"

# ══════════════════════════════════════════
#  PHASE 2: SlowDNS Install
# ══════════════════════════════════════════
phase_header "Phase 2/4 — SlowDNS (DNSTT) Server Install"
bash "$SCRIPT_DIR/03_slowdns_install.sh"

# ══════════════════════════════════════════
#  PHASE 3: V2Ray Install
# ══════════════════════════════════════════
phase_header "Phase 3/4 — V2Ray Install & Configure"
bash "$SCRIPT_DIR/04_v2ray_install.sh"

# ══════════════════════════════════════════
#  PHASE 4: Generate Client Config & Output
# ══════════════════════════════════════════
phase_header "Phase 4/4 — Generating Client Config"
bash "$SCRIPT_DIR/07_client_config.sh"

echo ""
echo -e "${BOLD}${GREEN}🎉 সব complete! উপরে VLESS link ও NS record info দেখো।${NC}"
echo ""
