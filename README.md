# 🚀 V2Ray + SlowDNS — Google Cloud Shell Setup

One-command setup script to run a **V2Ray (VMess)** proxy server tunneled through **SlowDNS** on Google Cloud Shell (free).

## ⚡ Quick Start (GCP Cloud Shell)

```bash
git clone https://github.com/foridul422/v2ray-slowdns-gcp.git
cd v2ray-slowdns-gcp
bash install.sh
```

## 📋 What it does

1. **Detects Public IP** → Shows you exactly which IP to point your NS record to
2. **Takes your domain** → Sets up SlowDNS tunnel subdomain
3. **Installs SlowDNS** → Generates RSA key pair, starts DNS tunnel server on port 53
4. **Installs V2Ray** → Generates UUID, creates VMess config
5. **Outputs everything** →
   - DNS NS record setup instructions
   - SlowDNS Public Key (for Android app)
   - `vmess://` link (import directly in V2RayNG/NekoBox)

## 🌐 DNS Setup (after running script)

| Type | Host | Value |
|------|------|-------|
| A | `ns1` | `<Your GCP IP>` |
| NS | `tunnel` | `ns1.yourdomain.com` |

## 📱 Client Apps Needed

- **SlowDNS** (Android) — DNS tunnel client
- **V2RayNG** or **NekoBox** (Android) — V2Ray client

## 📁 File Structure

```
.
├── install.sh              # Master script — run this!
├── 01_setup_env.sh         # Environment setup + IP detection
├── 03_slowdns_install.sh   # SlowDNS install + RSA keys
├── 04_v2ray_install.sh     # V2Ray install + config
└── 07_client_config.sh     # VMess link + client output
```

## ⚠️ Notes

- Google Cloud Shell **disconnects after ~20 min idle** — script uses `screen` to keep services running
- Requires a domain where you can set **NS records**
- Port 53 (UDP) must be open — script handles `systemd-resolved` conflict automatically
