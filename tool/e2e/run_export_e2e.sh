#!/usr/bin/env bash
# يوم 8: بيشغّل integration_test/export_e2e_test.dart على المحاكي، وبيحط
# مقاطع الاختبار بملفات التطبيق أول ما ينزل (run-as، APK debug).
set -uo pipefail
PKG=com.ayahstudio.app
CLIPS=${1:-build/e2e_clips}
OUT=${2:-build/e2e_out}
mkdir -p "$OUT"
adb wait-for-device
flutter test integration_test/export_e2e_test.dart -d emulator-5554 --reporter expanded \
  > "$OUT/flutter_test.log" 2>&1 &
PID=$!
echo "waiting for $PKG to be installed..."
for i in $(seq 1 600); do
  if adb shell pm path $PKG 2>/dev/null | grep -q package:; then break; fi
  sleep 2
done
adb shell pm grant $PKG android.permission.POST_NOTIFICATIONS || true
adb shell run-as $PKG mkdir -p files/e2e_in
for f in "$CLIPS"/*; do
  b=$(basename "$f")
  adb push "$f" /data/local/tmp/"$b" >/dev/null
  adb shell chmod 644 /data/local/tmp/"$b"
  adb shell run-as $PKG cp /data/local/tmp/"$b" files/e2e_in/"$b"
done
adb shell run-as $PKG touch files/e2e_in/READY
adb shell run-as $PKG ls -la files/e2e_in
# حالة "background_home": لما التجربة تطلب، Home → فحص الخدمة والإشعار → رجوع.
(
  for i in $(seq 1 3600); do
    kill -0 $PID 2>/dev/null || break
    if adb shell run-as $PKG ls files/e2e_out/GO_HOME >/dev/null 2>&1; then
      adb shell run-as $PKG rm files/e2e_out/GO_HOME
      adb shell input keyevent KEYCODE_HOME
      sleep 10
      {
        echo "== services (app in background)"
        adb shell dumpsys activity services $PKG | grep -E "ServiceRecord|isForeground|foregroundServiceType|foregroundId" || true
        echo "== top activity"
        adb shell dumpsys activity activities | grep -E "topResumedActivity|mResumedActivity" | head -3 || true
        echo "== notifications"
        adb shell dumpsys notification --noredact | grep -E "pkg=$PKG|android.title=|android.text=|android.progress=" | head -20 || true
      } > "$OUT/background_check.txt" 2>&1
      sleep 5
      adb shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
    fi
    if adb shell run-as $PKG ls files/e2e_out/DONE_WRITING >/dev/null 2>&1; then
      adb shell run-as $PKG rm files/e2e_out/DONE_WRITING
      adb exec-out run-as $PKG tar c files/e2e_out > "$OUT/e2e_out.tar" 2>/dev/null
      tar xf "$OUT/e2e_out.tar" -C "$OUT" && rm "$OUT/e2e_out.tar" && echo "سحبنا e2e_out" || echo "فشل سحب e2e_out"
      adb shell run-as $PKG touch files/e2e_out/PULLED
    fi
    sleep 1
  done
) &
wait $PID
CODE=$?
cat "$OUT/flutter_test.log" | grep -v "^I/flutter.*E2E_SUMMARY" | tail -200
adb pull /sdcard/Movies/AyahStudio "$OUT/gallery" >/dev/null 2>&1 || echo "ما في Movies/AyahStudio"
adb logcat -d -s AyahExport:* Transformer:* MediaCodec:* > "$OUT/logcat_export.txt" 2>/dev/null || true
cat "$OUT/background_check.txt" 2>/dev/null || true
grep -h "E2E_CASE" "$OUT/flutter_test.log" | sed 's/.*E2E_CASE //' > "$OUT/cases.jsonl" || true
exit $CODE
