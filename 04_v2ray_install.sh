#!/bin/bash
# ============================================================
#  Phase 3 — Create GCP VM & Wait for SlowDNS + VLESS Services
# ============================================================

ENV_FILE="$HOME/v2ray-slowdns-gcp/config/env.conf"
[[ ! -f "$ENV_FILE" ]] && echo "[✘] Run 01_setup_env.sh first!" && exit 1
source "$ENV_FILE"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
log()  { echo -e "${GREEN}[✔]${NC} $1" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YELLOW}[⚠]${NC} $1" | tee -a "$LOG_FILE"; }
err()  { echo -e "${RED}[✘]${NC} $1" | tee -a "$LOG_FILE"; exit 1; }
info() { echo -e "${CYAN}[i]${NC} $1" | tee -a "$LOG_FILE"; }
banner() {
    echo -e "\n${BOLD}${CYAN}═══════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}  $1${NC}"
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════${NC}\n"
}

banner "Phase 3: Creating GCP VM & Installing Server"

# ── 1. Detect Allowed Zones & Singapore Priority ────────────
DEFAULT_ZONE=$(gcloud config get-value compute/zone 2>/dev/null || true)
DEFAULT_REGION=$(gcloud config get-value compute/region 2>/dev/null || true)
[[ "$DEFAULT_ZONE" == "(unset)" ]] && DEFAULT_ZONE=""
[[ "$DEFAULT_REGION" == "(unset)" ]] && DEFAULT_REGION=""

META_ZONE=$(gcloud compute project-info describe --project="$PROJECT_ID" \
    --format="value(commonInstanceMetadata.items[google-compute-default-zone])" 2>/dev/null || true)
META_REGION=$(gcloud compute project-info describe --project="$PROJECT_ID" \
    --format="value(commonInstanceMetadata.items[google-compute-default-region])" 2>/dev/null || true)

ALLOWED_LOCATIONS=$(gcloud resource-manager org-policies describe constraints/gcp.resourceLocations \
    --project="$PROJECT_ID" \
    --format="value(listPolicy.allowedValues)" 2>/dev/null || true)

[[ -n "$META_ZONE" ]] && info "Project default zone: ${BOLD}$META_ZONE${NC}"
[[ -n "$ALLOWED_LOCATIONS" ]] && info "Allowed locations policy: ${BOLD}$ALLOWED_LOCATIONS${NC}"

CANDIDATE_ZONES=()

# 1. If project has a specific default zone/region set by Qwiklabs, try that first
[[ -n "$DEFAULT_ZONE" ]] && CANDIDATE_ZONES+=("$DEFAULT_ZONE")
[[ -n "$META_ZONE" ]] && CANDIDATE_ZONES+=("$META_ZONE")
[[ -n "$DEFAULT_REGION" ]] && CANDIDATE_ZONES+=("${DEFAULT_REGION}-a" "${DEFAULT_REGION}-b" "${DEFAULT_REGION}-c")
[[ -n "$META_REGION" ]] && CANDIDATE_ZONES+=("${META_REGION}-a" "${META_REGION}-b" "${META_REGION}-c")

# 2. Singapore (SG) & Asia zones (if not blocked by org policy)
if [[ -z "$ALLOWED_LOCATIONS" ]] || [[ "$ALLOWED_LOCATIONS" == *"asia"* ]]; then
    CANDIDATE_ZONES+=(
        "asia-southeast1-a" "asia-southeast1-b" "asia-southeast1-c"
        "asia-south1-a" "asia-east1-a"
    )
fi

# 3. US & Europe fallback zones
CANDIDATE_ZONES+=(
    "us-central1-a" "us-central1-b" "us-central1-c" "us-central1-f"
    "us-east1-b" "us-east1-c" "us-east4-a" "us-west1-b" "us-west4-b"
    "europe-west1-b" "europe-west4-a"
)

TARGET_ZONES=()
for z in "${CANDIDATE_ZONES[@]}"; do
    [[ -n "$z" ]] && [[ ! " ${TARGET_ZONES[*]} " =~ " ${z} " ]] && TARGET_ZONES+=("$z")
