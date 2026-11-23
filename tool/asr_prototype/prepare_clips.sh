#!/usr/bin/env bash
# بينزّل تلاوات تجريبية (آية بآية) من everyayah.com لعدة قرّاء، بيدمجها
# بمقاطع متصلة، وبيحوّلها لـ WAV 16kHz mono (الصيغة اللي بيحتاجها المحرك).
# الملفات للاختبار بس (ما بتنضاف للمستودع ولا للـ APK).
# usage: prepare_clips.sh OUT_DIR   → يكتب OUT_DIR/clips.json
set -euo pipefail
OUT="${1:?out dir}"
mkdir -p "$OUT/mp3"
BASE="https://everyayah.com/data"

# id | reciter folder | surah | first ayah | last ayah | expected | degrade(0/1)
CLIPS=(
  "fatiha_alafasy|Alafasy_128kbps|1|1|7|1:1-1:7|0"
  "fatiha_husary|Husary_128kbps|1|1|7|1:1-1:7|0"
  "fatiha_abdulbasit|Abdul_Basit_Murattal_192kbps|1|1|7|1:1-1:7|0"
  "ikhlas_minshawy|Minshawy_Murattal_128kbps|112|1|4|112:1-112:4|0"
  "kursi_alafasy|Alafasy_128kbps|2|255|255|2:255-2:255|0"
  "kursi_husary|Husary_128kbps|2|255|255|2:255-2:255|0"
  "rahman_abdulbasit|Abdul_Basit_Murattal_192kbps|55|13|18|55:13-55:18|0"
  "yasin_ghamadi_lowbitrate|Ghamadi_40kbps|36|1|12|36:1-36:12|0"
  "kahf_husary_mid|Husary_128kbps|18|10|10|18:10-18:10|0"
  "mulk_alafasy_phone_noisy|Alafasy_128kbps|67|1|5|67:1-67:5|1"
  "kahf_alafasy_phone_noisy|Alafasy_128kbps|18|1|4|18:1-18:4|1"
)

echo "[" > "$OUT/clips.json"
first=1
for row in "${CLIPS[@]}"; do
  IFS='|' read -r id rec s a1 a2 expected degrade <<< "$row"
  list="$OUT/mp3/$id.txt"; : > "$list"
  okall=1
  for ((a=a1; a<=a2; a++)); do
    f=$(printf "%03d%03d.mp3" "$s" "$a")
    dst="$OUT/mp3/${rec}_$f"
    if [ ! -s "$dst" ]; then
      curl -fsSL --retry 3 -o "$dst" "$BASE/$rec/$f" || { echo "WARN: missing $rec/$f"; okall=0; break; }
    fi
    echo "file '$(realpath "$dst")'" >> "$list"
  done
  [ "$okall" = 1 ] || continue
  wav="$OUT/$id.wav"
  if [ "$degrade" = 1 ]; then
    # محاكاة تسجيل جوال: نطاق 300-3400Hz + ضجيج خفيف + صوت أوطى.
    ffmpeg -loglevel error -y -f concat -safe 0 -i "$list" \
      -f lavfi -i "anoisesrc=color=pink:amplitude=0.02:sample_rate=16000" \
      -filter_complex "[0:a]aresample=16000,highpass=f=300,lowpass=f=3400,volume=0.7[v];[v][1:a]amix=inputs=2:duration=first:normalize=0[o]" \
      -map "[o]" -ac 1 -ar 16000 -c:a pcm_s16le "$wav"
  else
    ffmpeg -loglevel error -y -f concat -safe 0 -i "$list" -ac 1 -ar 16000 -c:a pcm_s16le "$wav"
  fi
  [ $first = 1 ] || echo "," >> "$OUT/clips.json"
  first=0
  printf '{"id":"%s","reciter":"%s","expected":"%s","degraded":%s,"wav":"%s"}\n' \
    "$id" "$rec" "$expected" "$([ "$degrade" = 1 ] && echo true || echo false)" "$wav" >> "$OUT/clips.json"
done
echo "]" >> "$OUT/clips.json"
cat "$OUT/clips.json"
