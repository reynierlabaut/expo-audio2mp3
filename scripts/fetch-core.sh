#!/usr/bin/env bash
# Instala los binarios precompilados de audio2mp3-core fijados en core-version.json:
#   android: <zip>/jniLibs/<abi>/libaudio2mp3.so → android/src/main/jniLibs/<abi>/
#   ios:     <zip>/Audio2Mp3Core.xcframework     → ios/Audio2Mp3Core.xcframework
# Verifica el sha256 de cada artefacto antes de copiarlo.
#
# Uso:
#   scripts/fetch-core.sh                    descarga el release (gh, o curl + GITHUB_TOKEN)
#   scripts/fetch-core.sh --from <dir>       usa los zips de un directorio (p. ej. ../audio2mp3-core/dist)
#   scripts/fetch-core.sh --check            solo comprueba que lo instalado coincide (prepublishOnly)
#   --platform android|ios|all               por defecto: all
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

from=""
check=0
platforms="all"
while [ $# -gt 0 ]; do
  case "$1" in
    --from) from="$2"; shift 2 ;;
    --check) check=1; shift ;;
    --platform) platforms="$2"; shift 2 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "Argumento desconocido: $1" >&2; exit 2 ;;
  esac
done
[ "$platforms" = "all" ] && platforms="android ios"

field() { node -p "const c = require('./core-version.json'); String($1 ?? '')"; }

version="$(field c.version)"
repo="$(field c.repository)"
tag="$(field c.tag)"
cache="$root/.core-cache/$version"

sha256() {
  if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

unzip_to() {
  if command -v unzip >/dev/null; then unzip -q -o "$1" -d "$2"
  else tar -xf "$1" -C "$2"; fi
}

dest_of() {
  case "$1" in
    android) echo "android/src/main/jniLibs" ;;
    ios) echo "ios/Audio2Mp3Core.xcframework" ;;
  esac
}

# Sello con la versión y el sha256 instalados, para --check.
stamp_of() { echo "$(dest_of "$1")/.core-version"; }

download() {
  local file="$1" out="$2"
  if [ -n "$from" ]; then
    cp "$from/$file" "$out"
  elif command -v gh >/dev/null; then
    gh release download "$tag" --repo "$repo" --pattern "$file" --output "$out" --clobber
  elif [ -n "${GITHUB_TOKEN:-}" ]; then
    # Repo privado: la API de assets necesita el id del asset.
    local id
    id="$(curl -fsSL -H "Authorization: Bearer $GITHUB_TOKEN" \
      "https://api.github.com/repos/$repo/releases/tags/$tag" |
      node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{const a=JSON.parse(s).assets.find(a=>a.name===process.argv[1]);if(!a)process.exit(1);console.log(a.id)})" "$file")"
    curl -fsSL -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/octet-stream" \
      "https://api.github.com/repos/$repo/releases/assets/$id" -o "$out"
  else
    curl -fsSL "https://github.com/$repo/releases/download/$tag/$file" -o "$out"
  fi
}

failed=0
for platform in $platforms; do
  file="$(field "c.artifacts.$platform.file")"
  expected="$(field "c.artifacts.$platform.sha256")"
  dest="$(dest_of "$platform")"
  stamp="$(stamp_of "$platform")"

  if [ "$check" = 1 ]; then
    if [ -z "$expected" ]; then
      echo "✗ $platform: core-version.json no tiene sha256 (artefacto sin publicar)" >&2; failed=1; continue
    fi
    if [ "$(cat "$stamp" 2>/dev/null)" != "$version $expected" ]; then
      echo "✗ $platform: faltan los binarios $version o no coinciden. Ejecuta scripts/fetch-core.sh" >&2; failed=1; continue
    fi
    if [ "$platform" = android ]; then
      for abi in arm64-v8a armeabi-v7a x86_64; do
        [ -f "$dest/$abi/libaudio2mp3.so" ] || { echo "✗ android: falta $abi" >&2; failed=1; }
      done
    fi
    [ "$failed" = 0 ] && echo "✓ $platform: audio2mp3-core $version"
    continue
  fi

  if [ -z "$expected" ]; then
    echo "• $platform: sin artefacto publicado en core-version.json; se omite" >&2
    continue
  fi

  mkdir -p "$cache"
  zip="$cache/$file"
  if [ ! -f "$zip" ] || [ "$(sha256 "$zip")" != "$expected" ]; then
    echo "↓ $platform: $file"
    download "$file" "$zip"
  fi
  actual="$(sha256 "$zip")"
  if [ "$actual" != "$expected" ]; then
    rm -f "$zip"
    echo "✗ $platform: sha256 no coincide ($actual ≠ $expected)" >&2
    exit 1
  fi

  tmp="$(mktemp -d)"
  unzip_to "$zip" "$tmp"
  rm -rf "$dest"
  case "$platform" in
    android) mkdir -p "$dest" && cp -R "$tmp/jniLibs/." "$dest/" ;;
    ios) cp -R "$tmp/Audio2Mp3Core.xcframework" "$dest" ;;
  esac
  rm -rf "$tmp"
  echo "$version $expected" > "$stamp"
  echo "✓ $platform: audio2mp3-core $version → $dest"
done

exit "$failed"
