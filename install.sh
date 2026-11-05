#!/bin/bash
# ============================================================
#  MASTER INSTALL SCRIPT — GCP VM Auto-Deployer
#  V2Ray (VLESS) + SlowDNS Server via Google Cloud Shell
#  Usage: bash install.sh
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

git -C "$SCRIPT_DIR" config core.fileMode false 2>/dev/null || true
chmod +x "$SCRIPT_DIR"/*.sh

# ══════════════════════════════════════════
#  PHASE 1: Project & Key Setup
# ══════════════════════════════════════════
phase_header "Phase 1/4 — Project & Key Setup"
bash "$SCRIPT_DIR/01_setup_env.sh"

# ══════════════════════════════════════════
#  PHASE 2: Firewall & Startup Script
# ══════════════════════════════════════════
phase_header "Phase 2/4 — GCP Firewall & Startup Config"
bash "$SCRIPT_DIR/03_slowdns_install.sh"

# ══════════════════════════════════════════
#  PHASE 3: GCP VM Creation & Installation
# ══════════════════════════════════════════
phase_header "Phase 3/4 — Creating GCP VM & Installing Server"
bash "$SCRIPT_DIR/04_v2ray_install.sh"

# ══════════════════════════════════════════
#  PHASE 4: Domain & Final Client Config
# ══════════════════════════════════════════
phase_header "Phase 4/4 — Final Config & Domain Output"
bash "$SCRIPT_DIR/07_client_config.sh" "$@"

echo ""
echo -e "${BOLD}${GREEN}🎉 সব complete! এখন উপরের IP-তে তোমার NS A-record পয়েন্ট করে কানেক্ট করো।${NC}"
echo ""
