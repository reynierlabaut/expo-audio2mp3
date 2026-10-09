#!/usr/bin/env bash
# Genera la matriz de fixtures de integración (spec §10) en fixtures/out/ con ffmpeg.
# ffmpeg es solo una herramienta de desarrollo: no forma parte del paquete.
#
# Uso: scripts/make-fixtures.sh [segundos]     (por defecto 10)
# Archivos largos (10 s, 1 min, 10 min, 30 min, 1 h): LONG=1 scripts/make-fixtures.sh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/fixtures/out"
secs="${1:-10}"
mkdir -p "$out"
cd "$out"

ff() { ffmpeg -hide_banner -loglevel error -y "$@"; }
has_encoder() { ffmpeg -hide_banner -encoders 2>/dev/null | grep -q " $1 "; }

video=(-f lavfi -i "testsrc=size=320x240:rate=25:duration=$secs")
tone() { echo "sine=frequency=440:sample_rate=$1:duration=$secs"; }

echo "→ fixtures en $out ($secs s)"

ff "${video[@]}" -f lavfi -i "$(tone 44100)" -ac 2 -c:v libx264 -pix_fmt yuv420p -c:a aac -ar 44100 -shortest mp4_h264_aac44_stereo.mp4
ff "${video[@]}" -f lavfi -i "$(tone 48000)" -ac 2 -c:v libx264 -pix_fmt yuv420p -c:a aac -ar 48000 -shortest mp4_aac48_stereo.mp4
if has_encoder libfdk_aac; then
  ff "${video[@]}" -f lavfi -i "$(tone 44100)" -ac 2 -c:v libx264 -pix_fmt yuv420p -c:a libfdk_aac -profile:a aac_he -shortest mp4_he_aac.mp4
else
  echo "• mp4_he_aac.mp4 omitido: ffmpeg sin libfdk_aac (añádelo a mano)"
fi
ff "${video[@]}" -f lavfi -i "$(tone 44100)" -ac 2 -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest -f mov mov_iphone.mov
ff "${video[@]}" -f lavfi -i "$(tone 48000)" -ac 6 -channel_layout 5.1 -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest mp4_aac_5_1.mp4
ff "${video[@]}" -f lavfi -i "$(tone 48000)" -ac 2 -c:v libvpx-vp9 -b:v 200k -c:a libopus -shortest webm_opus48.webm
ff -f lavfi -i "$(tone 44100)" -ac 2 -c:a aac m4a_aac.m4a
ff -f lavfi -i "$(tone 44100)" -ac 2 -c:a libmp3lame -b:a 128k mp3_128.mp3
ff -f lavfi -i "$(tone 16000)" -ac 1 -c:a pcm_s16le wav_16k_mono.wav
ff -f lavfi -i "$(tone 96000)" -ac 2 -c:a flac -sample_fmt s32 flac_96k.flac
ff "${video[@]}" -an -c:v libx264 -pix_fmt yuv420p video_sin_audio.mp4
printf 'esto no es un vídeo\n%.0s' $(seq 1 200) > corrupto.mp4

if [ "${LONG:-0}" = 1 ]; then
  for d in 10 60 600 1800 3600; do
    ff -f lavfi -i "testsrc=size=160x120:rate=10:duration=$d" -f lavfi -i "sine=frequency=440:sample_rate=44100:duration=$d" \
      -ac 2 -c:v libx264 -preset ultrafast -pix_fmt yuv420p -c:a aac -shortest "largo_${d}s.mp4"
  done
fi

cp "$root/fixtures/expected.tsv" "$out/expected.tsv"
echo "✓ listo. Android: scripts/run-fixtures-android.sh"
