#!/usr/bin/env bash

set -euo pipefail

STACK_NAME="${STACK_NAME:-vpn-stack}"
REMOVE_BINARIES="${REMOVE_BINARIES:-0}"

XRAY_SERVICE_NAME="xray-${STACK_NAME}"
SS_LEGACY_SERVICE_NAME="shadowsocks-legacy-${STACK_NAME}"
SS2022_SERVICE_NAME="shadowsocks-rust-${STACK_NAME}"
SUB_SERVICE_NAME="clash-subscription-${STACK_NAME}"

XRAY_CONFIG_DIR="/usr/local/etc/${STACK_NAME}-xray"
SS_LEGACY_CONFIG_DIR="/etc/${STACK_NAME}-shadowsocks-legacy"
SS2022_CONFIG_DIR="/etc/${STACK_NAME}-shadowsocks-rust"
WORK_DIR="/opt/${STACK_NAME}"
SUB_SERVER_BIN="/usr/local/bin/${STACK_NAME}-subscription-server.py"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Please run as root."
  exit 1
fi

stop_and_disable() {
  local service="$1"
  if systemctl list-unit-files | grep -q "^${service}\.service"; then
    systemctl stop "${service}.service" || true
    systemctl disable "${service}.service" || true
    rm -f "/etc/systemd/system/${service}.service"
  fi
}

echo "Removing stack: ${STACK_NAME}"

stop_and_disable "${XRAY_SERVICE_NAME}"
stop_and_disable "${SS_LEGACY_SERVICE_NAME}"
stop_and_disable "${SS2022_SERVICE_NAME}"
stop_and_disable "${SUB_SERVICE_NAME}"

rm -rf "${XRAY_CONFIG_DIR}"
rm -rf "${SS_LEGACY_CONFIG_DIR}"
rm -rf "${SS2022_CONFIG_DIR}"
rm -rf "${WORK_DIR}"
rm -f "${SUB_SERVER_BIN}"

systemctl daemon-reload
systemctl reset-failed || true

if [[ "${REMOVE_BINARIES}" == "1" ]]; then
  rm -f /usr/local/bin/xray
  rm -f /usr/local/bin/ssserver
  rm -f /usr/local/bin/ssservice
fi

echo "Uninstall complete for stack: ${STACK_NAME}"
