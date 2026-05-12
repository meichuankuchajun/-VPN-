#!/usr/bin/env bash

set -euo pipefail

PRESET_CONFIGS=(
  "default"     # VMess 10086, VLESS Reality 10443, SS legacy 8388, SS2022 8389, subscription 8090
  "compact"     # VMess 18086, VLESS Reality 18443, SS legacy 18388, SS2022 18389, subscription 18090
  "alt"         # VMess 26086, VLESS Reality 26443, SS legacy 26388, SS2022 26389, subscription 26090
)

INSTALL_PRESET="${INSTALL_PRESET:-default}"
STACK_NAME="${STACK_NAME:-vpn-stack}"

XRAY_VERSION="${XRAY_VERSION:-v1.8.24}"
SS_VERSION="${SS_VERSION:-v1.24.0}"
SERVER_IP="${SERVER_IP:-}"

ENABLE_VMESS="${ENABLE_VMESS:-1}"
ENABLE_VLESS_REALITY="${ENABLE_VLESS_REALITY:-1}"
ENABLE_SS_LEGACY="${ENABLE_SS_LEGACY:-1}"
ENABLE_SS2022="${ENABLE_SS2022:-1}"

REALITY_SERVER_NAME="${REALITY_SERVER_NAME:-www.cloudflare.com}"
REALITY_DEST="${REALITY_DEST:-www.cloudflare.com:443}"

case "${INSTALL_PRESET}" in
  default)
    DEFAULT_XRAY_PORT=10086
    DEFAULT_VLESS_REALITY_PORT=10443
    DEFAULT_SS_LEGACY_PORT=8388
    DEFAULT_SS2022_PORT=8389
    DEFAULT_SUB_PORT=8090
    ;;
  compact)
    DEFAULT_XRAY_PORT=18086
    DEFAULT_VLESS_REALITY_PORT=18443
    DEFAULT_SS_LEGACY_PORT=18388
    DEFAULT_SS2022_PORT=18389
    DEFAULT_SUB_PORT=18090
    ;;
  alt)
    DEFAULT_XRAY_PORT=26086
    DEFAULT_VLESS_REALITY_PORT=26443
    DEFAULT_SS_LEGACY_PORT=26388
    DEFAULT_SS2022_PORT=26389
    DEFAULT_SUB_PORT=26090
    ;;
  *)
    echo "Unsupported INSTALL_PRESET: ${INSTALL_PRESET}"
    exit 1
    ;;
esac

XRAY_PORT="${XRAY_PORT:-$DEFAULT_XRAY_PORT}"
VLESS_REALITY_PORT="${VLESS_REALITY_PORT:-$DEFAULT_VLESS_REALITY_PORT}"
SS_LEGACY_PORT="${SS_LEGACY_PORT:-$DEFAULT_SS_LEGACY_PORT}"
SS_PORT="${SS_PORT:-$DEFAULT_SS2022_PORT}"
SUB_PORT="${SUB_PORT:-$DEFAULT_SUB_PORT}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Please run as root."
  exit 1
fi

if [[ -z "${SERVER_IP}" ]]; then
  SERVER_IP="$(curl -fsSL https://api.ipify.org)"
fi

if [[ -z "${SERVER_IP}" ]]; then
  echo "Unable to determine server IP. Set SERVER_IP manually."
  exit 1
fi

ARCH="$(uname -m)"
case "${ARCH}" in
  x86_64)
    XRAY_ARCH="64"
    SS_ARCH="x86_64-unknown-linux-gnu"
    ;;
  aarch64)
    XRAY_ARCH="arm64-v8a"
    SS_ARCH="aarch64-unknown-linux-gnu"
    ;;
  *)
    echo "Unsupported architecture: ${ARCH}"
    exit 1
    ;;
esac

