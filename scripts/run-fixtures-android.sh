#!/usr/bin/env bash
# Convierte la matriz de fixtures en un dispositivo Android y valida los MP3 con ffprobe.
#   1. scripts/make-fixtures.sh            (genera fixtures/out/)
#   2. scripts/run-fixtures-android.sh     (adb push → FixturesTest → adb pull → check-mp3)
# Requiere: adb, ffprobe y example/android generado (cd example && npx expo prebuild -p android).
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/fixtures/out"
pkg="expo.modules.audio2mp3.test"
remote="/sdcard/Android/data/$pkg/files/fixtures"

[ -f "$out/expected.tsv" ] || { echo "Ejecuta antes scripts/make-fixtures.sh" >&2; exit 1; }

adb shell rm -rf "$remote"
adb shell mkdir -p "$remote"
adb push "$out/." "$remote/" >/dev/null

(cd "$root/example/android" && ./gradlew :expo-audio2mp3:connectedAndroidTest \
  -Pandroid.testInstrumentationRunnerArguments.class=expo.modules.audio2mp3.FixturesTest)

rm -rf "$out/results"
adb pull "$remote/results" "$out/results" >/dev/null

failed=0
# results.tsv: archivo, resultado, sampleRate, canales, bitrate, duración ms, tiempo, memoria nativa
while IFS=$'\t' read -r file outcome rate channels bitrate duration _rest; do
  [ "$outcome" = "OK" ] || continue
  bash "$root/scripts/check-mp3.sh" "$out/results/${file%.*}.mp3" "$rate" "$channels" "$bitrate" "$duration" || failed=1
done < "$out/results/results.tsv"
exit "$failed"
