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

# ffprobe cuenta los frames enteros: no descuenta el retardo del encoder (1057 muestras) ni el
# relleno del último frame (< 1152), porque no aplica el gapless del tag `a2m`. Así que
# 0 ≤ ffprobe − PCM ≤ (1057 + 1152) / tasa, + 1 ms porque durationMs es un entero truncado.
max_extra="$(awk -v r="$got_rate" 'BEGIN { printf "%.6f", (1057 + 1152) / r + 0.001 }')"
if ! awk -v a="$got_duration" -v b="$duration_ms" -v m="$max_extra" 'BEGIN { d = a - b / 1000; exit !(d >= -0.001 && d <= m) }'; then
  echo "  ✗ duración: ${got_duration}s (PCM ${duration_ms}ms; extra permitido 0–${max_extra}s)"
  fail=1
fi

# Decodificación completa con FFmpeg: ningún aviso ni error.
warnings="$(ffmpeg -hide_banner -v warning -i "$file" -f null - 2>&1 | head -3)"
if [ -n "$warnings" ]; then
  echo "  ✗ ffmpeg: $warnings"
  fail=1
fi

if [ "$fail" = 0 ]; then
  echo "✓ $(basename "$file"): $got_rate Hz, $got_channels ch, $((got_bitrate / 1000)) kbps, ${got_duration}s"
else
  echo "✗ $(basename "$file")"
fi
exit "$fail"