WORK_DIR="/opt/${STACK_NAME}"
SUB_DIR="${WORK_DIR}/subscription/public"
XRAY_ASSET_DIR="/usr/local/share/xray"
XRAY_BIN="/usr/local/bin/xray"
SS_BIN="/usr/local/bin/ssserver"
SSSERVICE_BIN="/usr/local/bin/ssservice"
SUB_SERVER_BIN="/usr/local/bin/${STACK_NAME}-subscription-server.py"

XRAY_CONFIG_DIR="/usr/local/etc/${STACK_NAME}-xray"
SS_LEGACY_CONFIG_DIR="/etc/${STACK_NAME}-shadowsocks-legacy"
SS2022_CONFIG_DIR="/etc/${STACK_NAME}-shadowsocks-rust"

XRAY_SERVICE_NAME="xray-${STACK_NAME}"
SS_LEGACY_SERVICE_NAME="shadowsocks-legacy-${STACK_NAME}"
SS2022_SERVICE_NAME="shadowsocks-rust-${STACK_NAME}"
SUB_SERVICE_NAME="clash-subscription-${STACK_NAME}"

VMESS_UUID=""
VLESS_UUID=""
VLESS_PRIVATE_KEY=""
VLESS_PUBLIC_KEY=""
VLESS_SHORT_ID=""
SS_LEGACY_PASSWORD=""
SS2022_PASSWORD=""
CLASSIC_TOKEN=""
META_TOKEN=""

log() {
  echo
  echo "==> $1"
}

random_alnum() {
  local length="$1"
  python3 - "$length" <<'PY'
import secrets
import string
import sys
alphabet = string.ascii_letters + string.digits
length = int(sys.argv[1])
print(''.join(secrets.choice(alphabet) for _ in range(length)))
PY
}

wait_for_http() {
  local url="$1"
  local attempts="${2:-20}"
  local delay="${3:-1}"
  local i

  for ((i=1; i<=attempts; i++)); do
    if curl -fsSL "${url}" >/dev/null 2>&1; then
      return 0
    fi
    sleep "${delay}"
  done

  return 1
}

install_packages() {
  log "Installing dependencies"
  apt-get update
  apt-get install -y curl unzip xz-utils python3 ca-certificates
}

prepare_secrets() {
  VMESS_UUID="$(cat /proc/sys/kernel/random/uuid)"
  VLESS_UUID="$(cat /proc/sys/kernel/random/uuid)"
  VLESS_SHORT_ID="$(random_alnum 8 | tr 'A-Z' 'a-z')"
  SS_LEGACY_PASSWORD="$(random_alnum 32)"
  CLASSIC_TOKEN="$(random_alnum 24)"
  META_TOKEN="$(random_alnum 24)"
}

