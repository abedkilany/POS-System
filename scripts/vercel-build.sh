#!/usr/bin/env bash
set -euo pipefail

FLUTTER_DIR="$PWD/.flutter"

if command -v flutter >/dev/null 2>&1; then
  echo "Flutter SDK found in PATH."
else
  if [ -x "$FLUTTER_DIR/bin/flutter" ]; then
    echo "Using cached Flutter SDK from .flutter."
  else
    echo "Flutter SDK not found. Installing stable Flutter for Vercel build..."
    rm -rf "$FLUTTER_DIR"
    git clone --depth 1 --branch stable https://github.com/flutter/flutter.git "$FLUTTER_DIR"
  fi

  export PATH="$FLUTTER_DIR/bin:$PATH"
fi

flutter --version
flutter config --enable-web
flutter pub get
flutter build web --release