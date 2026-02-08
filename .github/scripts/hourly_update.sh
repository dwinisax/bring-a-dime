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
  local resp
  resp="$(curl -fsSL --retry 1 --retry-delay 1 --max-time 8 \
    "https://zenquotes.io/api/random" || true)"

  echo "$resp" | jq -r '.[0] | "\(.q // "") — \(.a // "Unknown")"' 2>/dev/null \
    | sed 's/[[:space:]]\+$//' \
    | grep -v '^ — ' \
    || true
}

fetch_quotable_insecure() {
  local resp
  resp="$(curl -kfsSL --retry 1 --retry-delay 1 --max-time 8 \
    "https://api.quotable.io/random" || true)"

  echo "$resp" | jq -r '"\(.content // "") — \(.author // "Unknown")"' 2>/dev/null \
    | sed 's/[[:space:]]\+$//' \
    | grep -v '^ — ' \
    || true
}

dedupe_cache() {
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

  ZEN_N=5
  QUOTABLE_N=5

  tmp="$CACHE_DIR/new_quotes.tmp"
  > "$tmp"

  for _ in $(seq 1 "$ZEN_N"); do
    q="$(fetch_zenquotes || true)"
    [ -n "$q" ] && echo "$q" >> "$tmp"
    sleep 7
  done

  for _ in $(seq 1 "$QUOTABLE_N"); do
    q="$(fetch_quotable_insecure || true)"
    [ -n "$q" ] && echo "$q" >> "$tmp"
  done

  if [ -s "$tmp" ]; then
    cat "$QUOTES_CACHE" "$tmp" >> "$QUOTES_CACHE.merged"
    mv "$QUOTES_CACHE.merged" "$QUOTES_CACHE"
    dedupe_cache
  else
    echo "WARN: daily refresh fetched nothing. Keeping existing cache."
  fi

  rm -f "$tmp" || true
  echo "$TODAY_UTC" > "$QUOTES_DAY"
  rebuild_queue
else
  # Same day: DO NOT refresh (per request)
  :
fi

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
# README & Log (BAGIAN YANG DI-IMPROVE)
# -------------------------
ENTRY_FILE="$CACHE_DIR/_entry.tmp"
# Format entry: Emoji Waktu | ID | Quote
cat > "$ENTRY_FILE" <<EOF
$EMOJI_README $TS | $RAND | "$QUOTE_LINE"

EOF

cat "$ENTRY_FILE" >> "$README_LOG"

# OPSI 1: Log Rolling hemat memori
tac "$README_LOG" | awk 'BEGIN{RS=""; ORS="\n\n"} NR<=5' | tac > "$README_LOG.tmp"
mv "$README_LOG.tmp" "$README_LOG"

# OPSI 2: Visual Tabel untuk README
LOG_TABLE_ROWS=$(awk 'BEGIN{RS=""; ORS="\n"} {
  p1 = index($0, " | ")
  if (p1 > 0) {
    col1 = substr($0, 1, p1 - 1)
    temp = substr($0, p1 + 3)
    p2 = index(temp, " | ")
    if (p2 > 0) {
      col2 = substr(temp, 1, p2 - 1)
      col3 = substr(temp, p2 + 3)
      gsub(/\n+$/, "", col3)
      printf "| %s | `%s` | %s |\n", col1, col2, col3
    }
  }
}' "$README_LOG")

cat > README.md <<EOF
# Auto Update Repo

Repo ini auto update tiap 1 jam via GitHub Actions.

### 🕒 Log Aktivitas (5 Terakhir)
| Waktu (UTC) | ID Sesi | Pesan / Kutipan |
| :--- | :--- | :--- |
$LOG_TABLE_ROWS

---
*Terakhir dijalankan: $TS*
EOF

rm -f "$ENTRY_FILE" || true

# -------------------------
# tugas.txt: append
# -------------------------
if [ ! -f tugas.txt ]; then
  echo "tugas:" > tugas.txt
fi
echo "$EMOJI_TUGAS $TS | tugas-random-$RAND | \"$QUOTE_LINE\"" >> tugas.txt
