#!/usr/bin/env bash
# Valida un MP3 con ffprobe: sample rate, canales, bitrate y duración (±1 frame).
#
# Uso: scripts/check-mp3.sh <archivo.mp3> <sampleRate|-> <canales|-> <bitrate kbps> <duración ms>
set -euo pipefail

file="$1"; rate="$2"; channels="$3"; kbps="$4"; duration_ms="$5"

probe() { ffprobe -v error -select_streams a:0 -show_entries "$1" -of default=nw=1:nk=1 "$file"; }

codec="$(probe stream=codec_name)"
got_rate="$(probe stream=sample_rate)"
got_channels="$(probe stream=channels)"
got_bitrate="$(probe stream=bit_rate)"
got_duration="$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$file")"

fail=0
check() { if [ "$2" != "$3" ]; then echo "  ✗ $1: $3 (esperado $2)"; fail=1; fi; }

check codec mp3 "$codec"
[ "$rate" != "-" ] && check sampleRate "$rate" "$got_rate"
[ "$channels" != "-" ] && check channels "$channels" "$got_channels"
check bitrate "$((kbps * 1000))" "$got_bitrate"

# Un frame MPEG-1 Layer III = 1152 muestras.
tolerance="$(awk -v r="$got_rate" 'BEGIN { printf "%.6f", 1152 / r }')"
if ! awk -v a="$got_duration" -v b="$duration_ms" -v t="$tolerance" 'BEGIN { d = a - b / 1000; if (d < 0) d = -d; exit !(d <= t) }'; then
  echo "  ✗ duración: ${got_duration}s (esperado $((duration_ms))ms ±${tolerance}s)"
  fail=1
fi

if [ "$fail" = 0 ]; then
  echo "✓ $(basename "$file"): $got_rate Hz, $got_channels ch, $((got_bitrate / 1000)) kbps, ${got_duration}s"
else
  echo "✗ $(basename "$file")"
fi
exit "$fail"
