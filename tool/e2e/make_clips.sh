#!/usr/bin/env bash
# يوم 8: مقاطع اختبار التصدير (export-e2e.yml). 7 ثواني، 30fps، خلفيات
# متدرجة ناعمة (غامقة للنص الأبيض وفاتحة للنص الأسود) + صوت.
set -euo pipefail
out=${1:-build/e2e_clips}
mkdir -p "$out"
cd "$out"
D=7
dark="gradients=s=%s:c0=0x0b1f2a:c1=0x1f3b2c:c2=0x2a1f3b:speed=0.02:r=30:d=$D"
light="gradients=s=%s:c0=0xf6f2e6:c1=0xe2dccb:c2=0xeef3f6:speed=0.02:r=30:d=$D"
tone="sine=f=440:sample_rate=48000:d=$D"

mk() { # name size bg extra...
  local name=$1 size=$2 bg=$3; shift 3
  ffmpeg -hide_banner -loglevel error -y \
    -f lavfi -i "$(printf "$bg" "$size"),format=yuv420p" -f lavfi -i "$tone" \
    -c:v libx264 -preset veryfast -crf 20 -g 30 -pix_fmt yuv420p \
    -c:a aac -b:a 128k -shortest "$@" "$name"
}

mk portrait_dark.mp4 1080x1920 "$dark"
mk portrait_light.mp4 1080x1920 "$light"
mk landscape_dark.mp4 1920x1080 "$dark"
mk square_light.mp4 1080x1080 "$light"
# مخزّن أفقي 1920x1080 بعلامة دوران 90° → المستخدم بيشوفه عمودي 1080x1920.
mk land_for_rot.mp4 1920x1080 "$dark"
ffmpeg -hide_banner -loglevel error -y -display_rotation:v:0 90 -i land_for_rot.mp4 -c copy rot90_dark.mp4
rm land_for_rot.mp4
# أبعاد فردية (H.264 ما بيقبلها، فـ VP9 + Opus بـ WebM): الناتج لازم يطلع 1080x1920.
ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i "$(printf "$dark" 1081x1921),format=yuv420p" -f lavfi -i "$tone" \
  -c:v libvpx-vp9 -deadline realtime -cpu-used 8 -b:v 3M -row-mt 1 \
  -c:a libopus -b:a 96k -shortest odd_dark.webm
# ملف تلاوة منفصل (أطول من الفيديو: لازم ينقص على مدته).
ffmpeg -hide_banner -loglevel error -y -f lavfi -i "sine=f=660:sample_rate=44100:d=10" \
  -c:a aac -b:a 128k recite.m4a

cat > cases.json <<'J'
[
  {"name": "portrait_white", "file": "portrait_dark.mp4", "color": "white"},
  {"name": "portrait_black_shadow", "file": "portrait_light.mp4", "color": "black", "shadow": true},
  {"name": "portrait_white_shadow_long", "file": "portrait_dark.mp4", "color": "white", "shadow": true, "long": true},
  {"name": "landscape_white_shadow", "file": "landscape_dark.mp4", "color": "white", "shadow": true},
  {"name": "square_black", "file": "square_light.mp4", "color": "black"},
  {"name": "rotated90_white", "file": "rot90_dark.mp4", "color": "white"},
  {"name": "odd_1081x1921_vp9", "file": "odd_dark.webm", "color": "white", "shadow": true},
  {"name": "external_audio_amiri_full", "file": "portrait_dark.mp4", "audio": "recite.m4a", "color": "white", "font": "amiriQuran", "tafsir": "fullUnderEachPart"}
]
J
for f in *.mp4 *.webm; do
  echo "== $f"; ffprobe -v error -select_streams v:0 -show_entries stream=codec_name,width,height,r_frame_rate:stream_side_data=rotation -of compact "$f"
done
ls -la
