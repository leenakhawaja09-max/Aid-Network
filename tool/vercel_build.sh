#!/usr/bin/env bash
set -euo pipefail

FLUTTER_DIR="${FLUTTER_ROOT:-$HOME/flutter}"
export PATH="$FLUTTER_DIR/bin:${PATH:-}"

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter not on PATH. Run installCommand first."
  exit 1
fi

flutter build web --release --base-href /
echo "Web build output:"
ls -la build/web | head -20
