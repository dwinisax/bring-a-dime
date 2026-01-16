#!/usr/bin/env bash
set -euo pipefail

TS="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
RAND="$(openssl rand -hex 4)"

EMOJIS=("✨" "🔥" "🌿" "⚡" "🌙" "🧠" "🛠️" "📌" "🎲" "🚀" "💡" "🧩" "🍀" "🎯" "🕰️")
pick_emoji() { printf "%s" "${EMOJIS[$(( RANDOM % ${#EMOJIS[@]} ))]}"; }

CACHE_DIR=".cache"
CACHE_FILE="$CACHE_DIR/quotes_cache.txt"      # 1 quote per line: "text — author"
META_FILE="$CACHE_DIR/quotes_cache_meta.txt"  # epoch timestamp
TTL_SECONDS=$(( 24 * 60 * 60 ))               # refresh 1x/24 jam

mkdir -p "$CACHE_DIR"
[ -f "$CACHE_FILE" ] || > "$CACHE_FILE"
[ -f "$META_FILE" ]  || echo "0" > "$META_FILE"

now_epoch="$(date -u +%s)"
last_epoch="$(cat "$META_FILE" 2>/dev/null || echo 0)"

need_refresh=1
if [ -s "$CACHE_FILE" ] && [ $(( now_epoch - last_epoch )) -lt "$TTL_SECONDS" ]; then
  need_refresh=0
fi

fetch_zenquotes() {
  curl -fsSL --retry 3 --retry-delay 2 --max-time 20 \
    "https://zenquotes.io/api/random" \
  | python3 - <<'PY'
import json,sys
data=json.load(sys.stdin)[0]
q=(data.get("q","")).strip()
a=(data.get("a","Unknown")).strip()
print(f"{q} — {a}")
PY
}

fetch_quotable() {
  # Quotable sering error SSL (cert expired). Ini cuma "try".
  curl -fsSL --retry 2 --retry-delay 2 --max-time 15 \
    "https://api.quotable.io/random" \
  | python3 - <<'PY'
import json,sys
d=json.load(sys.stdin)
print(f"{d.get('content','').strip()} — {d.get('author','Unknown').strip()}")
PY
}

if [ "$need_refresh" -eq 1 ]; then
  echo "Refreshing quote cache..."
  tmp="$CACHE_FILE.tmp"
  > "$tmp"

  for _ in $(seq 1 50); do
    line=""
    if line="$(fetch_quotable 2>/dev/null)"; then true; else line=""; fi
    if [ -z "$line" ]; then
      if line="$(fetch_zenquotes 2>/dev/null)"; then true; else line=""; fi
    fi
    [ -n "$line" ] && echo "$line" >> "$tmp"
  done

  if [ -s "$tmp" ]; then
    mv "$tmp" "$CACHE_FILE"
    echo "$now_epoch" > "$META_FILE"
  else
    echo "WARN: cache refresh failed; keep existing cache."
    rm -f "$tmp" || true
  fi
else
  echo "Using cached quotes."
fi

QUOTE_LINE="Keep going. — Unknown"
if [ -s "$CACHE_FILE" ]; then
  QUOTE_LINE="$(shuf -n 1 "$CACHE_FILE")"
fi

EMOJI_README="$(pick_emoji)"
EMOJI_TUGAS="$(pick_emoji)"

if [ ! -f README.md ]; then
  cat > README.md <<'EOF'
# Auto Update Repo

Repo ini auto update tiap 1 jam via GitHub Actions.
EOF
fi

{
  echo ""
  echo "## Log"
  echo "- $EMOJI_README **$TS** — \`$RAND\`"
  echo "  > \"${QUOTE_LINE}\""
} >> README.md

if [ ! -f tugas.txt ]; then
  echo "tugas:" > tugas.txt
fi
echo "$EMOJI_TUGAS $TS | tugas-random-$RAND | \"${QUOTE_LINE}\"" >> tugas.txt