done

# ── 2. Check if VM already exists, or create a new one ──────
CREATED_IP=""
DEPLOYED_ZONE=""

EXISTING_INFO=$(gcloud compute instances list --project="$PROJECT_ID" \
    --filter="name=$VM_NAME" \
    --format="value(zone,networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null | head -n 1 || true)

if [[ -n "$EXISTING_INFO" ]]; then
    DEPLOYED_ZONE=$(echo "$EXISTING_INFO" | awk '{print $1}')
    CREATED_IP=$(echo "$EXISTING_INFO" | awk '{print $2}')
    warn "Existing VM '$VM_NAME' found in $DEPLOYED_ZONE ($CREATED_IP) — replacing with fresh config..."
    gcloud compute instances delete "$VM_NAME" --project="$PROJECT_ID" --zone="$DEPLOYED_ZONE" --quiet 2>/dev/null || true
    CREATED_IP=""
fi

for ZONE in "${TARGET_ZONES[@]}"; do
    info "Trying zone: ${BOLD}$ZONE${NC}..."
    for TYPE in "e2-medium" "e2-small" "e2-micro"; do
        OUT=$(gcloud compute instances create "$VM_NAME" \
            --project="$PROJECT_ID" \
            --zone="$ZONE" \
            --machine-type="$TYPE" \
            --image-family=ubuntu-2204-lts \
            --image-project=ubuntu-os-cloud \
            --tags=http-server,https-server \
            --scopes=cloud-platform \
            --metadata-from-file=startup-script=/tmp/slowdns-startup.sh \
            --format='get(networkInterfaces[0].accessConfigs[0].natIP)' \
            --quiet 2>&1 || true)

        IP=$(echo "$OUT" | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n 1 || true)
        if [[ -n "$IP" ]]; then
            CREATED_IP="$IP"
            DEPLOYED_ZONE="$ZONE"
            log "VM Created! Zone: ${BOLD}$ZONE${NC} | Type: ${BOLD}$TYPE${NC} | IP: ${BOLD}$CREATED_IP${NC}"
            break 2
        fi

        if ! echo "$OUT" | grep -qiE "quota|exceeded|RESOURCE_POOL_EXHAUSTED"; then
            break
        fi
    done

    ERR_SNIP=$(echo "$OUT" | grep -A 1 -Ei "ERROR|denied|quota|policy|ZONE_RESOURCE|not found|disabled" | tr '\n' ' ' | sed 's/  */ /g' || true)
    warn "Zone $ZONE skipped: ${ERR_SNIP:-not available}"
done

if [[ -z "$CREATED_IP" ]]; then
    err "GCP VM তৈরি করা যায়নি! উপরের এরর মেসেজটি দেখো (প্রজেক্টের টাইম শেষ বা Compute Engine পারমিশন নেই)।"
fi

{
    echo "PUBLIC_IP=\"$CREATED_IP\""
    echo "DEPLOYED_ZONE=\"$DEPLOYED_ZONE\""
} >> "$ENV_FILE"

# ── 3. Wait for VM Startup Script to Finish (~45s) ──────────
banner "Waiting for SlowDNS + VLESS Installation on VM"
info "VM ($CREATED_IP)-এ এখন dnstt-server এবং Xray (VLESS) ইনস্টল হচ্ছে (~40-60 সেকেন্ড লাগবে)..."

READY=false
for i in $(seq 1 30); do
    if timeout 2 bash -c "</dev/tcp/$CREATED_IP/$V2RAY_PORT" 2>/dev/null; then
        READY=true
        log "VM Services Ready! Port $V2RAY_PORT (VLESS) & UDP 53 (SlowDNS) are LIVE ✓"
        break
    fi
    echo -e "   ⏳ Installing on VM... ($((i*3))s elapsed)"
    sleep 3
done

if [[ "$READY" == false ]]; then
    warn "VM এখনো ব্যাকগ্রাউন্ডে সেটআপ শেষ করছে (আরেকটু সময় লাগতে পারে)।"
fi
