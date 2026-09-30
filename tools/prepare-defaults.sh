#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
avatar="${AVATAR_SOURCE:-assets/bg1/panding.JPG}"
artwork="${ARTWORK_SOURCE:-assets/bg2/bg2_6031.png}"

# A fresh checkout includes ready-to-use assets, but not the local image library.
# Rebuild a default only when its optional source exists.
prepare_image() {
  local source="$1" output="$2" width="$3" height="$4"
  if [ -f "$source" ]; then
    if [ ! -f "$output" ] || [ "$source" -nt "$output" ] || [ tools/prepare-defaults.swift -nt "$output" ]; then
      mkdir -p .build/module-cache
      if [ ! -x .build/prepare-defaults ] || [ tools/prepare-defaults.swift -nt .build/prepare-defaults ]; then
        swiftc -O -module-cache-path .build/module-cache tools/prepare-defaults.swift -o .build/prepare-defaults
      fi
      .build/prepare-defaults "$source" "$output" "$width" "$height"
    fi
  elif [ ! -f "$output" ]; then
    printf 'Missing %s. Set AVATAR_SOURCE / ARTWORK_SOURCE to your source images.\n' "$output" >&2
    exit 1
  fi
}
if [ -n "${AVATAR_SOURCE:-}" ] && [ ! -f "$avatar" ]; then
  printf 'AVATAR_SOURCE does not exist: %s\n' "$avatar" >&2; exit 1
fi
if [ -n "${ARTWORK_SOURCE:-}" ] && [ ! -f "$artwork" ]; then
  printf 'ARTWORK_SOURCE does not exist: %s\n' "$artwork" >&2; exit 1
fi
prepare_image "$avatar" assets/avatar.jpg 512 512
prepare_image "$artwork" assets/artwork.jpg 1536 1024
if [ ! -f assets/contours.js ] || [ assets/artwork.jpg -nt assets/contours.js ] || [ tools/trace-contours.swift -nt assets/contours.js ]; then
  mkdir -p .build/module-cache
  swiftc -O -module-cache-path .build/module-cache tools/trace-contours.swift -o .build/trace-contours -framework Vision
  .build/trace-contours assets/artwork.jpg assets/contours.js
fi