install_xray() {
  log "Installing Xray"
  mkdir -p "${WORK_DIR}" "${XRAY_ASSET_DIR}"
  cd "${WORK_DIR}"
  curl -fsSL "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-${XRAY_ARCH}.zip" -o xray.zip
  unzip -o xray.zip -d xray-dist >/dev/null
  install -m 0755 xray-dist/xray "${XRAY_BIN}"
  if [[ -f xray-dist/geoip.dat ]]; then
    install -m 0644 xray-dist/geoip.dat "${XRAY_ASSET_DIR}/geoip.dat"
  fi
  if [[ -f xray-dist/geosite.dat ]]; then
    install -m 0644 xray-dist/geosite.dat "${XRAY_ASSET_DIR}/geosite.dat"
  fi

  if [[ "${ENABLE_VLESS_REALITY}" == "1" ]]; then
    mapfile -t reality_keys < <("${XRAY_BIN}" x25519)
    VLESS_PRIVATE_KEY="$(printf '%s\n' "${reality_keys[@]}" | awk -F': ' '/Private key/ {print $2}')"
    VLESS_PUBLIC_KEY="$(printf '%s\n' "${reality_keys[@]}" | awk -F': ' '/Public key/ {print $2}')"
  fi

  mkdir -p "${XRAY_CONFIG_DIR}"
  python3 - <<PY > "${XRAY_CONFIG_DIR}/config.json"
import json

enable_vmess = ${ENABLE_VMESS}
enable_vless = ${ENABLE_VLESS_REALITY}
config = {
    "log": {"loglevel": "warning"},
    "inbounds": [],
    "outbounds": [{"protocol": "freedom", "settings": {}}],
}

if enable_vmess:
    config["inbounds"].append({
        "port": ${XRAY_PORT},
        "protocol": "vmess",
        "settings": {
            "clients": [{"id": "${VMESS_UUID}", "alterId": 0}]
        },
        "streamSettings": {"network": "tcp"},
    })

if enable_vless:
    config["inbounds"].append({
        "port": ${VLESS_REALITY_PORT},
        "protocol": "vless",
        "settings": {
            "clients": [{"id": "${VLESS_UUID}", "flow": "xtls-rprx-vision"}],
            "decryption": "none",
        },
        "streamSettings": {
            "network": "tcp",
            "security": "reality",
            "realitySettings": {
                "show": False,
                "dest": "${REALITY_DEST}",
                "xver": 0,
                "serverNames": ["${REALITY_SERVER_NAME}"],
                "privateKey": "${VLESS_PRIVATE_KEY}",
                "shortIds": ["${VLESS_SHORT_ID}"],
            },
        },
        "sniffing": {
            "enabled": True,
            "destOverride": ["http", "tls", "quic"],
        },
    })

print(json.dumps(config, indent=2))
PY

  cat > "/etc/systemd/system/${XRAY_SERVICE_NAME}.service" <<EOF
[Unit]
Description=Xray Service (${STACK_NAME})
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${XRAY_BIN} run -config ${XRAY_CONFIG_DIR}/config.json
Restart=always
RestartSec=3
LimitNOFILE=51200

[Install]
WantedBy=multi-user.target
EOF
}

install_shadowsocks() {
  log "Installing Shadowsocks Rust"
  mkdir -p "${WORK_DIR}"
  cd "${WORK_DIR}"
  curl -fsSL "https://github.com/shadowsocks/shadowsocks-rust/releases/download/${SS_VERSION}/shadowsocks-${SS_VERSION}.${SS_ARCH}.tar.xz" -o shadowsocks.tar.xz
  tar -xf shadowsocks.tar.xz
  install -m 0755 ssserver "${SS_BIN}"
  install -m 0755 ssservice "${SSSERVICE_BIN}"

  if [[ "${ENABLE_SS_LEGACY}" == "1" ]]; then
    mkdir -p "${SS_LEGACY_CONFIG_DIR}"
    cat > "${SS_LEGACY_CONFIG_DIR}/config.json" <<EOF
{
  "server": "0.0.0.0",
  "server_port": ${SS_LEGACY_PORT},
  "method": "aes-256-gcm",
  "password": "${SS_LEGACY_PASSWORD}",
  "timeout": 300,
  "fast_open": false,
  "mode": "tcp_and_udp"
}
EOF
    cat > "/etc/systemd/system/${SS_LEGACY_SERVICE_NAME}.service" <<EOF
[Unit]
Description=Shadowsocks Legacy Server Service (${STACK_NAME})
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${SS_BIN} -c ${SS_LEGACY_CONFIG_DIR}/config.json
Restart=always
RestartSec=3
LimitNOFILE=51200

[Install]
WantedBy=multi-user.target
EOF
  fi

  if [[ "${ENABLE_SS2022}" == "1" ]]; then
    mkdir -p "${SS2022_CONFIG_DIR}"
    SS2022_PASSWORD="$(${SSSERVICE_BIN} genkey -m '2022-blake3-aes-256-gcm')"
    cat > "${SS2022_CONFIG_DIR}/config.json" <<EOF
{
  "server": "0.0.0.0",
  "server_port": ${SS_PORT},
  "method": "2022-blake3-aes-256-gcm",
  "password": "${SS2022_PASSWORD}",
  "timeout": 300,
  "fast_open": false,
  "mode": "tcp_and_udp"
}
EOF
    cat > "/etc/systemd/system/${SS2022_SERVICE_NAME}.service" <<EOF
[Unit]
Description=Shadowsocks 2022 Server Service (${STACK_NAME})
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${SS_BIN} -c ${SS2022_CONFIG_DIR}/config.json
Restart=always
RestartSec=3
LimitNOFILE=51200

[Install]
WantedBy=multi-user.target
EOF
  fi
}

