#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${VERTEX_BRIDGE_REPO:-https://github.com/marifcelik/vertex-bridge.git}"
INSTALL_BIN="${INSTALL_BIN:-$HOME/.local/bin/vertex-bridge}"
LISTEN="${VERTEX_LISTEN:-127.0.0.1:8788}"
LOCATION="${VERTEX_LOCATION:-global}"
PROJECT="${VERTEX_PROJECT:-}"
SETUP_SYSTEMD="${SETUP_SYSTEMD:-auto}"

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  --project <id-or-number>   GCP project ID or project number (or set VERTEX_PROJECT)
  --location <region>        Vertex AI location (default: global)
  --listen <addr:port>       Local listen address (default: 127.0.0.1:8788)
  --bin <path>               Output binary path (default: ~/.local/bin/vertex-bridge)
  --no-systemd               Skip systemd user service setup
  -h, --help                 Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT="$2"; shift 2 ;;
    --location) LOCATION="$2"; shift 2 ;;
    --listen) LISTEN="$2"; shift 2 ;;
    --bin) INSTALL_BIN="$2"; shift 2 ;;
    --no-systemd) SETUP_SYSTEMD="no"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

if ! command -v go >/dev/null 2>&1; then
  echo "Error: Go is required to build vertex-bridge (https://go.dev/dl/)." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR"
TMP_DIR=""

cleanup() {
  if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

if [[ ! -f "$BUILD_DIR/main.go" ]]; then
  if ! command -v git >/dev/null 2>&1; then
    echo "Error: git is required when running install.sh outside the repository." >&2
    exit 1
  fi
  TMP_DIR="$(mktemp -d)"
  echo "Cloning $REPO_URL..."
  git clone --depth 1 "$REPO_URL" "$TMP_DIR/vertex-bridge"
  BUILD_DIR="$TMP_DIR/vertex-bridge"
fi

mkdir -p "$(dirname "$INSTALL_BIN")"
echo "Building vertex-bridge -> $INSTALL_BIN"
(cd "$BUILD_DIR" && go build -o "$INSTALL_BIN" .)
chmod +x "$INSTALL_BIN"

if [[ -z "$PROJECT" && -t 0 ]]; then
  read -r -p "GCP Project ID or Number (leave empty to skip systemd setup): " PROJECT
fi

if [[ "$SETUP_SYSTEMD" != "no" && -n "$PROJECT" ]] && command -v systemctl >/dev/null 2>&1; then
  SERVICE_DIR="$HOME/.config/systemd/user"
  SERVICE_FILE="$SERVICE_DIR/vertex-bridge.service"
  mkdir -p "$SERVICE_DIR"
  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=vertex-bridge: Native Gemini API to Vertex AI proxy
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$INSTALL_BIN -listen $LISTEN -project $PROJECT -location $LOCATION
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
EOF

  systemctl --user daemon-reload
  systemctl --user enable --now vertex-bridge.service
  echo ""
  echo "systemd user service installed and started: $SERVICE_FILE"
  systemctl --user status vertex-bridge.service --no-pager || true
else
  echo ""
  echo "Installed binary to: $INSTALL_BIN"
  echo "Run manually with:"
  echo "  $INSTALL_BIN -listen $LISTEN -project <YOUR_GCP_PROJECT> -location $LOCATION"
fi

echo ""
echo "Done! Point your native Gemini client base_url to: http://$LISTEN"
