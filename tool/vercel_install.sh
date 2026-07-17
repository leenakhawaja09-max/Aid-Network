#!/usr/bin/env bash
# Installs Flutter SDK on Vercel builders (not preinstalled).
set -euo pipefail

FLUTTER_DIR="${FLUTTER_ROOT:-$HOME/flutter}"

if ! command -v flutter >/dev/null 2>&1; then
  echo "Installing Flutter stable to $FLUTTER_DIR ..."
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 "$FLUTTER_DIR"
  export PATH="$FLUTTER_DIR/bin:$PATH"
  flutter config --enable-web --no-analytics
  flutter precache --web
else
  echo "Flutter already available: $(flutter --version | head -n 1)"
fi

flutter pub get
