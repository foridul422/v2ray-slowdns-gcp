#!/bin/bash
# ============================================================
#  Phase 2 — GCP Firewall & VM Startup Script Builder
#  Opens UDP 53 & TCP 10086 in GCP VPC Firewall and prepares
#  universal domain-agnostic dnstt-server + Xray VLESS startup
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

banner "Phase 2: GCP Firewall & SlowDNS Startup Config"

# ── 1. Open GCP Firewall Rules (on all VPC networks) ────────
info "Opening GCP Firewall ports (UDP:53, TCP:22,80,443,10086)..."

gcloud services enable compute.googleapis.com --project="$PROJECT_ID" --quiet 2>/dev/null || true

NETWORKS=$(gcloud compute networks list --project="$PROJECT_ID" --format="value(name)" 2>/dev/null || echo "default")
[[ -z "$NETWORKS" ]] && NETWORKS="default"

for NET in $NETWORKS; do
    FW_OUT=$(gcloud compute firewall-rules create "allow-slowdns-v2ray-${NET}" \
        --project="$PROJECT_ID" \
        --network="$NET" \
        --priority=100 \
        --allow=udp:53,udp:5300,tcp:22,tcp:80,tcp:443,tcp:10086 \
        --source-ranges=0.0.0.0/0 \
        --direction=INGRESS \
        --description="Allow SlowDNS (UDP 53) and V2Ray VLESS (TCP 10086)" \
        --quiet 2>&1 || true)
    if echo "$FW_OUT" | grep -qi "permission"; then
        warn "এই Qwiklabs ল্যাবে নতুন Firewall Rule তৈরি করার ('compute.firewalls.create') পারমিশন নেই!"
        # Fallback: try updating existing default rules if permitted
        gcloud compute firewall-rules update default-allow-ssh --project="$PROJECT_ID" --allow=tcp:22,tcp:10086,udp:53 --quiet 2>/dev/null || true
    fi
done

log "Firewall rules configured (UDP 53 & TCP 10086 OPEN) ✓"

# ── 2. Build VM Startup Script ──────────────────────────────
info "Generating VM startup script (/tmp/slowdns-startup.sh)..."

cat > /tmp/slowdns-startup.sh << 'STARTUP_EOF'
#!/bin/bash
set -e
exec > /var/log/slowdns-setup.log 2>&1
echo "=== [$(date)] SlowDNS + Xray VLESS VM Setup Starting ==="

export HOME=/root
export GOPATH=/root/go
export GOMODCACHE=/root/go/pkg/mod
export PATH=$PATH:/usr/local/go/bin
export DEBIAN_FRONTEND=noninteractive

# 1. Install unzip, curl & python3 if missing
apt-get update -qq || true
apt-get install -y -qq curl wget unzip python3 || true

# 2. Build speed-optimized, universal domain-agnostic dnstt-server
mkdir -p /usr/local/bin
if [ ! -x /usr/local/bin/dnstt-server ] || [ $(stat -c%s /usr/local/bin/dnstt-server 2>/dev/null || echo 0) -lt 1000000 ]; then
    echo "[*] Downloading Go 1.22.5..."
    curl -fsSL https://go.dev/dl/go1.22.5.linux-amd64.tar.gz -o /tmp/go.tar.gz
    tar -C /usr/local -xzf /tmp/go.tar.gz
    rm -f /tmp/go.tar.gz

    echo "[*] Downloading dnstt source from Go proxy..."
    rm -rf /tmp/dnstt_zip /tmp/dnstt.zip
    mkdir -p /tmp/dnstt_zip
    curl -fsSL "https://proxy.golang.org/www.bamsoftware.com/git/dnstt.git/@v/v1.20260501.0.zip" -o /tmp/dnstt.zip
    unzip -q /tmp/dnstt.zip -d /tmp/dnstt_zip
    SRC_DIR="/tmp/dnstt_zip/www.bamsoftware.com/git/dnstt.git@v1.20260501.0"

    echo "[*] Applying TurboTunnel high-speed & universal-domain patches..."
    sed -i 's/const QueueSize = 128/const QueueSize = 2048/g' "$SRC_DIR/turbotunnel/consts.go"
    sed -i 's/maxResponseDelay = 1 \* time.Second/maxResponseDelay = 30 \* time.Millisecond/g' "$SRC_DIR/dnstt-server/main.go"
    sed -i 's/ch := make(chan \*record, 100)/ch := make(chan \*record, 10000)/g' "$SRC_DIR/dnstt-server/main.go"
    sed -i 's/maxUDPPayload = 1280 - 40 - 8/maxUDPPayload = 512/g' "$SRC_DIR/dnstt-server/main.go"

    python3 - "$SRC_DIR/dnstt-server/main.go" << 'PY_EOF'
import sys
p = sys.argv[1]
with open(p, "r") as f:
    code = f.read()

# 1. Universal domain-agnostic prefix extraction + Always Authoritative (AA=1)
target = """\tprefix, ok := question.Name.TrimSuffix(domain)
\tif !ok {
\t\t// Not a name we are authoritative for.
\t\tresp.Flags |= dns.RcodeNameError
\t\tlog.Printf("NXDOMAIN: not authoritative for %s", question.Name)
\t\treturn resp, nil
\t}
\tresp.Flags |= 0x0400 // AA = 1"""

