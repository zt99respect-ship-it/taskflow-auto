#!/bin/bash
set +m
set -uo pipefail

# ═══════════════════════════════════════════════════════════════
#  Respect Broadcast — V18 (Direct Pipe - No FIFO - Bulletproof)
# ═══════════════════════════════════════════════════════════════

STREAMERS_LIST="${STREAMERS_LIST:-drb7h,S5B,ABO8ALYY,ID7O,F1AISAL,xmusabrt,TAF86,abo_khrbaa,Peerless,Seagull,iMonkey_D,FHLWY,Hook,okb8,wolf,NASSER,Aymnalsatam,BoQamar,NEFOXD,RAYN,xya7ya,W1pey,ALRND,klash,Sayko_911,ZAiKRx}"
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

WORKDIR="/tmp/standby_respect"
mkdir -p "$WORKDIR"
IFS=',' read -r -a STREAMERS <<< "$STREAMERS_LIST"
export STREAMERS_LIST UA WORKDIR

# ───────────────────────────────────────────────
#  Standby screen generation
# ───────────────────────────────────────────────
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
        if len(axes) == 1: f.set_variation_by_axes([weight])
        elif len(axes) == 2: f.set_variation_by_axes([0, weight])
        return f
    except Exception: return ImageFont.load_default()

bg = Image.new("RGB", (W, H), (10, 2, 20))
d = ImageDraw.Draw(bg)
for y in range(H):
    t = y / H
    d.line([(0, y), (W, y)], fill=(int(10+20*t), int(2+8*t), int(20+30*t)))

grid = Image.new("RGBA", (W, H), (0,0,0,0))
gd = ImageDraw.Draw(grid)
for x in range(0, W, 100): gd.line([(x,0),(x,H)], fill=(166,77,255,15), width=1)
for y in range(0, H, 100): gd.line([(0,y),(W,y)], fill=(166,77,255,15), width=1)
bg = Image.alpha_composite(bg.convert("RGBA"), grid)

f_title = font(os.path.expanduser("~/.fonts/Orbitron-var.ttf"), 120, 900)
t_img = Image.new("RGBA", (W, H), (0,0,0,0))
ImageDraw.Draw(t_img).text((W//2, 150), "RESPECT", font=f_title, fill=(212,179,255,255), anchor="mm")
bg = Image.alpha_composite(bg, t_img.filter(ImageFilter.GaussianBlur(20)))
bg = Image.alpha_composite(bg, t_img)

f_sub = font(os.path.expanduser("~/.fonts/Cairo-var.ttf"), 50, 700)
ImageDraw.Draw(bg).text((W//2, 280), "جاري انتظار الستريمرز...", font=f_sub, fill=(255,255,255,255), anchor="mm")

f_list = font(os.path.expanduser("~/.fonts/Orbitron-var.ttf"), 24, 700)
COLS = 5
for i, name in enumerate(STREAMERS):
    row, col = i // COLS, i % COLS
    x, y = 200 + col * 320, 420 + row * 60
    ImageDraw.Draw(bg).text((x, y), name.upper(), font=f_list, fill=(255,255,255), anchor="lm")

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

# ───────────────────────────────────────────────
#  Direct Pipe Process Management
# ───────────────────────────────────────────────
CURRENT_PID=""
MODE="STANDBY"
ACTIVE_STREAMER=""

kill_current() {
    if [ -n "$CURRENT_PID" ] && kill -0 "$CURRENT_PID" 2>/dev/null; then
        # نقتل العملية وكل توابعها
        kill -TERM -"$CURRENT_PID" 2>/dev/null || kill -TERM "$CURRENT_PID" 2>/dev/null
        sleep 1
        kill -KILL -"$CURRENT_PID" 2>/dev/null || kill -KILL "$CURRENT_PID" 2>/dev/null
    fi
    CURRENT_PID=""
}

start_standby() {
    echo "⏳ Playing Standby..."
    setsid ffmpeg -y -hide_banner -loglevel warning -re -stream_loop -1 -i "$WORKDIR/standby.ts" \
        -c:v copy -c:a aac -b:a 128k -ar 44100 -ac 2 \
        -f flv "$RESTREAM_URL" >/tmp/out.log 2>&1 &
    CURRENT_PID=$!
    MODE="STANDBY"
    ACTIVE_STREAMER=""
}

start_live() {
    local NAME="$1"
    echo "🔴 Playing Live: $NAME"
    setsid bash -c '
        streamlink --http-header "User-Agent='"$UA"'" "https://kick.com/'"$NAME"'" best --stdout 2>/dev/null | \
        ffmpeg -y -hide_banner -loglevel warning -i pipe:0 \
            -c:v copy -c:a aac -b:a 128k -ar 44100 -ac 2 \
            -f flv "'"$RESTREAM_URL"'"
    ' >/tmp/out.log 2>&1 &
    CURRENT_PID=$!
    MODE="LIVE"
    ACTIVE_STREAMER="$NAME"
}

# فحص الحالة عن طريق API كيك (أسرع 100 مرة من streamlink وما يعلق)
check_streamer_live() {
    local NAME="$1"
    local API_RES=$(curl -s -m 5 -A "$UA" "https://kick.com/api/v2/channels/$NAME")
    if echo "$API_RES" | grep -q '"is_live":true'; then
        return 0
    fi
    return 1
}

# ───────────────────────────────────────────────
#  Schedule next run
# ───────────────────────────────────────────────
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

# ───────────────────────────────────────────────
#  Boot
# ───────────────────────────────────────────────
echo "🚀 Respect Relay V18 starting..."
start_standby
LAST_SCAN=$(date +%s)

# ───────────────────────────────────────────────
#  Main Loop (Bulletproof Direct Pipe)
# ───────────────────────────────────────────────
while true; do
    NOW=$(date +%s)

    # 1. إذا مات البث فجأة (انقطع النت أو الستريمر سكر بثه)
    if ! kill -0 "$CURRENT_PID" 2>/dev/null; then
        echo "⚠️ Stream dropped (PID $CURRENT_PID). Restarting..."
        start_standby
        sleep 2
        continue
    fi

    # 2. الفحص الدوري (كل 15 ثانية)
    if [ $((NOW - LAST_SCAN)) -ge 15 ]; then
        LAST_SCAN=$NOW

        if [ "$MODE" = "LIVE" ]; then
            # إذا كنا نبث ستريمر، نتأكد إنه ما سكر
            if ! check_streamer_live "$ACTIVE_STREAMER"; then
                echo "📴 $ACTIVE_STREAMER went offline."
                kill_current
                start_standby
            fi
        else
            # إذا كنا على شاشة الانتظار، نفحص كل الستريمرز
            for S in "${STREAMERS[@]}"; do
                S=$(echo "$S" | xargs)
                [ -z "$S" ] && continue
                
                if check_streamer_live "$S"; then
                    echo "🔀 Found LIVE streamer: $S"
                    kill_current
                    start_live "$S"
                    break
                fi
            done
        fi
    fi

    sleep 1
done
