#!/usr/bin/env bash
# PingBlock dev launcher
# Starts: backend → ADB port forward → flutter run on Seeker
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKEND_PORT=3000
DEVICE_ID="SM02G4061957251"
LOG_DIR="$ROOT/.logs"
mkdir -p "$LOG_DIR"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

divider() { echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }
info()    { echo -e "${GREEN}[+]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
error()   { echo -e "${RED}[✗]${NC} $1"; }

# ── Pre-flight checks ─────────────────────────────────────────────────────────
divider
echo -e "  ${CYAN}PingBlock Dev${NC}"
divider

# Check flutter
if ! command -v flutter &>/dev/null; then
  error "flutter not found in PATH"
  exit 1
fi

# Check node
if ! command -v node &>/dev/null; then
  error "node not found in PATH"
  exit 1
fi

# Check device
if ! adb devices 2>/dev/null | grep -q "$DEVICE_ID"; then
  warn "Seeker ($DEVICE_ID) not detected via ADB."
  warn "Falling back to first available device."
  DEVICE_FLAG=""
else
  DEVICE_FLAG="-d $DEVICE_ID"
fi

# ── Kill any existing backend on that port ────────────────────────────────────
if lsof -ti:$BACKEND_PORT &>/dev/null; then
  warn "Port $BACKEND_PORT already in use — killing old process..."
  lsof -ti:$BACKEND_PORT | xargs kill -9 2>/dev/null || true
  sleep 1
fi

# ── Start backend ─────────────────────────────────────────────────────────────
info "Starting backend on :$BACKEND_PORT  (WAGER_CUSTODY_MODE=onchain)..."
cd "$ROOT/apps/backend"

# Install if node_modules missing
if [ ! -d "node_modules" ]; then
  warn "node_modules not found — running npm install..."
  npm install --silent
fi

WAGER_CUSTODY_MODE=onchain node src/server.js > "$LOG_DIR/backend.log" 2>&1 &
BACKEND_PID=$!
echo $BACKEND_PID > "$LOG_DIR/backend.pid"

# Wait for backend to be ready
info "Waiting for backend..."
for i in {1..15}; do
  if curl -sf "http://localhost:$BACKEND_PORT/health" &>/dev/null; then
    info "Backend ready ✓"
    break
  fi
  if ! kill -0 $BACKEND_PID 2>/dev/null; then
    error "Backend process died. Check $LOG_DIR/backend.log"
    cat "$LOG_DIR/backend.log"
    exit 1
  fi
  sleep 1
done

# ── ADB port reverse ──────────────────────────────────────────────────────────
# Always tunnel port $BACKEND_PORT so the app can reach the backend via
# localhost on the device regardless of which device Flutter picks.
CONNECTED_DEVICES=$(adb devices 2>/dev/null | grep -v "^List" | grep "device$" | awk '{print $1}')
REVERSE_OK=false

if [ -n "$CONNECTED_DEVICES" ]; then
  while IFS= read -r dev; do
    [ -z "$dev" ] && continue
    if adb -s "$dev" reverse tcp:$BACKEND_PORT tcp:$BACKEND_PORT 2>/dev/null; then
      info "ADB reverse OK on $dev  →  device:$BACKEND_PORT tunnels to mac:$BACKEND_PORT ✓"
      REVERSE_OK=true
    else
      warn "ADB reverse failed for $dev"
    fi
  done <<< "$CONNECTED_DEVICES"
fi

if [ "$REVERSE_OK" = false ]; then
  warn "ADB reverse not set on any device."
  warn "Backend URL 'http://localhost:$BACKEND_PORT' may not be reachable from the device."
fi

# ── Flutter run ───────────────────────────────────────────────────────────────
divider
info "Launching Flutter app..."
info "Backend URL → http://localhost:$BACKEND_PORT  (tunnelled via ADB reverse)"
echo ""
cd "$ROOT/apps/frontend"

# Install flutter deps if needed
if [ ! -d ".dart_tool" ]; then
  info "Running flutter pub get..."
  flutter pub get
fi

# Run — this stays in foreground so Ctrl+C kills everything
cleanup() {
  echo ""
  warn "Shutting down..."
  kill $BACKEND_PID 2>/dev/null || true
  # Remove reverse tunnels from all connected devices
  if [ -n "$CONNECTED_DEVICES" ]; then
    while IFS= read -r dev; do
      [ -z "$dev" ] && continue
      adb -s "$dev" reverse --remove tcp:$BACKEND_PORT 2>/dev/null || true
    done <<< "$CONNECTED_DEVICES"
  fi
  info "Done."
}
trap cleanup EXIT INT TERM

flutter run $DEVICE_FLAG \
  --dart-define=BACKEND_URL=http://localhost:$BACKEND_PORT