install_subscription_server() {
  log "Installing subscription file server"
  mkdir -p "${SUB_DIR}"
  cat > "${SUB_SERVER_BIN}" <<EOF
#!/usr/bin/env python3
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler

PORT = ${SUB_PORT}
DIRECTORY = '${SUB_DIR}'

class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)

    def end_headers(self):
        self.send_header('Content-Type', 'text/yaml; charset=utf-8')
        self.send_header('Cache-Control', 'no-store')
        super().end_headers()

server = ThreadingHTTPServer(('0.0.0.0', PORT), Handler)
server.serve_forever()
EOF
  chmod 755 "${SUB_SERVER_BIN}"
  cat > "/etc/systemd/system/${SUB_SERVICE_NAME}.service" <<EOF
[Unit]
Description=Clash Subscription HTTP Server (${STACK_NAME})
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 ${SUB_SERVER_BIN}
Restart=always
RestartSec=3
WorkingDirectory=${SUB_DIR}

[Install]
WantedBy=multi-user.target
EOF
}

write_subscription_files() {
  log "Writing subscription files"
  python3 - <<PY > "${SUB_DIR}/${CLASSIC_TOKEN}.yaml"
classic = {
  "allow-lan": False,
  "external-controller": "127.0.0.1:9090",
  "log-level": "info",
  "mixed-port": 7890,
  "mode": "rule",
  "proxies": [],
  "proxy-groups": [{"name": "PROXY", "type": "select", "proxies": []}],
  "rules": [
    "DOMAIN-SUFFIX,google.com,PROXY",
    "DOMAIN-SUFFIX,youtube.com,PROXY",
    "DOMAIN-SUFFIX,facebook.com,PROXY",
    "DOMAIN-SUFFIX,twitter.com,PROXY",
    "DOMAIN-SUFFIX,github.com,PROXY",
    "DOMAIN-KEYWORD,google,PROXY",
    "GEOIP,CN,DIRECT",
    "MATCH,PROXY",
  ],
}

if ${ENABLE_VMESS}:
  classic["proxies"].append({
    "name": "COMPAT-VMESS-TCP",
    "type": "vmess",
    "server": "${SERVER_IP}",
    "port": ${XRAY_PORT},
    "uuid": "${VMESS_UUID}",
    "alterId": 0,
    "cipher": "auto",
    "network": "tcp",
    "udp": True,
  })
  classic["proxy-groups"][0]["proxies"].append("COMPAT-VMESS-TCP")

if ${ENABLE_SS_LEGACY}:
  classic["proxies"].append({
    "name": "COMPAT-SS-AES256GCM",
    "type": "ss",
    "server": "${SERVER_IP}",
    "port": ${SS_LEGACY_PORT},
    "cipher": "aes-256-gcm",
    "password": "${SS_LEGACY_PASSWORD}",
    "udp": True,
  })
  classic["proxy-groups"][0]["proxies"].append("COMPAT-SS-AES256GCM")

classic["proxy-groups"][0]["proxies"].append("DIRECT")

def dump_yaml(data, indent=0):
  space = "  " * indent
  if isinstance(data, dict):
    lines = []
    for key, value in data.items():
      if isinstance(value, (dict, list)):
        lines.append(f"{space}{key}:")
        lines.extend(dump_yaml(value, indent + 1))
      else:
        if isinstance(value, bool):
          text = "true" if value else "false"
        else:
          text = value
        lines.append(f"{space}{key}: {text}")
    return lines
  if isinstance(data, list):
    lines = []
    for item in data:
      if isinstance(item, dict):
        first = True
        for key, value in item.items():
          if first:
            if isinstance(value, (dict, list)):
              lines.append(f"{space}- {key}:")
              lines.extend(dump_yaml(value, indent + 1))
            else:
              text = "true" if value is True else "false" if value is False else value
              lines.append(f"{space}- {key}: {text}")
            first = False
          else:
            if isinstance(value, (dict, list)):
              lines.append(f"{space}  {key}:")
              lines.extend(dump_yaml(value, indent + 2))
            else:
              text = "true" if value is True else "false" if value is False else value
              lines.append(f"{space}  {key}: {text}")
      else:
        lines.append(f"{space}- {item}")
    return lines
  return [f"{space}{data}"]

print("\n".join(dump_yaml(classic)))
PY

  python3 - <<PY > "${SUB_DIR}/${META_TOKEN}.yaml"
meta = {
  "allow-lan": False,
  "external-controller": "127.0.0.1:9090",
  "log-level": "info",
  "mixed-port": 7890,
  "mode": "rule",
  "proxies": [],
  "proxy-groups": [{"name": "PROXY", "type": "select", "proxies": []}],
  "rules": [
    "DOMAIN-SUFFIX,google.com,PROXY",
    "DOMAIN-SUFFIX,youtube.com,PROXY",
    "DOMAIN-SUFFIX,facebook.com,PROXY",
    "DOMAIN-SUFFIX,twitter.com,PROXY",
    "DOMAIN-SUFFIX,github.com,PROXY",
    "DOMAIN-KEYWORD,google,PROXY",
    "GEOIP,CN,DIRECT",
    "MATCH,PROXY",
  ],
}

if ${ENABLE_VMESS}:
  meta["proxies"].append({
    "name": "LATEST-VMESS-TCP",
    "type": "vmess",
    "server": "${SERVER_IP}",
    "port": ${XRAY_PORT},
    "uuid": "${VMESS_UUID}",
    "alterId": 0,
    "cipher": "auto",
    "network": "tcp",
    "udp": True,
  })
  meta["proxy-groups"][0]["proxies"].append("LATEST-VMESS-TCP")

if ${ENABLE_VLESS_REALITY}:
  meta["proxies"].append({
    "name": "LATEST-VLESS-REALITY-VISION",
    "type": "vless",
    "server": "${SERVER_IP}",
    "port": ${VLESS_REALITY_PORT},
    "uuid": "${VLESS_UUID}",
    "network": "tcp",
    "udp": True,
    "tls": True,
    "servername": "${REALITY_SERVER_NAME}",
    "flow": "xtls-rprx-vision",
    "client-fingerprint": "chrome",
    "reality-opts": {
      "public-key": "${VLESS_PUBLIC_KEY}",
      "short-id": "${VLESS_SHORT_ID}",
    },
  })
  meta["proxy-groups"][0]["proxies"].append("LATEST-VLESS-REALITY-VISION")

if ${ENABLE_SS2022}:
  meta["proxies"].append({
    "name": "LATEST-SS2022-BLAKE3-AES256",
    "type": "ss",
    "server": "${SERVER_IP}",
    "port": ${SS_PORT},
    "cipher": "2022-blake3-aes-256-gcm",
    "password": "${SS2022_PASSWORD}",
    "udp": True,
  })
  meta["proxy-groups"][0]["proxies"].append("LATEST-SS2022-BLAKE3-AES256")

meta["proxy-groups"][0]["proxies"].append("DIRECT")

def dump_yaml(data, indent=0):
  space = "  " * indent
  if isinstance(data, dict):
    lines = []
    for key, value in data.items():
      if isinstance(value, (dict, list)):
        lines.append(f"{space}{key}:")
        lines.extend(dump_yaml(value, indent + 1))
      else:
        if isinstance(value, bool):
          text = "true" if value else "false"
        else:
          text = value
        lines.append(f"{space}{key}: {text}")
    return lines
  if isinstance(data, list):
    lines = []
    for item in data:
      if isinstance(item, dict):
        first = True
        for key, value in item.items():
          if first:
            if isinstance(value, (dict, list)):
              lines.append(f"{space}- {key}:")
              lines.extend(dump_yaml(value, indent + 1))
            else:
              text = "true" if value is True else "false" if value is False else value
              lines.append(f"{space}- {key}: {text}")
            first = False
          else:
            if isinstance(value, (dict, list)):
              lines.append(f"{space}  {key}:")
              lines.extend(dump_yaml(value, indent + 2))
            else:
              text = "true" if value is True else "false" if value is False else value
              lines.append(f"{space}  {key}: {text}")
      else:
        lines.append(f"{space}- {item}")
    return lines
  return [f"{space}{data}"]

print("\n".join(dump_yaml(meta)))
PY
}

