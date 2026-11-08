#!/bin/bash
set +m
set -uo pipefail

# ═══════════════════════════════════════════════════════════════
#  Respect Broadcast — V15 (BULLETPROOF - No Segfault / H.265 Fix)
# ═══════════════════════════════════════════════════════════════

STREAMERS_LIST="${STREAMERS_LIST:-drb7h,S5B,ABO8ALYY,ID7O,F1AISAL,xmusabrt,TAF86,abo_khrbaa,Peerless,Seagull,iMonkey_D,FHLWY,Hook,okb8,wolf,NASSER,Aymnalsatam,BoQamar,NEFOXD,RAYN,xya7ya,W1pey,ALRND,klash,Sayko_911,ZAiKRx}"
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

WORKDIR="/tmp/standby_respect"
FIFO="/tmp/relay.ts"
KEEPER_READY="/tmp/relay_keeper.ready"

IFS=',' read -r -a STREAMERS <<< "$STREAMERS_LIST"
export STREAMERS_LIST UA WORKDIR

if ! command -v yt-dlp &> /dev/null; then
    pip3 install --user --break-system-packages --quiet yt-dlp
    export PATH="$HOME/.local/bin:$PATH"
fi

generate_standby() {
    echo "🎨 Generating standby screen..."
    mkdir -p ~/.fonts
    [ ! -s ~/.fonts/Cairo-var.ttf ] && curl -sL --max-time 30 \
        "https://raw.githubusercontent.com/google/fonts/main/ofl/cairo/Cairo%5Bslnt%2Cwght%5D.ttf" \
        -o ~/.fonts/Cairo-var.ttf || true
    [ ! -s ~/.fonts/Orbitron-var.ttf ] && curl -sL --max-time 30 \
        "https://raw.githubusercontent.com/google/fonts/main/ofl/orbitron/Orbitron%5Bwght%5D.ttf" \
        -o ~/.fonts/Orbitron-var.ttf || true
    fc-cache -f >/dev/null 2>&1 || true

    mkdir -p "$WORKDIR"

    cat > /tmp/make_ui.py <<'PYEOF'
import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 1920, 1080
WORKDIR = os.environ.get("WORKDIR", "/tmp/standby_respect")
STREAMERS = [s.strip() for s in os.environ.get("STREAMERS_LIST", "").split(',') if s.strip()]

def font(path, size, weight=700):
    try:
        f = ImageFont.truetype(path, size)
        axes = f.get_variation_axes()
        if len(axes) == 1:
            f.set_variation_by_axes([weight])
        elif len(axes) == 2:
            f.set_variation_by_axes([0, weight])
        return f
    except Exception:
        return ImageFont.load_default()

bg = Image.new("RGB", (W, H), (10, 2, 20))
d = ImageDraw.Draw(bg)
for y in range(H):
    t = y / H
    d.line([(0, y), (W, y)], fill=(int(10+20*t), int(2+8*t), int(20+30*t)))

grid = Image.new("RGBA", (W, H), (0,0,0,0))
gd = ImageDraw.Draw(grid)
for x in range(0, W, 100):
    gd.line([(x,0),(x,H)], fill=(166,77,255,15), width=1)
for y in range(0, H, 100):
    gd.line([(0,y),(W,y)], fill=(166,77,255,15), width=1)
bg = Image.alpha_composite(bg.convert("RGBA"), grid)

f_title = font(os.path.expanduser("~/.fonts/Orbitron-var.ttf"), 120, 900)
t_img = Image.new("RGBA", (W, H), (0,0,0,0))
ImageDraw.Draw(t_img).text((W//2, 150), "RESPECT",
                            font=f_title, fill=(212,179,255,255), anchor="mm")
bg = Image.alpha_composite(bg, t_img.filter(ImageFilter.GaussianBlur(20)))
bg = Image.alpha_composite(bg, t_img)

f_sub = font(os.path.expanduser("~/.fonts/Cairo-var.ttf"), 50, 700)
ImageDraw.Draw(bg).text((W//2, 280), "جاري انتظار الستريمرز...",
                        font=f_sub, fill=(255,255,255,255), anchor="mm")

f_list = font(os.path.expanduser("~/.fonts/Orbitron-var.ttf"), 24, 700)
COLS = 5
for i, name in enumerate(STREAMERS):
    row, col = i // COLS, i % COLS
    x, y = 200 + col * 320, 420 + row * 60
    ImageDraw.Draw(bg).text((x, y), name.upper(),
                            font=f_list, fill=(255,255,255), anchor="lm")

bg.convert("RGB").save(os.path.join(WORKDIR, "bg.png"), "PNG")
PYEOF

    WORKDIR="$WORKDIR" python3 /tmp/make_ui.py || return 1

    ffmpeg -y -hide_banner -loglevel warning \
        -loop 1 -framerate 60 -i "$WORKDIR/bg.png" \
        -f lavfi -i "anullsrc=r=44100:cl=stereo" -t 4 \
        -c:v libx264 -preset ultrafast -pix_fmt yuv420p -g 120 -r 60 \
        -c:a aac -b:a 128k -ar 44100 -ac 2 -shortest \
        -f mpegts "$WORKDIR/standby.ts" || return 1
    echo "✅ Standby ready"
    return 0
}

if [ "${PREPARE_ONLY:-0}" = "1" ]; then
    generate_standby
    exit $?
fi

RESTREAM_KEY="${RESTREAM_KEY:-}"
[ -z "$RESTREAM_KEY" ] && { echo "❌ RESTREAM_KEY empty"; exit 1; }

RESTREAM_URL="rtmp://live.restream.io/live/$RESTREAM_KEY"

[ ! -f "$WORKDIR/standby.ts" ] && { generate_standby || exit 1; }

OUT=""; PROD=""; KEEPER=""
ACTIVE_STREAMER=""
MODE="STANDBY"
OUT_STARTED=0; PROD_STARTED=0
OUT_PREV_FRAME=""; PROD_PREV_FRAME=""
OUT_STALL=0; PROD_STALL=0
LAST_SCAN=0
SCAN_INTERVAL=15

stop_group() {
    local pid="${1:-}"
    [ -z "$pid" ] && return 0
    kill -TERM -- "-$pid" 2>/dev/null || true
    local i=0
    while [ $i -lt 20 ]; do
        kill -0 -- "-$pid" 2>/dev/null || { wait "$pid" 2>/dev/null || true; return 0; }
        sleep 0.15; i=$((i+1))
    done
    kill -KILL -- "-$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
}

stop_output() {
    [ -z "$OUT" ] && return 0
    kill -TERM "$OUT" 2>/dev/null || true
    local i=0
    while [ $i -lt 20 ]; do
        kill -0 "$OUT" 2>/dev/null || { wait "$OUT" 2>/dev/null || true; OUT=""; return 0; }
        sleep 0.15; i=$((i+1))
    done
    kill -KILL "$OUT" 2>/dev/null || true
    wait "$OUT" 2>/dev/null || true
    OUT=""
}

stop_producer() { [ -n "$PROD" ] && { stop_group "$PROD"; PROD=""; }; }
stop_keeper()   { [ -n "$KEEPER" ] && { stop_group "$KEEPER"; KEEPER=""; }; }

cleanup() {
    trap - EXIT INT TERM
    stop_producer; stop_output; stop_keeper
    rm -f "$KEEPER_READY" "$FIFO"
}
trap cleanup EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

setup_fifo() { rm -f "$FIFO" "$KEEPER_READY"; mkfifo "$FIFO"; }

start_keeper() {
    rm -f "$KEEPER_READY"
    setsid bash -c 'exec 3>"$1" || exit 1; : > "$2"; exec sleep infinity' \
        _ "$FIFO" "$KEEPER_READY" >/dev/null 2>&1 &
    KEEPER=$!
    local i=0
    while [ $i -lt 100 ]; do
        [ -f "$KEEPER_READY" ] && return 0
        sleep 0.1; i=$((i+1))
    done
    return 1
}

get_frame() {
    [ -f "$1" ] || return 0
    tail -n 30 "$1" 2>/dev/null | awk -F= '$1=="frame" {v=$2} END {print v}'
}

start_output_with_retry() {
    local max_attempts=10
    local i=0
    while [ $i -lt $max_attempts ]; do
        i=$((i+1))
        rm -f /tmp/out.prog
        # 🔥 التعديل الجوهري: معالجة الفيديو بدل نقله + تخصيص خيوط المعالج لمنع الانهيار
        ffmpeg -y -hide_banner -loglevel warning -nostdin \
            -analyzeduration 10M -probesize 10M \
            -f mpegts -i "$FIFO" \
            -map 0:v:0 -map 0:a:0? \
            -c:v libx264 -preset ultrafast -tune zerolatency -threads 2 -pix_fmt yuv420p -g 60 -r 60 \
            -c:a aac -b:a 128k -ar 44100 -ac 2 \
            -progress /tmp/out.prog -stats_period 1 \
            -f flv "$RESTREAM_URL" >/tmp/out.log 2>&1 &
        OUT=$!
        OUT_STARTED=$(date +%s)
        OUT_PREV_FRAME=""; OUT_STALL=0
        sleep 3
        if kill -0 "$OUT" 2>/dev/null; then
            echo "✅ Output connected (attempt $i)"
            return 0
        fi
        echo "⚠️ Output rejected (attempt $i), retry..."
        wait "$OUT" 2>/dev/null || true
        OUT=""
        sleep 2
    done
    echo "❌ Output failed after $max_attempts attempts"
    return 1
}

wait_prod_ready() {
    local i=0
    while [ $i -lt 60 ]; do
        kill -0 "$PROD" 2>/dev/null || return 1
        local f=$(get_frame /tmp/prod.prog)
        [[ "$f" =~ ^[0-9]+$ ]] && [ "$f" -gt 0 ] && return 0
        sleep 0.5; i=$((i+1))
    done
    return 1
}

start_prod_standby() {
    rm -f /tmp/prod.prog
    # التعديل: حلقة لا نهائية باش عشان الأنبوب ما يفضى
    setsid bash -c '
        while true; do
            ffmpeg -y -hide_banner -loglevel warning -re -i "'"$WORKDIR/standby.ts"'" \
                -c copy -mpegts_flags +resend_headers \
                -progress /tmp/prod.prog -stats_period 1 \
                -f mpegts "'"$FIFO"'"
            sleep 0.1
        done
    ' >/tmp/prod.log 2>&1 &
    PROD=$!
    PROD_STARTED=$(date +%s); PROD_PREV_FRAME=""; PROD_STALL=0
    if wait_prod_ready; then
        MODE="STANDBY"; echo "✅ STANDBY active"; return 0
    fi
    stop_producer
    return 1
}

start_prod_live() {
    local NAME="$1"
    rm -f /tmp/prod.prog
    setsid bash -c '
        while true; do
            yt-dlp --no-warnings --quiet --no-check-certificates \
                --user-agent "'"$UA"'" \
                -f "best[protocol^=m3u8]/best" -o - \
                "https://kick.com/'"$NAME"'" 2>/tmp/yt_err.log | \
            ffmpeg -y -hide_banner -loglevel warning -nostdin \
                -fflags +genpts+discardcorrupt \
                -i pipe:0 -c:v copy -c:a aac -b:a 160k -ar 44100 -ac 2 \
                -mpegts_flags +resend_headers -progress /tmp/prod.prog \
                -stats_period 1 -f mpegts "'"$FIFO"'" >/tmp/prod.log 2>&1

            sleep 3
            
            streamlink --http-header "User-Agent='"$UA"'" \
                --http-header "Referer=https://kick.com/" \
                "https://kick.com/'"$NAME"'" best --stdout 2>/dev/null | \
            ffmpeg -y -hide_banner -loglevel warning -nostdin \
                -fflags +genpts+discardcorrupt \
                -i pipe:0 -c:v copy -c:a aac -b:a 160k -ar 44100 -ac 2 \
                -mpegts_flags +resend_headers -progress /tmp/prod.prog \
                -stats_period 1 -f mpegts "'"$FIFO"'" >/tmp/prod.log 2>&1

            sleep 3
        done
    ' >/dev/null 2>&1 &
    PROD=$!
    PROD_STARTED=$(date +%s); PROD_PREV_FRAME=""; PROD_STALL=0
    if wait_prod_ready; then
        MODE="LIVE"; echo "✅ LIVE: $NAME"; return 0
    fi
    stop_producer
    return 1
}

find_active_streamer() {
    local pids=()
    local tmpdir=$(mktemp -d)
    for S in "${STREAMERS[@]}"; do
        S=$(echo "$S" | xargs)
        [ -z "$S" ] && continue
        (
            IS_LIVE=$(curl -s -m 5 -A "$UA" "https://kick.com/api/v2/channels/$S" | grep -o '"is_live":true')
            if [ -n "$IS_LIVE" ]; then
                : > "$tmpdir/$S"
            fi
        ) &
        pids+=($!)
    done
    wait "${pids[@]}" 2>/dev/null || true

    local found=""
    for S in "${STREAMERS[@]}"; do
        S=$(echo "$S" | xargs)
        if [ -f "$tmpdir/$S" ]; then found="$S"; break; fi
    done
    rm -rf "$tmpdir"
    [ -n "$found" ] && { echo "$found"; return 0; }
    return 1
}

start_best_source() {
    local found
    found=$(find_active_streamer)
    if [ -n "$found" ]; then
        ACTIVE_STREAMER="$found"
        start_prod_live "$found" && return 0
    fi
    ACTIVE_STREAMER=""
    start_prod_standby
}

restart_output_chain() {
    echo "♻️  Full chain restart"
    stop_producer; stop_output; stop_keeper
    setup_fifo
    start_output_with_retry || { echo "❌ FATAL: cannot connect"; exit 1; }
    start_keeper || { echo "❌ FATAL: keeper failed"; exit 1; }
    start_best_source
    LAST_SCAN=$(date +%s)
}

if [ -n "${MY_RUN_ID:-}" ] && [ -n "${GH_TOKEN:-}" ]; then
    echo "📅 Scheduling next run in 5h20m"
    setsid nohup bash -c "
        sleep 19200
        for i in 1 2 3 4 5; do
            if gh workflow run main.yml --ref '${GITHUB_REF_NAME:-main}' -f parent_run_id=$MY_RUN_ID; then
                echo \"✅ Next run dispatched (attempt \$i)\"
                exit 0
            fi
            sleep 60
        done
    " >/tmp/sched.log 2>&1 < /dev/null &
fi

echo "🚀 Respect Relay V15 starting..."
setup_fifo
start_output_with_retry || { echo "❌ FATAL: initial connect failed"; exit 1; }
start_keeper || { echo "❌ FATAL: keeper failed"; exit 1; }
start_best_source
LAST_SCAN=$(date +%s)

while true; do
    NOW=$(date +%s)

    if ! kill -0 "$OUT" 2>/dev/null; then
        echo "⚠️ Output died"
        restart_output_chain
        continue
    fi

    if ! kill -0 "$PROD" 2>/dev/null; then
        echo "⚠️ Producer died"
        stop_producer
        sleep 5
        start_best_source
        continue
    fi

    if [ $((NOW - OUT_STARTED)) -ge 15 ]; then
        F=$(get_frame /tmp/out.prog)
        MT=$(stat -c %Y /tmp/out.prog 2>/dev/null || echo 0)
        if [ $((NOW - MT)) -ge 15 ]; then
            OUT_STALL=15
        elif [[ "$F" =~ ^[0-9]+$ ]]; then
            if [ -n "$OUT_PREV_FRAME" ] && [ "$F" -le "$OUT_PREV_FRAME" ]; then
                OUT_STALL=$((OUT_STALL + 1))
            else
                OUT_STALL=0
            fi
            OUT_PREV_FRAME="$F"
        fi
        if [ "$OUT_STALL" -ge 15 ]; then
            echo "⚠️ Output stalled"
            restart_output_chain
            continue
        fi
    fi

    if [ $((NOW - PROD_STARTED)) -ge 15 ]; then
        F=$(get_frame /tmp/prod.prog)
        MT=$(stat -c %Y /tmp/prod.prog 2>/dev/null || echo 0)
        if [ $((NOW - MT)) -ge 12 ]; then
            PROD_STALL=12
        elif [[ "$F" =~ ^[0-9]+$ ]]; then
            if [ -n "$PROD_PREV_FRAME" ] && [ "$F" -le "$PROD_PREV_FRAME" ]; then
                PROD_STALL=$((PROD_STALL + 1))
            else
                PROD_STALL=0
            fi
            PROD_PREV_FRAME="$F"
        fi
        if [ "$PROD_STALL" -ge 12 ]; then
            echo "⚠️ Producer stalled"
            stop_producer
            start_best_source
            continue
        fi
    fi

    if [ $((NOW - LAST_SCAN)) -ge "$SCAN_INTERVAL" ]; then
        LAST_SCAN=$NOW
        FOUND=$(find_active_streamer)
        if [ -n "$FOUND" ]; then
            if [ "$MODE" != "LIVE" ] || [ "$ACTIVE_STREAMER" != "$FOUND" ]; then
                echo "🔀 Switching to: $FOUND"
                stop_producer
                ACTIVE_STREAMER="$FOUND"
                start_prod_live "$FOUND" || start_prod_standby
            fi
        else
            if [ "$MODE" = "LIVE" ]; then
                echo "📴 All offline, standby"
                stop_producer
                ACTIVE_STREAMER=""
                start_prod_standby
            fi
        fi
    fi

    sleep 1
done
