#!/usr/bin/env bash
set -euo pipefail

TS="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
RAND="$(openssl rand -hex 4)"

EMOJIS=("✨" "🔥" "🌿" "⚡" "🌙" "🧠" "🛠️" "📌" "🎲" "🚀" "💡" "🧩" "🍀" "🎯" "🕰️")
pick_emoji() { printf "%s" "${EMOJIS[$(( RANDOM % ${#EMOJIS[@]} ))]}"; }

CACHE_DIR=".cache"
QUOTES_CACHE="$CACHE_DIR/quotes_cache.txt"
QUOTES_META="$CACHE_DIR/quotes_cache_meta.txt"
README_LOG="$CACHE_DIR/readme_log.txt"
TTL_SECONDS=$(( 24 * 60 * 60 ))  # refresh quotes 1x/24 jam

mkdir -p "$CACHE_DIR"
[ -f "$QUOTES_CACHE" ] || > "$QUOTES_CACHE"
[ -f "$QUOTES_META" ]  || echo "0" > "$QUOTES_META"
[ -f "$README_LOG" ]   || > "$README_LOG"

now_epoch="$(date -u +%s)"
last_epoch="$(cat "$QUOTES_META" 2>/dev/null || echo 0)"

need_refresh=1
if [ -s "$QUOTES_CACHE" ] && [ $(( now_epoch - last_epoch )) -lt "$TTL_SECONDS" ]; then
  need_refresh=0
fi

fetch_zenquotes() {
  local resp
  resp="$(curl -fsSL --retry 1 --retry-delay 1 --max-time 8 \
    "https://zenquotes.io/api/random" || true)"

  echo "$resp" | jq -r '.[0] | "\(.q // "Keep going.") — \(.a // "Unknown")"' 2>/dev/null \
    || echo "Keep going. — Unknown"
}

if [ "$need_refresh" -eq 1 ]; then
  echo "Refreshing quote cache..."
  tmp="$QUOTES_CACHE.tmp"
  > "$tmp"

  for _ in $(seq 1 10); do
    line="$(fetch_zenquotes)"
    [ -n "$line" ] && echo "$line" >> "$tmp"
  done

  if [ -s "$tmp" ]; then
    mv "$tmp" "$QUOTES_CACHE"
    echo "$now_epoch" > "$QUOTES_META"
  else
    echo "WARN: quote cache refresh failed; keep existing cache."
    rm -f "$tmp" || true
  fi
else
  echo "Using cached quotes."
fi

QUOTE_LINE="Keep going. — Unknown"
if [ -s "$QUOTES_CACHE" ]; then
  QUOTE_LINE="$(shuf -n 1 "$QUOTES_CACHE")"
fi

EMOJI_README="$(pick_emoji)"
EMOJI_TUGAS="$(pick_emoji)"

# --- README replace, keep last 5 entries ---
ENTRY_FILE="$CACHE_DIR/_entry.tmp"
cat > "$ENTRY_FILE" <<EOF
$EMOJI_README $TS — $RAND
"$QUOTE_LINE"

EOF

cat "$ENTRY_FILE" >> "$README_LOG"

awk '
  BEGIN{RS=""; ORS="\n\n"}
  {blocks[++n]=$0}
  END{
    start=(n>5)? n-5+1 : 1
    for(i=start;i<=n;i++) print blocks[i]
  }
' "$README_LOG" > "$README_LOG.tmp" && mv "$README_LOG.tmp" "$README_LOG"

cat > README.md <<EOF
# Auto Update Repo

Repo ini auto update tiap 1 jam via GitHub Actions.

Log

$(cat "$README_LOG")
EOF

rm -f "$ENTRY_FILE" || true

# --- tugas.txt append ---
if [ ! -f tugas.txt ]; then
  echo "tugas:" > tugas.txt
fi
echo "$EMOJI_TUGAS $TS | tugas-random-$RAND | \"$QUOTE_LINE\"" >> tugas.txt
