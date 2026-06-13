#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/Mangox.xcodeproj"
SCHEME="Mangox"

SIM_ID="${SIMULATOR_ID:-}"
if [[ -z "$SIM_ID" ]]; then
  SIM_ID="$(xcrun simctl list devices available -j | python3 -c "
import json, sys
data = json.load(sys.stdin)
for runtime, devices in sorted(data.get('devices', {}).items(), reverse=True):
    if 'iOS' not in runtime:
        continue
    for d in devices:
        if d.get('isAvailable') and not d.get('isUnavailable'):
            print(d['udid'])
            raise SystemExit
print('', end='')
")"
fi

if [[ -z "$SIM_ID" ]]; then
  echo "No available iOS simulator found. Set SIMULATOR_ID or boot a simulator." >&2
  exit 1
fi

echo "Running Foundation Models coach eval tests on simulator $SIM_ID"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "id=$SIM_ID" \
  test \
  -only-testing:MangoxTests/FoundationModelsCoachEvaluationTests \
  -only-testing:MangoxTests/OnDeviceCoachRoutingTests \
  -only-testing:MangoxTests/CoachChatImprovementsTests

if command -v fm >/dev/null 2>&1; then
  FIXTURES="$ROOT/backend/scripts/coach-eval-fixtures.json"
  if [[ -f "$FIXTURES" ]]; then
    echo "fm CLI found — run manual prompt evals against $FIXTURES when Foundation Models utilities package is configured."
  fi
else
  echo "Optional: install Apple's fm CLI + Foundation Models utilities SPM package for cross-release prompt regression."
fi
