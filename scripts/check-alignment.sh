#!/usr/bin/env bash
# Comprueba que los .so de android/src/main/jniLibs tienen los segmentos LOAD alineados a 16 KB
# (requisito de Google Play para Android 15+). Usa llvm-readelf del NDK.
#
# Uso: scripts/check-alignment.sh   (ANDROID_NDK_HOME o ANDROID_HOME/ndk/<versión>)
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
libs="$root/android/src/main/jniLibs"
page=16384

ndk="${ANDROID_NDK_HOME:-${ANDROID_NDK_LATEST_HOME:-}}"
if [ -z "$ndk" ] && [ -n "${ANDROID_HOME:-}" ]; then
  ndk="$(ls -d "$ANDROID_HOME"/ndk/* 2>/dev/null | sort -V | tail -1 || true)"
fi
readelf="$(ls "$ndk"/toolchains/llvm/prebuilt/*/bin/llvm-readelf* 2>/dev/null | head -1 || true)"
[ -n "$readelf" ] || readelf="$(command -v llvm-readelf || true)"
if [ -z "$readelf" ]; then
  echo "No se encuentra llvm-readelf (define ANDROID_NDK_HOME)" >&2
  exit 2
fi

shopt -s nullglob
sos=("$libs"/*/libaudio2mp3.so)
if [ ${#sos[@]} -eq 0 ]; then
  echo "No hay binarios en $libs (ejecuta scripts/fetch-core.sh)" >&2
  exit 1
fi

failed=0
for so in "${sos[@]}"; do
  abi="$(basename "$(dirname "$so")")"
  bad=""
  for align in $("$readelf" -lW "$so" | awk '$1 == "LOAD" { print $NF }'); do
    if (( align < page )); then bad="$bad $align"; fi
  done
  if [ -n "$bad" ]; then
    echo "✗ $abi: segmentos LOAD sin alinear a 16 KB:$bad"
    failed=1
  else
    echo "✓ $abi: alineado a 16 KB"
  fi
done
exit "$failed"