start_services() {
  log "Starting services"
  systemctl daemon-reload
  systemctl enable --now "${XRAY_SERVICE_NAME}.service"
  if [[ "${ENABLE_SS_LEGACY}" == "1" ]]; then
    systemctl enable --now "${SS_LEGACY_SERVICE_NAME}.service"
  fi
  if [[ "${ENABLE_SS2022}" == "1" ]]; then
    systemctl enable --now "${SS2022_SERVICE_NAME}.service"
  fi
  systemctl enable --now "${SUB_SERVICE_NAME}.service"
}

verify_services() {
  log "Verifying deployment"
  systemctl is-active "${XRAY_SERVICE_NAME}.service" >/dev/null
  if [[ "${ENABLE_SS_LEGACY}" == "1" ]]; then
    systemctl is-active "${SS_LEGACY_SERVICE_NAME}.service" >/dev/null
  fi
  if [[ "${ENABLE_SS2022}" == "1" ]]; then
    systemctl is-active "${SS2022_SERVICE_NAME}.service" >/dev/null
  fi
  systemctl is-active "${SUB_SERVICE_NAME}.service" >/dev/null
  wait_for_http "http://127.0.0.1:${SUB_PORT}/${CLASSIC_TOKEN}.yaml"
  wait_for_http "http://127.0.0.1:${SUB_PORT}/${META_TOKEN}.yaml"
}

