#!/usr/bin/env bash
# Run Ollama so your iPhone (same Wi‑Fi) can use it from Mangox → OpenAI-compatible.
#
# 1. Quit the Ollama menu bar app if it’s running (otherwise port 11434 may be taken).
# 2. chmod +x scripts/ollama-lan.sh && ./scripts/ollama-lan.sh
# 3. In Mangox Settings → Coach: OpenAI-compatible, Base URL http://YOUR_MAC_IP:11434
#
# Your Mac’s Wi‑Fi IP (often en0):
#   ipconfig getifaddr en0

set -euo pipefail
export OLLAMA_HOST="${OLLAMA_HOST:-0.0.0.0:11434}"
echo "Ollama listening on ${OLLAMA_HOST} (all interfaces — reachable from LAN)"
echo "Pick a model name from: ollama list   (e.g. minimax-m2.7:cloud, gemma4:latest)"
exec ollama serve
