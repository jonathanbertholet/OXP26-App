#!/bin/bash
# Apply listing metadata after the App Store Connect app record exists.
# Usage: scripts/asc-after-listing.sh APP_ID
set -euo pipefail

APP_ID="${1:?app id required}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "Setting app info, category, age rating, and content rights…"
asc app-setup info set \
  --app "$APP_ID" \
  --primary-locale "en-US" \
  --locale "en-US" \
  --name "OXP – Odoo Experience" \
  --subtitle "Unofficial conference guide" \
  --privacy-policy-url "https://oxp-site.jonathanbertholet.workers.dev/privacy/" \
  --content-rights "DOES_NOT_USE_THIRD_PARTY_CONTENT"

asc app-setup categories set --app "$APP_ID" --primary BUSINESS --secondary PRODUCTIVITY
asc age-rating edit --app "$APP_ID" --all-none
asc apps content-rights edit --app "$APP_ID" --uses-third-party-content=false

echo "Pushing version metadata…"
asc metadata push --app "$APP_ID" --version "1.0" --dir "./metadata"

VERSION_ID="$(asc versions list --app "$APP_ID" --output json | python3 -c '
import json,sys
rows=json.load(sys.stdin).get("data",[])
for r in rows:
    a=r.get("attributes",{})
    if a.get("versionString") in ("1.0","1.0.0"):
        print(r["id"]); break
')"
if [[ -z "${VERSION_ID}" ]]; then
  echo "No 1.0 version yet; creating one"
  asc versions create --app "$APP_ID" --version "1.0" --platform IOS --copyright "2026 Jonathan Bertholet"
  VERSION_ID="$(asc versions list --app "$APP_ID" --output json | python3 -c '
import json,sys
rows=json.load(sys.stdin).get("data",[])
for r in rows:
    if r.get("attributes",{}).get("versionString") in ("1.0","1.0.0"):
        print(r["id"]); break
')"
else
  asc versions update --version-id "$VERSION_ID" --copyright "2026 Jonathan Bertholet"
fi

echo "Review details…"
if ! asc review details-for-version --version-id "$VERSION_ID" --output json >/dev/null 2>&1; then
  asc review details-create \
    --version-id "$VERSION_ID" \
    --contact-first-name "jonathan" \
    --contact-last-name "bertholet" \
    --contact-email "jonathanbertholet@gmail.com" \
    --contact-phone "+32486263519" \
    --notes "OXP is an unofficial companion for Odoo Experience 2026. No account or login. The agenda is bundled. Use Today → Preview to jump to 24 Sep 2026 11:40 if reviewing before the event. Privacy Policy is in Saved (toolbar) and Today → Preview → About."
fi

if [[ -d "./screenshots/store/iphone" ]]; then
  echo "Uploading iPhone screenshots…"
  asc screenshots upload --app "$APP_ID" --version "1.0" --path "./screenshots/store/iphone" --device-type "IPHONE_65"
fi
if [[ -d "./screenshots/store/ipad" ]]; then
  echo "Uploading iPad screenshots…"
  asc screenshots upload --app "$APP_ID" --version "1.0" --path "./screenshots/store/ipad" --device-type "IPAD_PRO_3GEN_129"
fi

echo "Done. Next: bootstrap availability (needs a web session), then archive + publish."
echo "  asc pricing availability view --app $APP_ID"
echo "  asc publish appstore --app $APP_ID --project ./OXP.xcodeproj --scheme OXP --version 1.0 --export-options ./ExportOptions.plist --wait --submit --confirm"