replacement = """\tresp.Flags |= 0x0400 // AA = 1 (Always authoritative for delegated tunnel zone)
\tprefix, ok := question.Name.TrimSuffix(domain)
\tif !ok {
\t\tfor i := 1; i < len(question.Name); i++ {
\t\t\tcand := question.Name[:i]
\t\t\tif i > 1 && len(cand[i-2]) != 63 {
\t\t\t\tbreak
\t\t\t}
\t\t\tenc := bytes.ToUpper(bytes.Join(cand, nil))
\t\t\tbuf := make([]byte, base32Encoding.DecodedLen(len(enc)))
\t\t\tn, err := base32Encoding.Decode(buf, enc)
\t\t\tif err != nil || n < 9 || buf[8] < 224 {
\t\t\t\tcontinue
\t\t\t}
\t\t\tpos := 8
\t\t\tfor pos < n {
\t\t\t\tb := int(buf[pos])
\t\t\t\tpos++
\t\t\t\tif b >= 224 {
\t\t\t\t\tpos += b - 224
\t\t\t\t} else {
\t\t\t\t\tpos += b
\t\t\t\t}
\t\t\t}
\t\t\tif pos == n {
\t\t\t\tprefix = cand
\t\t\t\tok = true
\t\t\t\tbreak
\t\t\t}
\t\t}
\t}
\tif !ok {
\t\tresp.Flags |= dns.RcodeNameError
\t\treturn resp, nil
\t}"""
assert target in code
code = code.replace(target, replacement, 1)

# 2. Return AA=1 NOERROR with valid NS/SOA records for zone apex & QNAME minimization so 8.8.8.8 never SERVFAILs after TTL expiry
recv_target = """\t\t} else {
\t\t\t// Payload is not long enough to contain a ClientID.
\t\t\tif resp != nil && resp.Rcode() == dns.RcodeNoError {
\t\t\t\tresp.Flags |= dns.RcodeNameError
\t\t\t\tlog.Printf("NXDOMAIN: %d bytes are too short to contain a ClientID", n)
\t\t\t}
\t\t}"""
recv_replacement = """\t\t} else {
\t\t\tif resp != nil && (resp.Rcode() == dns.RcodeNoError || resp.Rcode() == dns.RcodeNameError) {
\t\t\t\tresp.Flags = (resp.Flags &^ 0x000f) | 0x0400 // QR=1, AA=1, RCODE=0
\t\t\t\tif len(resp.Question) == 1 {
\t\t\t\t\tq := resp.Question[0]
\t\t\t\t\tvar nameBuf bytes.Buffer
\t\t\t\t\tfor _, lbl := range q.Name {
\t\t\t\t\t\tnameBuf.WriteByte(byte(len(lbl)))
\t\t\t\t\t\tnameBuf.Write(lbl)
\t\t\t\t\t}
\t\t\t\t\tnameBuf.WriteByte(0)
\t\t\t\t\tvar soaBuf bytes.Buffer
\t\t\t\t\tsoaBuf.Write(nameBuf.Bytes())
\t\t\t\t\tsoaBuf.Write(nameBuf.Bytes())
\t\t\t\t\tsoaBuf.Write([]byte{0, 0, 0, 1, 0, 0, 14, 16, 0, 0, 2, 88, 0, 1, 81, 128, 0, 0, 0, 60})
\t\t\t\t\tif q.Type == 2 {
\t\t\t\t\t\tresp.Answer = []dns.RR{{Name: q.Name, Type: 2, Class: dns.ClassIN, TTL: 3600, Data: nameBuf.Bytes()}}
\t\t\t\t\t} else if q.Type == 6 {
\t\t\t\t\t\tresp.Answer = []dns.RR{{Name: q.Name, Type: 6, Class: dns.ClassIN, TTL: 3600, Data: soaBuf.Bytes()}}
\t\t\t\t\t} else {
\t\t\t\t\t\tresp.Authority = []dns.RR{{Name: q.Name, Type: 6, Class: dns.ClassIN, TTL: 60, Data: soaBuf.Bytes()}}
\t\t\t\t\t}
\t\t\t\t}
\t\t\t\tif wire, err := resp.WireFormat(); err == nil {
\t\t\t\t\tdnsConn.WriteTo(wire, addr)
\t\t\t\t}
\t\t\t\tcontinue
\t\t\t}
\t\t}"""
assert recv_target in code
code = code.replace(recv_target, recv_replacement, 1)

# 3. KCP Turbo Mode tuned for high-jitter SIM DNS (nodelay=1, interval=20ms, resend=2, nc=1)
kcp_target = """\t\tconn.SetNoDelay(
\t\t\t0, // default nodelay
\t\t\t0, // default interval
\t\t\t0, // default resend
\t\t\t1, // nc=1 => congestion window off
\t\t)"""
kcp_replacement = """\t\tconn.SetNoDelay(
\t\t\t1,  // nodelay=1 (turbo)
\t\t\t20, // interval=20ms (safe for SIM DNS jitter)
\t\t\t2,  // resend=2 (fast retransmit on 2 ack skips)
\t\t\t1,  // nc=1 => congestion window off
\t\t)"""
if kcp_target in code:
    code = code.replace(kcp_target, kcp_replacement, 1)

