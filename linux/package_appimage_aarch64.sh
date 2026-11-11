#!/bin/bash
# Finish an ARM64 AppImage prepared by make_appimage_aarch64.sh. On x86_64 this runs the
# static AArch64 appimagetool through qemu-user; on native AArch64 it runs directly.
set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/env.sh"
C="$W/linux/appimage/cache"; A="$W/linux/appimage/AppDir"
OUT="$W/linux/dist/Metroid_Dread-aarch64.AppImage"
TOOL="$C/appimagetool"
[ -x "$TOOL" ] && [ -d "$A" ] || { echo "Run make_appimage_aarch64.sh first to prepare the AppDir." >&2; exit 1; }
need mksquashfs "squashfs-tools"
if [ "$(uname -m)" = aarch64 ]; then
  ARCH=aarch64 "$TOOL" --appimage-extract-and-run --no-appstream "$A" "$OUT"
else
  need qemu-aarch64-static "qemu-user-static (to run the AArch64 appimagetool)"
  ARCH=aarch64 qemu-aarch64-static "$TOOL" --no-appstream "$A" "$OUT"
fi
{ cat "$A/usr/share/metroid-dread/update.txt"
  printf 'package %s %s %s\n' "$(basename "$OUT")" "$(sha256sum "$OUT" | cut -d' ' -f1)" "$(stat -c %s "$OUT")"; } \
  > "$(dirname "$OUT")/update-linux.txt"
ls -lh "$OUT" "$(dirname "$OUT")/update-linux.txt"
cat "$(dirname "$OUT")/update-linux.txt"
