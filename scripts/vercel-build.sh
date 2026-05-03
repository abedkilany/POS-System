#!/usr/bin/env bash
set -euo pipefail

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter SDK not found. Installing stable Flutter for Vercel build..."
  git clone --depth 1 --branch stable https://github.com/flutter/flutter.git "$PWD/.flutter"
  export PATH="$PWD/.flutter/bin:$PATH"
fi

flutter --version
flutter config --enable-web
flutter pub get
flutter build web --release