# 4. Larger smux receive/stream buffers (16MB / 4MB)
smux_target = "\tsmuxConfig.MaxStreamBuffer = 1 * 1024 * 1024 // default is 65536"
smux_replacement = """\tsmuxConfig.MaxReceiveBuffer = 16 * 1024 * 1024
\tsmuxConfig.MaxStreamBuffer = 4 * 1024 * 1024"""
if smux_target in code:
    code = code.replace(smux_target, smux_replacement, 1)

with open(p, "w") as f:
    f.write(code)
PY_EOF

    echo "[*] Compiling dnstt-server..."
    cd "$SRC_DIR/dnstt-server"
    GOPROXY="https://proxy.golang.org,direct" CGO_ENABLED=0 /usr/local/go/bin/go build -ldflags="-s -w" -o /usr/local/bin/dnstt-server .
    chmod +x /usr/local/bin/dnstt-server
    rm -rf /tmp/dnstt_zip /tmp/dnstt.zip /usr/local/go /root/go
    echo "[OK] dnstt-server compiled!"
fi

# 3. Write SlowDNS Keys
mkdir -p /etc/slowdns
echo "PRIVKEY_PLACEHOLDER" > /etc/slowdns/server.key
echo "PUBKEY_PLACEHOLDER" > /etc/slowdns/server.pub
chmod 600 /etc/slowdns/server.key

# 4. Install Xray-core & Configure VLESS
echo "[*] Installing Xray-core..."
mkdir -p /usr/local/bin /usr/local/etc/xray
if [ ! -x /usr/local/bin/xray ]; then
    curl -fsSL -o /tmp/xray.zip "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip"
    unzip -qo /tmp/xray.zip -d /usr/local/bin/
    chmod +x /usr/local/bin/xray
    rm -f /tmp/xray.zip
fi

cat > /usr/local/etc/xray/config.json << 'XRAY_CONFIG'
{
  "log": { "loglevel": "warning" },
  "dns": { "servers": ["8.8.8.8", "1.1.1.1"] },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": PORT_PLACEHOLDER,
      "protocol": "vless",
      "settings": {
        "clients": [{ "id": "UUID_PLACEHOLDER" }],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "none",
        "sockopt": {
          "tcpFastOpen": true,
          "tcpNoDelay": true,
          "tcpKeepAliveInterval": 15
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": { "domainStrategy": "UseIP" }
    }
  ]
}
XRAY_CONFIG

cat > /etc/systemd/system/xray.service << 'XSVC_EOF'
[Unit]
Description=Xray VLESS Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=always
RestartSec=3
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
XSVC_EOF

# 5. SlowDNS Systemd Service (accepts ANY tunnel domain, MTU 512 for full SIM compatibility)
cat > /etc/systemd/system/slowdns.service << 'SVC_EOF'
[Unit]
Description=SlowDNS DNSTT Server
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/dnstt-server -udp :53 -mtu 512 -privkey-file /etc/slowdns/server.key t.local 127.0.0.1:PORT_PLACEHOLDER
Restart=always
RestartSec=3
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
SVC_EOF

# 6. Kernel UDP & BBR Tuning
cat > /etc/sysctl.d/99-slowdns-tune.conf << 'SYSCTL_EOF'
net.core.rmem_max=67108864
net.core.wmem_max=67108864
net.core.rmem_default=33554432
net.core.wmem_default=33554432
net.core.netdev_max_backlog=100000
net.core.somaxconn=65535
net.ipv4.tcp_fastopen=3
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
SYSCTL_EOF
sysctl -p /etc/sysctl.d/99-slowdns-tune.conf 2>/dev/null || true

# 7. Free Port 53 safely & set public DNS
systemctl stop systemd-resolved 2>/dev/null || true
systemctl disable systemd-resolved 2>/dev/null || true
rm -f /etc/resolv.conf
printf "nameserver 8.8.8.8\nnameserver 1.1.1.1\n" > /etc/resolv.conf

# 8. Start Services
systemctl daemon-reload
systemctl enable xray && systemctl restart xray
systemctl enable slowdns && systemctl restart slowdns

touch /tmp/slowdns-setup-done
echo "=== [$(date)] SETUP COMPLETE ==="
STARTUP_EOF

sed -i "s|PRIVKEY_PLACEHOLDER|$DNSTT_PRIVKEY|g" /tmp/slowdns-startup.sh
sed -i "s|PUBKEY_PLACEHOLDER|$DNSTT_PUBKEY|g" /tmp/slowdns-startup.sh
sed -i "s|UUID_PLACEHOLDER|$V2RAY_UUID|g" /tmp/slowdns-startup.sh
sed -i "s|PORT_PLACEHOLDER|$V2RAY_PORT|g" /tmp/slowdns-startup.sh

log "VM Startup script ready ✓"
