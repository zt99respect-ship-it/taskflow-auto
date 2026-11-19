#!/bin/bash
set +m

# ═══════════════════════════════════════════════════
#  SXB Broadcast — Smart State Machine (Infinite)
# ═══════════════════════════════════════════════════

STREAMER="drb7h"
TITLE_AR=" انتهى البث او علق "
SUBTITLE_AR="بث ريسبكت!"
LOGO_URL="https://h.top4top.io/p_3966xt60d0.png"
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

RESTREAM_KEY="${RESTREAM_KEY:-re_12552561_event81737fba9ada4713ab13ad7e04a36880}"
[ -z "$RESTREAM_KEY" ] && { echo "❌ مفتاح Restream فارغ"; exit 1; }

RESTREAM_URL="rtmp://live.restream.io/live/$RESTREAM_KEY"
WORKDIR="/tmp/standby_sxb"
mkdir -p "$WORKDIR"

# 1. توليد شاشة الانتظار
if [ ! -f "$WORKDIR/standby.ts" ]; then
    echo "🎨 تصميم شاشة الانتظار..."
    cat > /tmp/make_ui.py <<'PYEOF'
from PIL import Image, ImageDraw, ImageFilter, ImageFont
import urllib.request, io, os

W, H = 1920, 1080
WORKDIR = os.environ["WORKDIR"]
FONT_AR = os.path.expanduser("~/.fonts/Cairo-var.ttf")
FONT_EN = os.path.expanduser("~/.fonts/Orbitron-var.ttf")
TITLE = os.environ.get("TITLE_AR", "توقف البث")
SUBTITLE = os.environ.get("SUBTITLE_AR", "جاري الانتظار...")
STREAMER = os.environ.get("STREAMER", "drb7h")
LOGO_URL = os.environ.get("LOGO_URL", "https://h.top4top.io/p_3966xt60d0.png")

def load_font(path, size, weight=700):
    try:
        font = ImageFont.truetype(path, size)
        axes = font.get_variation_axes()
        if len(axes) == 1: font.set_variation_by_axes([weight])
        elif len(axes) == 2: font.set_variation_by_axes([0, weight])
        return font
    except: return ImageFont.load_default()

bg = Image.new("RGB", (W, H))
d = ImageDraw.Draw(bg)
for y in range(H):
    t = y / H
    d.line([(0, y), (W, y)], fill=(int(30*(1-t)), int(0), int(0)))

glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
gd = ImageDraw.Draw(glow)
gd.ellipse([W//2 - 600, H//2 - 400, W//2 + 600, H//2 + 400], fill=(255, 0, 0, 80))
glow = glow.filter(ImageFilter.GaussianBlur(250))
bg = bg.convert("RGBA")
bg = Image.alpha_composite(bg, glow)

corner = Image.new("RGBA", (W, H), (0, 0, 0, 0))
cd = ImageDraw.Draw(corner)
SIZE = 80
def draw_corner(cx, cy, fx, fy):
    cd.line([(cx, cy), (cx + SIZE*fx, cy)], fill=(255, 0, 0, 255), width=4)
    cd.line([(cx, cy), (cx, cy + SIZE*fy)], fill=(255, 0, 0, 255), width=4)
draw_corner(40, 40, 1, 1); draw_corner(W-40, 40, -1, 1)
draw_corner(40, H-40, 1, -1); draw_corner(W-40, H-40, -1, -1)
bg = Image.alpha_composite(bg, corner)

card_w, card_h = 1200, 600
card_x, card_y = (W - card_w)//2, (H - card_h)//2
card = Image.new("RGBA", (W, H), (0, 0, 0, 0))
cd = ImageDraw.Draw(card)
cd.rounded_rectangle([(card_x, card_y), (card_x+card_w, card_y+card_h)], radius=20, fill=(20, 0, 0, 150), outline=(255, 0, 0, 100), width=2)
cd.rounded_rectangle([(card_x+5, card_y+5), (card_x+card_w-5, card_y+card_h-5)], radius=18, outline=(255, 255, 255, 30), width=1)
bg = Image.alpha_composite(bg, card)

font_title = load_font(FONT_AR, 100, 900)
font_sub = load_font(FONT_AR, 50, 700)
font_sxb = load_font(FONT_EN, 150, 900)

t_img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
ImageDraw.Draw(t_img).text((W//2, card_y + 100), TITLE, font=font_title, fill=(255, 255, 255, 255), anchor="mm", direction="rtl")
bg = Image.alpha_composite(bg, t_img.filter(ImageFilter.GaussianBlur(20)))
bg = Image.alpha_composite(bg, t_img)

s_img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
ImageDraw.Draw(s_img).text((W//2, card_y + 220), SUBTITLE, font=font_sub, fill=(255, 255, 255, 200), anchor="mm", direction="rtl")
bg = Image.alpha_composite(bg, s_img)

sxb_img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
ImageDraw.Draw(sxb_img).text((W//2, card_y + 400), STREAMER, font=font_sxb, fill=(255, 0, 0, 255), anchor="mm")
bg = Image.alpha_composite(bg, sxb_img.filter(ImageFilter.GaussianBlur(40)))
bg = Image.alpha_composite(bg, sxb_img)

try:
    req = urllib.request.Request(LOGO_URL, headers={"User-Agent": "Mozilla/5.0"})
    logo = Image.open(io.BytesIO(urllib.request.urlopen(req, timeout=10).read())).convert("RGBA")
    logo = logo.resize((150, int(logo.height * (150 / logo.width))), Image.LANCZOS)
    bg.alpha_composite(logo, ((W - 150)//2, card_y - 90))
except Exception: pass

bg.convert("RGB").save(f"{WORKDIR}/bg.png")
PYEOF
    WORKDIR="$WORKDIR" STREAMER="$STREAMER" TITLE_AR="$TITLE_AR" SUBTITLE_AR="$SUBTITLE_AR" LOGO_URL="$LOGO_URL" python3 /tmp/make_ui.py
    ffmpeg -y -hide_banner -loglevel warning -loop 1 -framerate 60 -i "$WORKDIR/bg.png" \
        -f lavfi -i "anullsrc=r=44100:cl=stereo" -t 4 \
        -c:v libx264 -preset ultrafast -pix_fmt yuv420p -g 120 -r 60 \
        -c:a aac -b:a 128k -ar 44100 -ac 2 -shortest \
        -f mpegts "$WORKDIR/standby.ts"
fi

# ═══════════════════════════════════════════════════
#  منطق التسليم والتسلّم (Handoff)
# ═══════════════════════════════════════════════════
echo "🔍 البحث عن رنات قديمة شغالة..."
OLD_RUNS=$(gh run list --workflow="main.yml" --status=in_progress --json databaseId --jq '.[].databaseId' 2>/dev/null | awk -v m="$GITHUB_RUN_ID" '$1 != m')

if [ -n "$OLD_RUNS" ]; then
    echo "⚠️ يوجد رن قديم نشط: $OLD_RUNS"
    for R in $OLD_RUNS; do
        timeout 10 gh run cancel "$R" 2>/dev/null || true
    done
    echo "⏳ انتظار 3 ثوانٍ لتحرير اتصال Restream..."
    sleep 3
else
    echo "✅ لا يوجد رن قديم. بدء البث مباشرة."
fi

# ═══════════════════════════════════════════════════
#  دوال البث
# ═══════════════════════════════════════════════════
LIVE_PID=""
STANDBY_PID=""

kill_streams() {
    if [ -n "$LIVE_PID" ] && kill -0 "$LIVE_PID" 2>/dev/null; then
        kill "$LIVE_PID" 2>/dev/null
        wait "$LIVE_PID" 2>/dev/null
    fi
    LIVE_PID=""
    
    if [ -n "$STANDBY_PID" ] && kill -0 "$STANDBY_PID" 2>/dev/null; then
        kill "$STANDBY_PID" 2>/dev/null
        wait "$STANDBY_PID" 2>/dev/null
    fi
    STANDBY_PID=""
}

stream_live() {
    echo "🔴 بث مباشر: $STREAMER (1080p60 Zero-CPU)"
    streamlink --http-header "User-Agent=$UA" "https://kick.com/$STREAMER" best --stdout 2>/dev/null | \
    ffmpeg -hide_banner -loglevel warning -nostdin \
        -thread_queue_size 512 \
        -fflags +genpts+discardcorrupt \
        -err_detect ignore_err \
        -i pipe:0 \
        -c:v copy \
        -af "volume=1.1,alimiter=limit=0.95" \
        -c:a aac -b:a 160k -ar 44100 -ac 2 \
        -max_muxing_queue_size 4096 -flvflags no_duration_filesize \
        -f flv "$RESTREAM_URL" &
    LIVE_PID=$!
}

stream_standby_timer() {
    local REMAINING=$1
    echo "⏳ إرسال شاشة انتظار (مؤقت: $REMAINING ثانية)..."
    ffmpeg -hide_banner -loglevel warning -nostdin \
        -re -stream_loop -1 -i "$WORKDIR/standby.ts" \
        -vf "drawtext=fontfile=$HOME/.fonts/Orbitron-var.ttf:text='%{eif\:floor((${REMAINING}-t)/60)\:d\:2}\:%{eif\:mod(${REMAINING}-t\,60)\:d\:2}':x=w-tw-100:y=100:fontsize=70:fontcolor=red:box=1:boxcolor=black@0.5" \
        -c:v libx264 -preset ultrafast -pix_fmt yuv420p -g 60 -r 30 -threads 1 \
        -c:a aac -b:a 128k -ar 44100 -ac 2 \
        -t "$REMAINING" -f flv "$RESTREAM_URL" >/tmp/standby.log 2>&1 &
    STANDBY_PID=$!
}

# ═══════════════════════════════════════════════════
#  الحلقة الرئيسية (الآلة الذكية)
# ═══════════════════════════════════════════════════
echo "🚀 بدء المراقبة الدائمة..."

CURRENT_MODE="INIT_OFFLINE" # INIT_OFFLINE, LIVE, TIMER, DEAD_AIR
OFFLINE_START=0
MAX_OFFLINE=600 # 10 دقائق

while true; do
    URL=$(timeout 10 streamlink --http-header "User-Agent=$UA" "https://kick.com/$STREAMER" best --stream-url 2>/dev/null | grep -m1 "^http")

    if [ -n "$URL" ]; then
        # ---------------- الستريمر أونلاين ----------------
        OFFLINE_START=0
        
        if [ "$CURRENT_MODE" != "LIVE" ]; then
            echo "🟢 الستريمر متصل! تحويل للبث المباشر..."
            kill_streams
            stream_live
            CURRENT_MODE="LIVE"
        fi
    else
        # ---------------- الستريمر أوفلاين ----------------
        NOW=$(date +%s)
        
        if [ "$CURRENT_MODE" = "LIVE" ]; then
            # كان يبث وطفى -> نبدأ العداد
            echo "🔴 الستريمر طفى! بدء العداد التنازلي (10 دقائق)..."
            OFFLINE_START=$NOW
            kill_streams
            stream_standby_timer "$MAX_OFFLINE"
            CURRENT_MODE="TIMER"
            
        elif [ "$CURRENT_MODE" = "TIMER" ]; then
            # نحن في فترة العداد
            ELAPSED=$((NOW - OFFLINE_START))
            REMAINING=$((MAX_OFFLINE - ELAPSED))
            
            if [ "$REMAINING" -le 0 ]; then
                # العداد خلص -> إيقاف الإرسال
                echo "🛑 انتهى وقت الانتظار (10 دقائق). قطع الإرسال لريستريم..."
                kill_streams
                CURRENT_MODE="DEAD_AIR"
            elif [ -n "$STANDBY_PID" ] && ! kill -0 "$STANDBY_PID" 2>/dev/null; then
                # إذا ماتت شاشة الانتظار فجأة لأي سبب، نرجع نشغلها
                stream_standby_timer "$REMAINING"
            fi
            
        elif [ "$CURRENT_MODE" = "INIT_OFFLINE" ] || [ "$CURRENT_MODE" = "DEAD_AIR" ]; then
            # الستريمر طافي من البداية أو العداد خلص -> نسكت تماماً
            # لا نرسل شي لريستريم، بس ننتظر
            if [ "$CURRENT_MODE" = "INIT_OFFLINE" ]; then
                echo "⏳ الستريمر أوفلاين. في انتظار بدء البث (لا يتم إرسال شيء لريستريم)..."
                CURRENT_MODE="DEAD_AIR"
            fi
        fi
    fi

    # فحص كل 30 ثانية
    sleep 30
done
