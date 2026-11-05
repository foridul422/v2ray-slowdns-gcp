#!/bin/bash
# ============================================================
#  Phase 3 — Create/Reuse GCP VM & Install SlowDNS + VLESS
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

banner "Phase 3: Setting Up GCP VM & Installing Server"

# Ensure Compute Engine API is enabled
gcloud services enable compute.googleapis.com --project="$PROJECT_ID" --quiet 2>/dev/null || true

CREATED_IP=""
DEPLOYED_ZONE=""
ACTIVE_VM_NAME="$VM_NAME"

# ── 1. Check if ANY Running VM Already Exists in the Lab ─────
info "Checking for existing VMs in project ($PROJECT_ID)..."
EXISTING_VM_LINE=$(gcloud compute instances list --project="$PROJECT_ID" \
    --filter="status=RUNNING" \
    --format="value(name,zone,networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null | head -n 1 || true)

if [[ -n "$EXISTING_VM_LINE" ]]; then
    EXISTING_NAME=$(echo "$EXISTING_VM_LINE" | awk '{print $1}')
    EXISTING_ZONE=$(echo "$EXISTING_VM_LINE" | awk '{print $2}')
    EXISTING_IP=$(echo "$EXISTING_VM_LINE" | awk '{print $3}')

    if [[ -n "$EXISTING_IP" ]]; then
        ACTIVE_VM_NAME="$EXISTING_NAME"
        DEPLOYED_ZONE="$EXISTING_ZONE"
        CREATED_IP="$EXISTING_IP"
        log "Found existing running VM: ${BOLD}$ACTIVE_VM_NAME${NC} ($DEPLOYED_ZONE) | IP: ${BOLD}$CREATED_IP${NC}"
        info "Installing SlowDNS + VLESS directly onto '$ACTIVE_VM_NAME'..."

        gcloud compute instances add-tags "$ACTIVE_VM_NAME" \
            --project="$PROJECT_ID" --zone="$DEPLOYED_ZONE" \
            --tags=http-server,https-server --quiet 2>/dev/null || true

        gcloud compute instances add-metadata "$ACTIVE_VM_NAME" \
            --project="$PROJECT_ID" --zone="$DEPLOYED_ZONE" \
            --metadata-from-file=startup-script=/tmp/slowdns-startup.sh --quiet 2>/dev/null || true

        # Run startup script directly over SSH in background or foreground
        gcloud compute ssh "$ACTIVE_VM_NAME" \
            --project="$PROJECT_ID" --zone="$DEPLOYED_ZONE" \
            --strict-host-key-checking=no --quiet \
            --command="sudo bash -s" < /tmp/slowdns-startup.sh >/dev/null 2>&1 &
    fi
fi

# ── 2. If No Running VM Exists, Create a New VM ──────────────
if [[ -z "$CREATED_IP" ]]; then
    DEFAULT_ZONE=$(gcloud config get-value compute/zone 2>/dev/null || true)
    [[ "$DEFAULT_ZONE" == "(unset)" ]] && DEFAULT_ZONE=""

    META_ZONE=$(gcloud compute project-info describe --project="$PROJECT_ID" \
        --format="value(commonInstanceMetadata.items[google-compute-default-zone])" 2>/dev/null || true)
    META_REGION=$(gcloud compute project-info describe --project="$PROJECT_ID" \
        --format="value(commonInstanceMetadata.items[google-compute-default-region])" 2>/dev/null || true)

    ALLOWED_LOCATIONS=$(gcloud resource-manager org-policies describe constraints/gcp.resourceLocations \
        --project="$PROJECT_ID" \
        --format="value(listPolicy.allowedValues)" 2>/dev/null || true)

    CANDIDATE_ZONES=()

    # 1. Try Singapore (SG) & Asia FIRST if allowed by org policy
    if [[ -z "$ALLOWED_LOCATIONS" ]] || [[ "$ALLOWED_LOCATIONS" == *"asia"* ]]; then
        CANDIDATE_ZONES+=(
            "asia-southeast1-a" "asia-southeast1-b" "asia-southeast1-c"
            "asia-south1-a" "asia-east1-a"
        )
    fi

    # 2. Next, project default zone/region
    [[ -n "$DEFAULT_ZONE" ]] && CANDIDATE_ZONES+=("$DEFAULT_ZONE")
    [[ -n "$META_ZONE" ]] && CANDIDATE_ZONES+=("$META_ZONE")
    [[ -n "$META_REGION" ]] && CANDIDATE_ZONES+=("${META_REGION}-a" "${META_REGION}-b" "${META_REGION}-c")

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

    for ZONE in "${TARGET_ZONES[@]}"; do
        info "Trying zone: ${BOLD}$ZONE${NC}..."
        for TYPE in "e2-medium" "e2-small" "e2-micro" "n1-standard-1"; do
            # Try standard Debian 12 image first (fastest & allowed in all Qwiklabs Compute labs)
            OUT=$(gcloud compute instances create "$VM_NAME" \
                --project="$PROJECT_ID" \
                --zone="$ZONE" \
                --machine-type="$TYPE" \
                --image-family=debian-12 \
                --image-project=debian-cloud \
                --tags=http-server,https-server \
                --metadata-from-file=startup-script=/tmp/slowdns-startup.sh \
                --format='get(networkInterfaces[0].accessConfigs[0].natIP)' \
                --quiet 2>&1 || true)

            # Fallback if service account scope is restricted by Qwiklabs policy
            if echo "$OUT" | grep -qiE "serviceAccount|actAs|scope"; then
                OUT=$(gcloud compute instances create "$VM_NAME" \
                    --project="$PROJECT_ID" \
                    --zone="$ZONE" \
                    --machine-type="$TYPE" \
                    --image-family=debian-12 \
                    --image-project=debian-cloud \
                    --no-service-account --no-scopes \
                    --tags=http-server,https-server \
                    --metadata-from-file=startup-script=/tmp/slowdns-startup.sh \
                    --format='get(networkInterfaces[0].accessConfigs[0].natIP)' \
                    --quiet 2>&1 || true)
            fi

            IP=$(echo "$OUT" | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n 1 || true)
            if [[ -n "$IP" ]]; then
                CREATED_IP="$IP"
                DEPLOYED_ZONE="$ZONE"
                log "VM Created! Zone: ${BOLD}$ZONE${NC} | Type: ${BOLD}$TYPE${NC} | IP: ${BOLD}$CREATED_IP${NC}"
                break 2
            fi

            # Stop immediately if this Qwiklabs lab does not have Compute Engine permission
            if echo "$OUT" | grep -qi "Required 'compute.instances.create' permission"; then
                ACTIVE_ACC=$(gcloud config get-value account 2>/dev/null || true)
                USER_ROLES=$(gcloud projects get-iam-policy "$PROJECT_ID" \
                    --flatten="bindings[].members" \
                    --filter="bindings.members:$ACTIVE_ACC" \
                    --format="value(bindings.role)" 2>/dev/null | tr '\n' ' ' || true)
                echo ""
                warn "Account : ${ACTIVE_ACC:-unknown}"
                warn "Project : $PROJECT_ID"
                warn "Roles   : ${USER_ROLES:-NONE (ল্যাবের মেয়াদ শেষ বা পারমিশন নেই)}"
                warn "এই প্রজেক্টে ($PROJECT_ID) নতুন VM তৈরি করার ('compute.instances.create') পারমিশন নেই এবং কোনো চালু VM-ও নেই!"
                echo -e "${BOLD}${GREEN}💡 সমাধান:${NC} Qwiklabs-এ যেকোনো ${BOLD}Compute Engine / Virtual Machine${NC} ল্যাব স্টার্ট করে নতুন Cloud Shell ওপেন করে এই কমান্ডটি চালাও।"
                err "Compute Engine পারমিশনযুক্ত ল্যাব স্টার্ট করে আবার চেষ্টা করো।"
            fi

            if ! echo "$OUT" | grep -qiE "quota|exceeded|RESOURCE_POOL_EXHAUSTED|machine type"; then
                break
            fi
        done

        ERR_SNIP=$(echo "$OUT" | grep -A 1 -Ei "ERROR|denied|quota|policy|ZONE_RESOURCE|not found|disabled" | tr '\n' ' ' | sed 's/  */ /g' || true)
        warn "Zone $ZONE skipped: ${ERR_SNIP:-not available}"
    done
fi

if [[ -z "$CREATED_IP" ]]; then
    err "GCP VM তৈরি করা যায়নি! উপরের এরর মেসেজটি দেখো।"
fi

{
    echo "PUBLIC_IP=\"$CREATED_IP\""
    echo "DEPLOYED_ZONE=\"$DEPLOYED_ZONE\""
} >> "$ENV_FILE"

# ── 3. Wait for VM Startup Script to Finish (~40s) ──────────
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
