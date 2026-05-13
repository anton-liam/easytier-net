#!/usr/bin/env sh
set -eu

missing=""

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    missing="$missing $1"
  fi
}

need git
need make

if [ -n "$missing" ]; then
  echo "Missing required tools:$missing" >&2
  exit 1
fi

echo "Base tools are available."

if command -v docker >/dev/null 2>&1; then
  echo "Docker: $(docker --version)"
else
  echo "Docker not found. Required for containerlab tests."
fi

if command -v containerlab >/dev/null 2>&1; then
  echo "containerlab: $(containerlab version 2>/dev/null | head -n 1)"
else
  echo "containerlab not found. Install it inside the Linux lab VM for make lab-up."
fi

if command -v rustc >/dev/null 2>&1; then
  echo "Rust: $(rustc --version)"
else
  echo "Rust not found. Required for EasyTier/agent builds."
fi

