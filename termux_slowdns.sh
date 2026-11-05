#!/bin/bash
# ==============================================================================
#  Termux Turbo dnstt-client + V2RayNG / NekoBox Chaining Setup & Runner
#  Features:
#   - 8-Socket Multi-Resolver UDP Striping (8.8.8.8:53 + 8.8.4.4:53)
#   - KCP Turbo Mode (nodelay=1, interval=40ms, resend=0, nc=1)
#   - 16MB/4MB smux Buffers & QueueSize=2048 (Matched with GCP Server)
#   - 15s Handshake Timeout + Auto-Healing Session Reconnect (Never disconnects)
# ==============================================================================

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

BIN_DIR="$HOME/bin"
BIN_PATH="$BIN_DIR/dnstt-client"
CONF_FILE="$HOME/.slowdns_termux.conf"
mkdir -p "$BIN_DIR"

echo -e "${BOLD}${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║   ⚡ Termux Turbo SlowDNS (dnstt-client) + V2RayNG/NekoBox ║${NC}"
echo -e "${BOLD}${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"

# ── 1. Install Dependencies in Termux (if missing) ──────────────────────────
if command -v pkg >/dev/null 2>&1; then
    NEED_PKGS=()
    command -v go >/dev/null 2>&1 || NEED_PKGS+=("golang")
    command -v curl >/dev/null 2>&1 || NEED_PKGS+=("curl")
    command -v unzip >/dev/null 2>&1 || NEED_PKGS+=("unzip")
    command -v python3 >/dev/null 2>&1 || NEED_PKGS+=("python")
    if [[ ${#NEED_PKGS[@]} -gt 0 ]]; then
        echo -e "${CYAN}[*] Installing required Termux packages (${NEED_PKGS[*]})...${NC}"
        pkg update -y && pkg install -y "${NEED_PKGS[@]}" termux-tools
    fi
    # Acquire Termux wake-lock so Android doesn't kill the tunnel in background
    command -v termux-wake-lock >/dev/null 2>&1 && termux-wake-lock 2>/dev/null || true
fi

# ── 2. Compile Turbo-Patched dnstt-client (if not already built) ────────────
if [[ ! -x "$BIN_PATH" ]] || [[ "${1:-}" == "--rebuild" ]]; then
    [[ "${1:-}" == "--rebuild" ]] && shift
    echo -e "${CYAN}[*] Downloading & compiling Turbo-Patched dnstt-client...${NC}"
    BUILD_DIR="$HOME/.dnstt_build"
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"

    curl -fsSL "https://proxy.golang.org/www.bamsoftware.com/git/dnstt.git/@v/v1.20260501.0.zip" -o "$BUILD_DIR/dnstt.zip"
    unzip -q "$BUILD_DIR/dnstt.zip" -d "$BUILD_DIR"
    SRC_DIR="$BUILD_DIR/www.bamsoftware.com/git/dnstt.git@v1.20260501.0"

    python3 - "$SRC_DIR" << 'PY_EOF'
import os, sys

base = sys.argv[1]

# 1. Patch turbotunnel/consts.go (QueueSize = 2048 to match GCP server)
consts_path = os.path.join(base, "turbotunnel/consts.go")
with open(consts_path, "r") as f:
    c = f.read()
c = c.replace("const QueueSize = 128", "const QueueSize = 2048")
with open(consts_path, "w") as f:
    f.write(c)

# 2. Patch dnstt-client/dns.go (30ms fast poll, 128 pollLimit, 4x downstream burst, clean Close)
dns_path = os.path.join(base, "dnstt-client/dns.go")
with open(dns_path, "r") as f:
    d = f.read()

d = d.replace(
    "\tinitPollDelay       = 500 * time.Millisecond\n\tmaxPollDelay        = 10 * time.Second\n\tpollDelayMultiplier = 2.0\n\n\t// A limit on the number of empty poll requests we may send in a burst\n\t// as a result of receiving data.\n\tpollLimit = 16",
    "\tinitPollDelay       = 30 * time.Millisecond\n\tmaxPollDelay        = 500 * time.Millisecond\n\tpollDelayMultiplier = 1.3\n\n\t// A limit on the number of empty poll requests we may send in a burst\n\t// as a result of receiving data.\n\tpollLimit = 128",
    1,
)
d = d.replace(
    "\tpollChan chan struct{}\n\t// QueuePacketConn",
    "\tpollChan chan struct{}\n\tclosed   chan struct{}\n\t// QueuePacketConn",
    1,
)
d = d.replace(
    "\t\tpollChan:        make(chan struct{}, pollLimit),\n\t\tQueuePacketConn: turbotunnel.NewQueuePacketConn(clientID, 0),",
    "\t\tpollChan:        make(chan struct{}, pollLimit),\n\t\tclosed:          make(chan struct{}),\n\t\tQueuePacketConn: turbotunnel.NewQueuePacketConn(clientID, 0),",
    1,
)
d = d.replace(
    "func (c *DNSPacketConn) recvLoop(transport net.PacketConn) error {",
    "func (c *DNSPacketConn) Close() error {\n\tselect {\n\tcase <-c.closed:\n\tdefault:\n\t\tclose(c.closed)\n\t}\n\treturn c.QueuePacketConn.Close()\n}\n\nfunc (c *DNSPacketConn) recvLoop(transport net.PacketConn) error {",
    1,
)
d = d.replace(
    "\t\tif any {\n\t\t\tselect {\n\t\t\tcase c.pollChan <- struct{}{}:\n\t\t\tdefault:\n\t\t\t}\n\t\t}",
    "\t\tif any {\n\t\t\tfor i := 0; i < 4; i++ {\n\t\t\t\tselect {\n\t\t\t\tcase c.pollChan <- struct{}{}:\n\t\t\t\tdefault:\n\t\t\t\t}\n\t\t\t}\n\t\t}",
    1,
)
d = d.replace(
    "\t\tselect {\n\t\tcase p = <-outgoing:\n\t\tdefault:\n\t\t\tselect {\n\t\t\tcase p = <-outgoing:\n\t\t\tcase <-c.pollChan:\n\t\t\tcase <-pollTimer.C:\n\t\t\t\tpollTimerExpired = true\n\t\t\t}\n\t\t}",
    "\t\tselect {\n\t\tcase <-c.closed:\n\t\t\treturn nil\n\t\tcase p = <-outgoing:\n\t\tdefault:\n\t\t\tselect {\n\t\t\tcase <-c.closed:\n\t\t\t\treturn nil\n\t\t\tcase p = <-outgoing:\n\t\t\tcase <-c.pollChan:\n\t\t\tcase <-pollTimer.C:\n\t\t\t\tpollTimerExpired = true\n\t\t\t}\n\t\t}",
    1,
)
with open(dns_path, "w") as f:
    f.write(d)

# 3. Patch dnstt-client/main.go (8-Socket Multi-Resolver UDP + Turbo KCP + Auto-Reconnect)
main_path = os.path.join(base, "dnstt-client/main.go")
with open(main_path, "r") as f:
    m = f.read()

m = m.replace('\t"sync"\n', '\t"sync"\n\t"sync/atomic"\n', 1)
m = m.replace("const idleTimeout = 2 * time.Minute", "const idleTimeout = 10 * time.Minute", 1)

multi_udp_code = """// MultiUDPPacketConn stripes DNS queries across multiple UDP sockets and multiple DNS resolvers.
type MultiUDPPacketConn struct {
	conns  []*net.UDPConn
	addrs  []*net.UDPAddr
	idx    uint64
	closed chan struct{}
	*turbotunnel.QueuePacketConn
}

func NewMultiUDPPacketConn(spec string, numSockets int) (*MultiUDPPacketConn, error) {
	var addrs []*net.UDPAddr
	for _, part := range strings.Split(spec, ",") {
		part = strings.TrimSpace(part)
		if part == "" {
			continue
		}
		if !strings.Contains(part, ":") {
			part = part + ":53"
		}
		a, err := net.ResolveUDPAddr("udp", part)
		if err != nil {
			return nil, err
		}
		addrs = append(addrs, a)
	}
	if len(addrs) == 0 {
		return nil, fmt.Errorf("no valid UDP addresses in %q", spec)
	}
	c := &MultiUDPPacketConn{
		addrs:           addrs,
		closed:          make(chan struct{}),
		QueuePacketConn: turbotunnel.NewQueuePacketConn(turbotunnel.DummyAddr{}, 0),
	}
	for i := 0; i < numSockets; i++ {
		uc, err := net.ListenUDP("udp", nil)
		if err != nil {
			for _, prev := range c.conns {
				prev.Close()
			}
			return nil, err
		}
		_ = uc.SetReadBuffer(4 * 1024 * 1024)
		_ = uc.SetWriteBuffer(4 * 1024 * 1024)
		c.conns = append(c.conns, uc)
		go func(conn *net.UDPConn) {
			var buf [4096]byte
			for {
				n, _, err := conn.ReadFrom(buf[:])
				if err != nil {
					return
				}
				c.QueuePacketConn.QueueIncoming(buf[:n], turbotunnel.DummyAddr{})
			}
		}(uc)
	}
	go func() {
		out := c.QueuePacketConn.OutgoingQueue(turbotunnel.DummyAddr{})
		for {
			select {
			case <-c.closed:
				return
			case p, ok := <-out:
				if !ok {
					return
				}
				n := atomic.AddUint64(&c.idx, 1)
				conn := c.conns[n%uint64(len(c.conns))]
				addr := c.addrs[(n/uint64(len(c.conns)))%uint64(len(c.addrs))]
				if _, err := conn.WriteTo(p, addr); err != nil {
					if errors.Is(err, net.ErrClosed) {
						return
					}
				}
			}
		}
	}()
	return c, nil
}

func (c *MultiUDPPacketConn) Close() error {
	select {
	case <-c.closed:
	default:
		close(c.closed)
	}
	for _, uc := range c.conns {
		_ = uc.Close()
	}
	return c.QueuePacketConn.Close()
}

"""

m = m.replace("func handle(", multi_udp_code + "func handle(", 1)

old_run = """func run(pubkey []byte, domain dns.Name, localAddr *net.TCPAddr, remoteAddr net.Addr, pconn net.PacketConn) error {
	defer pconn.Close()

	ln, err := net.ListenTCP("tcp", localAddr)
	if err != nil {
		return fmt.Errorf("opening local listener: %v", err)
	}
	defer ln.Close()

	mtu := dnsNameCapacity(domain) - 8 - 1 - numPadding - 1 // clientid + padding length prefix + padding + data length prefix
	if mtu < 80 {
		return fmt.Errorf("domain %s leaves only %d bytes for payload", domain, mtu)
	}
	log.Printf("effective MTU %d", mtu)

	// Open a KCP conn on the PacketConn.
	conn, err := kcp.NewConn2(remoteAddr, nil, 0, 0, pconn)
	if err != nil {
		return fmt.Errorf("opening KCP conn: %v", err)
	}
	defer func() {
		log.Printf("end session %08x", conn.GetConv())
		conn.Close()
	}()
	log.Printf("begin session %08x", conn.GetConv())
	// Permit coalescing the payloads of consecutive sends.
	conn.SetStreamMode(true)
	// Disable the dynamic congestion window (limit only by the maximum of
	// local and remote static windows).
	conn.SetNoDelay(
		0, // default nodelay
		0, // default interval
		0, // default resend
		1, // nc=1 => congestion window off
	)
	conn.SetWindowSize(turbotunnel.QueueSize/2, turbotunnel.QueueSize/2)
	if rc := conn.SetMtu(mtu); !rc {
		panic(rc)
	}

	// Put a Noise channel on top of the KCP conn.
	rw, err := noise.NewClient(conn, pubkey)
	if err != nil {
		return err
	}

	// Start a smux session on the Noise channel.
	smuxConfig := smux.DefaultConfig()
	smuxConfig.Version = 2
	smuxConfig.KeepAliveTimeout = idleTimeout
	smuxConfig.MaxStreamBuffer = 1 * 1024 * 1024 // default is 65536
	sess, err := smux.Client(rw, smuxConfig)
	if err != nil {
		return fmt.Errorf("opening smux session: %v", err)
	}
	defer sess.Close()

	for {
		local, err := ln.Accept()
		if err != nil {
			if err, ok := err.(net.Error); ok && err.Temporary() {
				continue
			}
			return err
		}
		go func() {
			defer local.Close()
			err := handle(local.(*net.TCPConn), sess, conn.GetConv())
			if err != nil {
				log.Printf("handle: %v", err)
			}
		}()
	}
}"""

new_run = """func runSession(pubkey []byte, domain dns.Name, mtu int, acceptChan chan *net.TCPConn, makeTransport func() (net.Addr, net.PacketConn, error)) error {
	remoteAddr, rawPconn, err := makeTransport()
	if err != nil {
		return fmt.Errorf("transport: %v", err)
	}
	defer rawPconn.Close()

	pconn := NewDNSPacketConn(rawPconn, remoteAddr, domain)
	defer pconn.Close()

	conn, err := kcp.NewConn2(remoteAddr, nil, 0, 0, pconn)
	if err != nil {
		return fmt.Errorf("opening KCP conn: %v", err)
	}
	defer func() {
		log.Printf("end session %08x", conn.GetConv())
		conn.Close()
	}()
	log.Printf("begin session %08x (connecting via DNS...)", conn.GetConv())
	conn.SetStreamMode(true)
	conn.SetNoDelay(
		1,  // nodelay=1 (turbo)
		20, // interval=20ms (was 40ms)
		2,  // resend=2 (FAST RETRANSMIT ON 2 ACK SKIPS - no stalling on mobile jitter!)
		1,  // nc=1 => congestion window off
	)
	conn.SetWindowSize(turbotunnel.QueueSize/2, turbotunnel.QueueSize/2)
	if rc := conn.SetMtu(mtu); !rc {
		panic(rc)
	}

	_ = conn.SetDeadline(time.Now().Add(15 * time.Second))
	rw, err := noise.NewClient(conn, pubkey)
	_ = conn.SetDeadline(time.Time{})
	if err != nil {
		return fmt.Errorf("noise handshake: %v", err)
	}

	smuxConfig := smux.DefaultConfig()
	smuxConfig.Version = 2
	smuxConfig.KeepAliveInterval = 10 * time.Second
	smuxConfig.KeepAliveTimeout = idleTimeout
	smuxConfig.MaxReceiveBuffer = 16 * 1024 * 1024
	smuxConfig.MaxStreamBuffer = 4 * 1024 * 1024
	sess, err := smux.Client(rw, smuxConfig)
	if err != nil {
		return fmt.Errorf("opening smux session: %v", err)
	}
	defer sess.Close()
	log.Printf("session %08x READY ✓ (V2RayNG / NekoBox can now transmit!)", conn.GetConv())

	for {
		select {
		case <-sess.CloseChan():
			return fmt.Errorf("smux session closed")
		case local := <-acceptChan:
			go func(local *net.TCPConn) {
				err := handle(local, sess, conn.GetConv())
				if err != nil {
					log.Printf("handle: %v", err)
					if sess.IsClosed() {
						select {
						case acceptChan <- local:
							return
						default:
						}
					}
				}
				local.Close()
			}(local)
		}
	}
}

func run(pubkey []byte, domain dns.Name, localAddr *net.TCPAddr, makeTransport func() (net.Addr, net.PacketConn, error)) error {
	ln, err := net.ListenTCP("tcp", localAddr)
	if err != nil {
		return fmt.Errorf("opening local listener: %v", err)
	}
	defer ln.Close()

	mtu := dnsNameCapacity(domain) - 8 - 1 - numPadding - 1
	if mtu < 80 {
		return fmt.Errorf("domain %s leaves only %d bytes for payload", domain, mtu)
	}
	log.Printf("effective MTU %d | listening on %s", mtu, localAddr)

	acceptChan := make(chan *net.TCPConn, 128)
	go func() {
		for {
			local, err := ln.AcceptTCP()
			if err != nil {
				if ne, ok := err.(net.Error); ok && ne.Temporary() {
					time.Sleep(50 * time.Millisecond)
					continue
				}
				return
			}
			_ = local.SetNoDelay(true)
			_ = local.SetKeepAlive(true)
			_ = local.SetKeepAlivePeriod(15 * time.Second)
			acceptChan <- local
		}
	}()

	for {
		err := runSession(pubkey, domain, mtu, acceptChan, makeTransport)
		log.Printf("tunnel session ended (%v) — auto-reconnecting in 1s...", err)
		time.Sleep(1 * time.Second)
	}
}"""

assert old_run in m
m = m.replace(old_run, new_run, 1)

old_udp = """		// -udp
		{udpAddr, func(s string) (net.Addr, net.PacketConn, error) {
			addr, err := net.ResolveUDPAddr("udp", s)
			if err != nil {
				return nil, nil, err
			}
			pconn, err := net.ListenUDP("udp", nil)
			return addr, pconn, err
		}},
	} {
		if opt.s == "" {
			continue
		}
		if pconn != nil {
			fmt.Fprintf(os.Stderr, "only one of -doh, -dot, and -udp may be given\\n")
			os.Exit(1)
		}
		var err error
		remoteAddr, pconn, err = opt.f(opt.s)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
	}
	if pconn == nil {
		fmt.Fprintf(os.Stderr, "one of -doh, -dot, or -udp is required\\n")
		os.Exit(1)
	}

	pconn = NewDNSPacketConn(pconn, remoteAddr, domain)
	err = run(pubkey, domain, localAddr, remoteAddr, pconn)"""

new_udp = """		// -udp (8-Socket Multi-Resolver Pool)
		{udpAddr, func(s string) (net.Addr, net.PacketConn, error) {
			pconn, err := NewMultiUDPPacketConn(s, 8)
			return turbotunnel.DummyAddr{}, pconn, err
		}},
	} {
		if opt.s == "" {
			continue
		}
		if makeTransport != nil {
			fmt.Fprintf(os.Stderr, "only one of -doh, -dot, and -udp may be given\\n")
			os.Exit(1)
		}
		optS := opt.s
		optF := opt.f
		makeTransport = func() (net.Addr, net.PacketConn, error) {
			return optF(optS)
		}
	}
	if makeTransport == nil {
		fmt.Fprintf(os.Stderr, "one of -doh, -dot, or -udp is required\\n")
		os.Exit(1)
	}

	err = run(pubkey, domain, localAddr, makeTransport)"""

m = m.replace("var remoteAddr net.Addr\n\tvar pconn net.PacketConn", "var makeTransport func() (net.Addr, net.PacketConn, error)", 1)
assert old_udp in m
m = m.replace(old_udp, new_udp, 1)

with open(main_path, "w") as f:
    f.write(m)
PY_EOF

    cd "$SRC_DIR/dnstt-client"
    GOPROXY="https://proxy.golang.org,direct" CGO_ENABLED=0 go build -ldflags="-s -w" -o "$BIN_PATH" .
    chmod +x "$BIN_PATH"
    rm -rf "$BUILD_DIR"
    echo -e "${GREEN}[✔] Turbo dnstt-client compiled at $BIN_PATH!${NC}"
fi

# ── 3. Load or Prompt Configuration ─────────────────────────────────────────
DEFAULT_PUBKEY="58a0eeb51c71ad9fe39997ded7cf4e1f9700d497edd47af5c2c42a66611bc34c"
DEFAULT_DOMAIN="x.foridul.pp.ua"
DEFAULT_UUID="60c44ed2-4dd4-43ab-9a66-a0b40623a1d4"

if [[ -f "$CONF_FILE" ]]; then
    source "$CONF_FILE"
fi

# Always force the permanent keypair & UUID unless explicitly overridden via CLI args $2/$3
PUBKEY="$DEFAULT_PUBKEY"
VLESS_UUID="$DEFAULT_UUID"
if [[ "${TUNNEL_DOMAIN:-}" == "YOUR_NS_DOMAIN" || "${TUNNEL_DOMAIN:-}" == "tunnel2.foridul.pp.ua" ]]; then
    TUNNEL_DOMAIN="$DEFAULT_DOMAIN"
fi

# CLI args override: bash termux_slowdns.sh [TUNNEL_DOMAIN] [PUBKEY] [VLESS_UUID] [DNS_TARGET] [LOCAL_PORT]
if [[ -n "${1:-}" ]]; then
    if [[ ${#1} -eq 64 && "$1" != *.* ]]; then
        PUBKEY="$1"
        [[ -n "${2:-}" ]] && TUNNEL_DOMAIN="$2"
    else
        TUNNEL_DOMAIN="$1"
        [[ -n "${2:-}" ]] && PUBKEY="$2"
    fi
fi
[[ -n "${3:-}" ]] && VLESS_UUID="$3"
[[ -n "${4:-}" ]] && DNS_TARGET="$4"
[[ -n "${5:-}" ]] && LOCAL_PORT="$5"

PUBKEY="${PUBKEY:-$DEFAULT_PUBKEY}"
VLESS_UUID="${VLESS_UUID:-$DEFAULT_UUID}"

if [[ -z "${TUNNEL_DOMAIN:-}" ]]; then
    echo -ne "${YELLOW}🌐 Tunnel NS Domain [Auto: $DEFAULT_DOMAIN in 3s]: ${NC}"
    read -t 3 -r INPUT_DOMAIN || echo ""
    TUNNEL_DOMAIN="${INPUT_DOMAIN:-$DEFAULT_DOMAIN}"
fi
TUNNEL_DOMAIN=$(echo "$TUNNEL_DOMAIN" | tr -d '[:space:]')
PUBKEY=$(echo "$PUBKEY" | tr -d '[:space:]')
VLESS_UUID=$(echo "$VLESS_UUID" | tr -d '[:space:]')

if [[ -z "${DNS_TARGET:-}" ]]; then
    echo ""
    echo -e "${BOLD}${CYAN}সিলেক্ট করো Google DNS Tunnel Mode:${NC}"
    echo -e "  ${GREEN}1)${NC} Google Multi-DNS UDP (${YELLOW}8.8.8.8:53,8.8.4.4:53${NC}) — [Recommended]"
    echo -e "  ${GREEN}2)${NC} Google + Cloudflare UDP (${YELLOW}8.8.8.8:53,8.8.4.4:53,1.1.1.1:53,1.0.0.1:53${NC})"
    echo -e "  ${GREEN}3)${NC} Google DoH HTTPS (${YELLOW}https://dns.google/dns-query${NC})"
    echo -e "  ${GREEN}4)${NC} Google DoT TLS (${YELLOW}dns.google:853${NC})"
    echo -e "  ${GREEN}5)${NC} Custom DNS IP (নিজের ইচ্ছেমতো DNS IP)"
    echo -ne "${YELLOW}পছন্দ (1-5) [Auto: 1 in 3s]: ${NC}"
    read -t 3 -r MODE_CHOICE || echo ""
    case "${MODE_CHOICE:-1}" in
        2) DNS_MODE="-udp"; DNS_TARGET="8.8.8.8:53,8.8.4.4:53,1.1.1.1:53,1.0.0.1:53" ;;
        3) DNS_MODE="-doh"; DNS_TARGET="https://dns.google/dns-query" ;;
        4) DNS_MODE="-dot"; DNS_TARGET="dns.google:853" ;;
        5)
            DNS_MODE="-udp"
            echo -ne "${YELLOW}Enter DNS IP(s) (comma-separated, e.g. 8.8.8.8:53): ${NC}"
            read -r DNS_TARGET
            ;;
        *) DNS_MODE="-udp"; DNS_TARGET="8.8.8.8:53,8.8.4.4:53" ;;
    esac
else
    if [[ "$DNS_TARGET" == https://* ]]; then
        DNS_MODE="-doh"
    elif [[ "$DNS_TARGET" == *:853 ]]; then
        DNS_MODE="-dot"
    else
        DNS_MODE="-udp"
    fi
fi

LOCAL_PORT="${LOCAL_PORT:-10086}"

# Save configuration for quick restart next time
cat > "$CONF_FILE" << EOF
PUBKEY="$PUBKEY"
TUNNEL_DOMAIN="$TUNNEL_DOMAIN"
VLESS_UUID="$VLESS_UUID"
DNS_MODE="$DNS_MODE"
DNS_TARGET="$DNS_TARGET"
LOCAL_PORT="$LOCAL_PORT"
EOF

# Create 'slowdns' shortcut in Termux $PREFIX/bin if available
if [[ -n "${PREFIX:-}" && -d "$PREFIX/bin" ]]; then
    SCRIPT_REAL=$(realpath "$0" 2>/dev/null || echo "$HOME/termux_slowdns.sh")
    cp -f "$0" "$HOME/termux_slowdns.sh" 2>/dev/null || true
    chmod +x "$HOME/termux_slowdns.sh"
    cat > "$PREFIX/bin/slowdns" << SHORTCUT_EOF
#!/bin/bash
exec bash "$HOME/termux_slowdns.sh" "\$@"
SHORTCUT_EOF
    chmod +x "$PREFIX/bin/slowdns"
fi

echo ""
echo -e "${BOLD}${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${GREEN}  🚀 Termux SlowDNS Tunnel Starting on 127.0.0.1:$LOCAL_PORT${NC}"
echo -e "${BOLD}${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "  ${CYAN}Tunnel Domain :${NC} ${YELLOW}$TUNNEL_DOMAIN${NC}"
echo -e "  ${CYAN}DNS Resolver  :${NC} ${YELLOW}$DNS_MODE $DNS_TARGET${NC} (8x Socket Pool)"
echo -e "  ${CYAN}Local Port    :${NC} ${GREEN}127.0.0.1:$LOCAL_PORT${NC}"

if [[ -n "$VLESS_UUID" ]]; then
    VLESS_LINK="vless://${VLESS_UUID}@127.0.0.1:${LOCAL_PORT}?encryption=none&security=none&type=tcp#Termux-SlowDNS-Turbo"
    echo ""
    echo -e "${BOLD}${CYAN}📲 নিচের VLESS লিংকটি কপি করে V2RayNG বা NekoBox-এ Import করে স্টার্ট দাও:${NC}"
    echo -e "${BOLD}${YELLOW}$VLESS_LINK${NC}"
fi

echo ""
echo -e "${CYAN}[i] লগে 'session ... READY ✓' লেখা আসলেই V2RayNG / NekoBox কানেক্ট করো!${NC}"
echo -e "${CYAN}[i] বন্ধ করতে Ctrl+C চাপো। পরের বার শুধু 'slowdns' লিখে এন্টার দিলেই চালু হবে।${NC}"
echo -e "${BOLD}${GREEN}────────────────────────────────────────────────────────────${NC}"

# Kill any old instance bound to LOCAL_PORT
pkill -f "dnstt-client.*127.0.0.1:${LOCAL_PORT}" 2>/dev/null || true

exec "$BIN_PATH" "$DNS_MODE" "$DNS_TARGET" -pubkey "$PUBKEY" "$TUNNEL_DOMAIN" "127.0.0.1:${LOCAL_PORT}"
