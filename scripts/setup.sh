#!/usr/bin/env bash
# PingBlock — install all dependencies
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  PingBlock Setup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── Backend deps ──────────────────────────────────────────────────────────────
echo ""
echo "📦  Installing backend dependencies..."
cd "$ROOT/apps/backend"
npm install

# ── Flutter deps ──────────────────────────────────────────────────────────────
echo ""
echo "🦋  Getting Flutter packages..."
cd "$ROOT/apps/frontend"
flutter pub get

echo ""
echo "✅  Setup complete!"
echo ""
echo "To start the dev environment:"
echo "  ./scripts/dev.sh"
