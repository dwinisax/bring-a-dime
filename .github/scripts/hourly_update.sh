#!/usr/bin/env bash
set -euo pipefail

TS="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
RAND="$(openssl rand -hex 4)"

EMOJIS=("✨" "🔥" "🌿" "⚡" "🌙" "🧠" "🛠️" "📌" "🎲" "🚀" "💡" "🧩" "🍀" "🎯" "🕰️")
pick_emoji() { printf "%s" "${EMOJIS[$(( RANDOM % ${#EMOJIS[@]} ))]}"; }

EMOJI_README="$(pick_emoji)"
EMOJI_TUGAS="$(pick_emoji)"

# -------------------------
# Quotes cache: refresh per hari (UTC) + no-repeat queue
# -------------------------
CACHE_DIR=".cache"
QUOTES_CACHE="$CACHE_DIR/quotes_cache.txt"        # master quotes (unik)
QUOTES_DAY="$CACHE_DIR/quotes_cache_day.txt"      # YYYY-MM-DD (UTC)
QUOTES_QUEUE="$CACHE_DIR/quotes_queue.txt"        # shuffled list dipakai 1-1
TODAY_UTC="$(date -u '+%Y-%m-%d')"

mkdir -p "$CACHE_DIR"
[ -f "$QUOTES_CACHE" ] || > "$QUOTES_CACHE"
[ -f "$QUOTES_DAY" ]   || echo "" > "$QUOTES_DAY"
[ -f "$QUOTES_QUEUE" ] || > "$QUOTES_QUEUE"

fetch_zenquotes() {
  local resp
  resp="$(curl -fsSL --retry 1 --retry-delay 1 --max-time 6 \
    "https://zenquotes.io/api/random" || true)"

  # ZenQuotes: [ {"q":"...","a":"...","h":"..."} ]
  # jq parse -> "quote — author", fallback blank (biar caller decide)
  echo "$resp" | jq -r '.[0] | "\(.q // "") — \(.a // "Unknown")"' 2>/dev/null \
    | sed 's/[[:space:]]\+$//' \
    | grep -v '^ — ' \
    || true
}

LAST_DAY="$(cat "$QUOTES_DAY" 2>/dev/null || echo "")"
MIN_CACHE_LINES=30
CUR_LINES="$(wc -l < "$QUOTES_CACHE" 2>/dev/null || echo 0)"

if [ "$LAST_DAY" != "$TODAY_UTC" ] || [ "$CUR_LINES" -lt "$MIN_CACHE_LINES" ]; then
  echo "Refreshing daily quote cache for $TODAY_UTC..."
  tmp="$QUOTES_CACHE.tmp"
  > "$tmp"

  # ambil 40 quotes (cukup buat variasi 1 hari)
  for _ in $(seq 1 40); do
    line="$(fetch_zenquotes || true)"
    [ -n "$line" ] && echo "$line" >> "$tmp"
  done

  if [ -s "$tmp" ]; then
    # gabung cache lama + baru, hapus kosong, unikkan
    cat "$QUOTES_CACHE" "$tmp" \
      | sed '/^[[:space:]]*$/d' \
      | awk '!seen[$0]++' > "$QUOTES_CACHE.new"
    mv "$QUOTES_CACHE.new" "$QUOTES_CACHE"
    echo "$TODAY_UTC" > "$QUOTES_DAY"
  else
    echo "WARN: failed to fetch new quotes; keeping existing cache."
  fi

  rm -f "$tmp" || true

  # rebuild queue: shuffle master cache
  if [ -s "$QUOTES_CACHE" ]; then
    shuf "$QUOTES_CACHE" > "$QUOTES_QUEUE" || true
  fi
fi

# kalau queue kosong, rebuild
if [ ! -s "$QUOTES_QUEUE" ] && [ -s "$QUOTES_CACHE" ]; then
  shuf "$QUOTES_CACHE" > "$QUOTES_QUEUE" || true
fi

# pop 1 quote dari queue
QUOTE_LINE="Keep going. — Unknown"
if [ -s "$QUOTES_QUEUE" ]; then
  QUOTE_LINE="$(head -n 1 "$QUOTES_QUEUE")"
  tail -n +2 "$QUOTES_QUEUE" > "$QUOTES_QUEUE.tmp" && mv "$QUOTES_QUEUE.tmp" "$QUOTES_QUEUE"
elif [ -s "$QUOTES_CACHE" ]; then
  QUOTE_LINE="$(shuf -n 1 "$QUOTES_CACHE")"
fi

# -------------------------
# README: replace tiap run, log tahan 5 entry
# -------------------------
README_LOG="$CACHE_DIR/readme_log.txt"
[ -f "$README_LOG" ] || > "$README_LOG"

ENTRY_FILE="$CACHE_DIR/_entry.tmp"
cat > "$ENTRY_FILE" <<EOF
$EMOJI_README $TS — $RAND
"$QUOTE_LINE"

EOF

cat "$ENTRY_FILE" >> "$README_LOG"

# keep last 5 blocks (block dipisah blank line)
awk '
  BEGIN{RS=""; ORS="\n\n"}
  {blocks[++n]=$0}
  END{
    start=(n>5)? n-5+1 : 1
    for(i=start;i<=n;i++) print blocks[i]
  }
' "$README_LOG" > "$README_LOG.tmp" && mv "$README_LOG.tmp" "$README_LOG"

# render README (overwrite)
cat > README.md <<EOF
# Auto Update Repo

Repo ini auto update tiap 1 jam via GitHub Actions.

Log

$(cat "$README_LOG")
EOF

rm -f "$ENTRY_FILE" || true

# -------------------------
# tugas.txt: append terus
# -------------------------
if [ ! -f tugas.txt ]; then
  echo "tugas:" > tugas.txt
fi
echo "$EMOJI_TUGAS $TS | tugas-random-$RAND | \"$QUOTE_LINE\"" >> tugas.txt
