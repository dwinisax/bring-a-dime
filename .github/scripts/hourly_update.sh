#!/usr/bin/env bash
set -euo pipefail

TS="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
RAND="$(openssl rand -hex 4)"

EMOJIS=("✨" "🔥" "🌿" "⚡" "🌙" "🧠" "🛠️" "📌" "🎲" "🚀" "💡" "🧩" "🍀" "🎯" "🕰️")
pick_emoji() { printf "%s" "${EMOJIS[$(( RANDOM % ${#EMOJIS[@]} ))]}"; }

EMOJI_README="$(pick_emoji)"
EMOJI_TUGAS="$(pick_emoji)"

# -------------------------
# Cache & files
# -------------------------
CACHE_DIR=".cache"
QUOTES_CACHE="$CACHE_DIR/quotes_cache.txt"        # master list (unik)
QUOTES_DAY="$CACHE_DIR/quotes_day.txt"            # YYYY-MM-DD (UTC) terakhir refresh
QUOTES_QUEUE="$CACHE_DIR/quotes_queue.txt"        # shuffled queue (dipakai 1-1)
README_LOG="$CACHE_DIR/readme_log.txt"            # last 5 entries

mkdir -p "$CACHE_DIR"
[ -f "$QUOTES_CACHE" ] || > "$QUOTES_CACHE"
[ -f "$QUOTES_DAY" ]   || echo "" > "$QUOTES_DAY"
[ -f "$QUOTES_QUEUE" ] || > "$QUOTES_QUEUE"
[ -f "$README_LOG" ]   || > "$README_LOG"

TODAY_UTC="$(date -u '+%Y-%m-%d')"
LAST_DAY="$(cat "$QUOTES_DAY" 2>/dev/null || echo "")"

# -------------------------
# Quote fetchers
# -------------------------
fetch_zenquotes() {
  # ZenQuotes JSON: [ {"q":"...","a":"...","h":"..."} ]
  # NOTE: rate limit default 5/30s/IP => nanti kita throttle pas daily refresh :contentReference[oaicite:3]{index=3}
  local resp
  resp="$(curl -fsSL --retry 1 --retry-delay 1 --max-time 8 \
    "https://zenquotes.io/api/random" || true)"

  echo "$resp" | jq -r '.[0] | "\(.q // "") — \(.a // "Unknown")"' 2>/dev/null \
    | sed 's/[[:space:]]\+$//' \
    | grep -v '^ — ' \
    || true
}

fetch_quotable_insecure() {
  # Quotable cert reportedly expired :contentReference[oaicite:4]{index=4}
  # User request: ignore SSL for fallback => -k/--insecure
  local resp
  resp="$(curl -kfsSL --retry 1 --retry-delay 1 --max-time 8 \
    "https://api.quotable.io/random" || true)"

  # JSON: { "content": "...", "author": "..." }
  echo "$resp" | jq -r '"\(.content // "") — \(.author // "Unknown")"' 2>/dev/null \
    | sed 's/[[:space:]]\+$//' \
    | grep -v '^ — ' \
    || true
}

dedupe_cache() {
  # buang blank + dedupe preserve order
  sed '/^[[:space:]]*$/d' "$QUOTES_CACHE" | awk '!seen[$0]++' > "$QUOTES_CACHE.tmp"
  mv "$QUOTES_CACHE.tmp" "$QUOTES_CACHE"
}

rebuild_queue() {
  if [ -s "$QUOTES_CACHE" ]; then
    shuf "$QUOTES_CACHE" > "$QUOTES_QUEUE" || true
  else
    > "$QUOTES_QUEUE"
  fi
}

# -------------------------
# Daily refresh (ONLY if day changed)
# -------------------------
if [ "$LAST_DAY" != "$TODAY_UTC" ]; then
  echo "New UTC day detected: $LAST_DAY -> $TODAY_UTC. Refreshing quote cache..."

  # target quotes per day (bisa kamu naikkan)
  # ZenQuotes aman kalau 5 request dengan jeda 7 detik (hindari 429) :contentReference[oaicite:6]{index=6}
  ZEN_N=5
  QUOTABLE_N=5

  tmp="$CACHE_DIR/new_quotes.tmp"
  > "$tmp"

  # 1) ZenQuotes (throttled)
  for _ in $(seq 1 "$ZEN_N"); do
    q="$(fetch_zenquotes || true)"
    [ -n "$q" ] && echo "$q" >> "$tmp"
    sleep 7
  done

  # 2) Fallback: Quotable insecure (no sleep needed)
  for _ in $(seq 1 "$QUOTABLE_N"); do
    q="$(fetch_quotable_insecure || true)"
    [ -n "$q" ] && echo "$q" >> "$tmp"
  done

  # Merge into cache if we got anything
  if [ -s "$tmp" ]; then
    cat "$QUOTES_CACHE" "$tmp" >> "$QUOTES_CACHE.merged"
    mv "$QUOTES_CACHE.merged" "$QUOTES_CACHE"
    dedupe_cache
  else
    echo "WARN: daily refresh fetched nothing. Keeping existing cache."
  fi

  rm -f "$tmp" || true

  # Mark day + rebuild queue (fresh order)
  echo "$TODAY_UTC" > "$QUOTES_DAY"
  rebuild_queue
else
  # Same day: DO NOT refresh (per request)
  :
fi

# If queue empty (e.g., first run), build it
if [ ! -s "$QUOTES_QUEUE" ]; then
  rebuild_queue
fi

# Pop one quote from queue
QUOTE_LINE="Keep going. — Unknown"
if [ -s "$QUOTES_QUEUE" ]; then
  QUOTE_LINE="$(head -n 1 "$QUOTES_QUEUE")"
  tail -n +2 "$QUOTES_QUEUE" > "$QUOTES_QUEUE.tmp" && mv "$QUOTES_QUEUE.tmp" "$QUOTES_QUEUE"
elif [ -s "$QUOTES_CACHE" ]; then
  QUOTE_LINE="$(shuf -n 1 "$QUOTES_CACHE")"
fi

# -------------------------
# README: replace each run, keep last 5 entries
# -------------------------
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

# -------------------------
# tugas.txt: append
# -------------------------
if [ ! -f tugas.txt ]; then
  echo "tugas:" > tugas.txt
fi
echo "$EMOJI_TUGAS $TS | tugas-random-$RAND | \"$QUOTE_LINE\"" >> tugas.txt
