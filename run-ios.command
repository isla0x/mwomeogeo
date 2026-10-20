#!/bin/zsh
set -e
project_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
cd "$project_dir"
if ! command -v flutter >/dev/null 2>&1; then
  export PATH="/opt/homebrew/bin:$PATH"
fi
flutter pub get
open -a Simulator
exec flutter run "$@"