print_summary() {
  cat <<EOF

Deployment complete.

Preset:
  ${INSTALL_PRESET}

Stack:
  ${STACK_NAME}

Server:
  ${SERVER_IP}

Enabled protocols:
  VMess: ${ENABLE_VMESS}
  VLESS Reality: ${ENABLE_VLESS_REALITY}
  Shadowsocks legacy: ${ENABLE_SS_LEGACY}
  Shadowsocks 2022: ${ENABLE_SS2022}

VMess:
  server: ${SERVER_IP}
  port: ${XRAY_PORT}
  uuid: ${VMESS_UUID}

VLESS Reality:
  server: ${SERVER_IP}
  port: ${VLESS_REALITY_PORT}
  uuid: ${VLESS_UUID}
  public-key: ${VLESS_PUBLIC_KEY}
  short-id: ${VLESS_SHORT_ID}
  server-name: ${REALITY_SERVER_NAME}

Shadowsocks legacy:
  server: ${SERVER_IP}
  port: ${SS_LEGACY_PORT}
  cipher: aes-256-gcm
  password: ${SS_LEGACY_PASSWORD}

Shadowsocks 2022:
  server: ${SERVER_IP}
  port: ${SS_PORT}
  cipher: 2022-blake3-aes-256-gcm
  password: ${SS2022_PASSWORD}

Subscriptions:
  classic: http://${SERVER_IP}:${SUB_PORT}/${CLASSIC_TOKEN}.yaml
  meta:    http://${SERVER_IP}:${SUB_PORT}/${META_TOKEN}.yaml

Services:
  ${XRAY_SERVICE_NAME}
  ${SS_LEGACY_SERVICE_NAME}
  ${SS2022_SERVICE_NAME}
  ${SUB_SERVICE_NAME}
EOF
}

prepare_secrets
install_packages
install_xray
install_shadowsocks
install_subscription_server
write_subscription_files
start_services
verify_services
print_summary
