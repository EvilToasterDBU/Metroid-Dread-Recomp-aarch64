#!/bin/bash
# Linux build: the AppImage, one file that sets up, configures and runs the game like the Windows EXE. Inside: the runtime
# with the Play / setup screens, the recompiler (the Python scripts, patches and RomFS manifest), a native AArch64 GCC
# from the build host and Python
# (python-build-standalone), so the player needs none of them. No game files inside.
# The game is installed in ~/.local/share/MetroidDreadRecomp (METROID_DREAD_HOME moves it), see appimage/AppRun.
# Downloads are checked against the SHA-256 below and kept in linux/appimage/cache.
# Output: linux/dist/Metroid_Dread-aarch64.AppImage, and linux/dist/update-linux.txt for the in-game updater
# (dread_ui/fe_update_linux.cpp). VERSION=x.y.z names the release (default: 0.0.0-dev); publish both files as release
# assets of tag vVERSION (TAG=... otherwise).
set -e -o pipefail
source "$(dirname "$(readlink -f "$0")")/env.sh"
need curl "curl"; need "$PY" "python3"
need desktop-file-validate "desktop-file-utils (appimagetool makes no AppImage without it, and says nothing)"
need file "file (appimagetool needs it)"
C="$W/linux/appimage/cache"; A="$W/linux/appimage/AppDir"; R="$A/usr/share/metroid-dread/recompiler"
OUT="$W/linux/dist/Metroid_Dread-aarch64.AppImage"
PY_URL=https://github.com/astral-sh/python-build-standalone/releases/download/20261009/cpython-3.12.15%2B20261009-aarch64-unknown-linux-gnu-install_only_stripped.tar.gz
PY_SHA=2e1ba0e7f22e01c534caebf7f09e7820322bc0d055271d3434af671e8400f96f
TOOL_URL=https://github.com/AppImage/appimagetool/releases/download/1.9.1/appimagetool-aarch64.AppImage
TOOL_SHA=f0837e7448a0c1e4e650a93bb3e85802546e60654ef287576f46c71c126a9158

fetch() {   # fetch FILE URL [SHA256]
  local f="$C/$1"
  if [ -n "$3" ] && [ -f "$f" ] && ! echo "$3  $f" | sha256sum -c --quiet - 2>/dev/null; then rm -f "$f"; fi
  [ -f "$f" ] || { echo "downloading $1"; curl -fL --retry 3 -o "$f.part" "$2" && mv "$f.part" "$f"; }
  [ -z "$3" ] || echo "$3  $f" | sha256sum -c --quiet - || { echo "error: $1 does not match its SHA-256" >&2; exit 1; }
}
mkdir -p "$C"
fetch python.tar.gz "$PY_URL" "$PY_SHA"
fetch appimagetool "$TOOL_URL" "$TOOL_SHA"
chmod +x "$C/appimagetool"

# the runtime as released on Windows (SWR_RELEASE: no frame generation, no DLSS notes), with the front end
# renderer=vulkan_native: ScarletNX's renderer (GPL-3.0, its source is in runtime/snxvk), built without DLSS
RUNTIME_MARK="$RUNTIME.release.sha256"
RUNTIME_HASH=$(sha256sum "$RUNTIME" 2>/dev/null | cut -d' ' -f1 || true)
if [ ! -x "$RUNTIME" ] || [ "$(cat "$RUNTIME_MARK" 2>/dev/null || true)" != "$RUNTIME_HASH" ]; then
  need "$(command -v glslang || command -v glslangValidator || echo glslang)" "glslang-tools"
  "$PY" "$W/work-profiler/build_snxvk2.py" | tail -1
  SWR_RELEASE=1 bash "$W/linux/setup_and_build_runtime.sh" > /dev/null
  RUNTIME_HASH=$(sha256sum "$RUNTIME" | cut -d' ' -f1)
  printf '%s\n' "$RUNTIME_HASH" > "$RUNTIME_MARK"
fi
grep -qa "FIRST-TIME SETUP" "$RUNTIME" || { echo "error: the runtime was built without the front end (SWR_NO_LINUX_FRONTEND?)" >&2; exit 1; }

rm -rf "$A"; mkdir -p "$A/usr/bin" "$R/dread" "$R/runtime" "$R/linux" "$A/usr/share/metroid-dread/licenses"
cp "$RUNTIME" "$A/usr/bin/metroid-dread"
cp "$W/dread/pipeline_recipes_shipped.bin" "$A/usr/share/metroid-dread/"   # Native Vulkan's pipeline list (AppRun)
# the recompiler, laid out as dread_setup.py expects it (as in the Windows release's recompiler folder)
cp "$W"/{switchrecomp,codegen,a64,nxloader,metroid_perf}.py "$W/dread/dread_setup.py" "$R/"
cp "$W/dread/dread_v210_patches.json" "$W/dread/romfs_v210.manifest" "$R/dread/"
cp "$W/runtime/cpu.h" "$W/runtime/cpu_helpers.c" "$R/runtime/"
cp "$W/linux/lx_compat.h" "$R/linux/"
LIC="$A/usr/share/metroid-dread/licenses"
cp "$W/LICENSE.txt" "$LIC/LICENSE-SwitchRecomp.txt"; cp "$W/NOTICE.txt" "$W/LICENSE-GPL-3.0.txt" "$LIC/"
cp "$W/third_party/imgui-1.92.5/LICENSE.txt" "$LIC/LICENSE-ImGui.txt"; cp "$W/runtime/vp9/LICENSE-libvpx.txt" "$LIC/"

# GCC: bundle a native AArch64 C compiler from this Ubuntu ARM64 build host. Bootlin's ARM64 toolchain is hosted on
# x86_64 and cannot run inside an ARM64 AppImage. Only GCC, binutils, headers, startup objects and their non-glibc
# shared libraries are copied; the target provides glibc (minimum 2.39, as for the runtime).
echo "bundling native GCC"
TRIPLE=$(gcc -dumpmachine); GCCVER=$(gcc -dumpversion)
[ "$TRIPLE" = aarch64-linux-gnu ] || { echo "error: expected native AArch64 GCC, got $TRIPLE" >&2; exit 1; }
SYSROOT="$R/gcc/sysroot"; GCC_LIB="/usr/lib/gcc/$TRIPLE/$GCCVER"; GCC_EXEC="/usr/libexec/gcc/$TRIPLE/$GCCVER"
mkdir -p "$R/gcc/bin" "$SYSROOT/usr/bin" "$SYSROOT/usr/lib/gcc/$TRIPLE" "$SYSROOT/usr/libexec/gcc/$TRIPLE" \
    "$SYSROOT/usr/lib/$TRIPLE" "$SYSROOT/usr/include" "$SYSROOT/lib/$TRIPLE"
cp -aL "$(command -v gcc-$GCCVER)" "$SYSROOT/usr/bin/"
cp -a "$GCC_LIB" "$SYSROOT/usr/lib/gcc/$TRIPLE/"
cp -a "$GCC_EXEC" "$SYSROOT/usr/libexec/gcc/$TRIPLE/"
rm -rf "$SYSROOT/usr/lib/gcc/$TRIPLE/$GCCVER"/{cc1plus,lto1,g++-mapper-server,plugin,install-tools} \
    "$SYSROOT/usr/include/c++"
rm -f "$SYSROOT/usr/lib/gcc/$TRIPLE/$GCCVER"/{libstdc++*,libgomp*,libquadmath*,libasan*,libtsan*,libubsan*,libatomic*}
rm -f "$SYSROOT/usr/libexec/gcc/$TRIPLE/$GCCVER"/{cc1plus,lto1,g++-mapper-server,lto-dump}
cp -aL "$(command -v as)" "$(command -v ld)" "$SYSROOT/usr/bin/"
cp -a /usr/include/. "$SYSROOT/usr/include/"
# The game module is a shared object linked with -lm and -ldl. Include the libc development linker scripts,
# startup objects and their glibc sonames as link-time inputs.
for name in crt1.o crti.o crtn.o libc.so libc_nonshared.a libm.so libm_nonshared.a libdl.a; do
  f=$(gcc -print-file-name="$name")
  [ -f "$f" ] && cp -a "$f" "$SYSROOT/usr/lib/$TRIPLE/"
done
cp -aL /lib/$TRIPLE/libc.so.6 /lib/$TRIPLE/libm.so.6 /lib/$TRIPLE/libmvec.so.1 /lib/$TRIPLE/libdl.so.2 /lib/$TRIPLE/libpthread.so.0 \
    /lib/$TRIPLE/libgcc_s.so.1 \
    /lib/$TRIPLE/ld-linux-aarch64.so.1 "$SYSROOT/lib/$TRIPLE/"
cp -aL /lib/ld-linux-aarch64.so.1 "$SYSROOT/lib/"
for pkg in "gcc-$GCCVER-base" binutils libc6-dev linux-libc-dev; do
  doc="/usr/share/doc/$pkg/copyright"
  [ ! -f "$doc" ] || cp "$doc" "$LIC/LICENSE-$pkg.txt"
done
{
  echo "Native AArch64 compiler package: $(gcc --version | head -1)"
  echo "Binutils package: $(ld --version | head -1)"
  echo "System C library: $(ldd --version | head -1)"
  echo "Compiler source: https://launchpad.net/ubuntu/+source/gcc-$GCCVER"
  echo "Binutils source: https://launchpad.net/ubuntu/+source/binutils"
  echo "Glibc source: https://launchpad.net/ubuntu/+source/glibc"
  echo "Linux UAPI headers: https://launchpad.net/ubuntu/+source/linux"
} > "$LIC/ARM64-toolchain-sources.txt"
# Runtime libraries used by cc1, collect2, as and ld; libc and the dynamic loader stay provided by the target OS.
for exe in "$(command -v gcc-$GCCVER)" "$GCC_EXEC/cc1" "$GCC_EXEC/collect2" /usr/bin/as /usr/bin/ld; do
  ldd "$exe" | awk '/=> \/.*\(/ {print $3} /^\// {print $1}'
done | sort -u | while read -r f; do
  case "$f" in */libc.so.*|*/libm.so.*|*/libdl.so.*|*/libpthread.so.*|*/ld-linux-aarch64.so.1) continue;; esac
  [ -f "$f" ] && cp -aL "$f" "$SYSROOT/usr/lib/$TRIPLE/$(basename "$f")"
done
cat > "$R/gcc/bin/gcc" <<'EOF'
#!/bin/sh
R="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
T="$R/gcc/sysroot"; VER=@GCCVER@
export GCC_EXEC_PREFIX="$T/usr/lib/gcc/"
export COMPILER_PATH="$T/usr/libexec/gcc/aarch64-linux-gnu/$VER:$T/usr/bin"
export LIBRARY_PATH="$T/usr/lib/gcc/aarch64-linux-gnu/$VER:$T/usr/lib/aarch64-linux-gnu"
export LD_LIBRARY_PATH="$T/usr/lib/aarch64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$T/usr/bin/gcc-$VER" --sysroot="$T" -B "$T/usr/lib/gcc/aarch64-linux-gnu/$VER/" -B "$T/usr/bin/" "$@"
EOF
sed -i "s/@GCCVER@/$GCCVER/" "$R/gcc/bin/gcc"
chmod +x "$R/gcc/bin/gcc"
# Python: the standard library dread_setup.py and SwitchRecomp use (no Tk, IDLE, tests, pip)
echo "unpacking Python"
tar -xzf "$C/python.tar.gz" -C "$R"
( cd "$R/python"
  rm -rf include share lib/pkgconfig lib/itcl* lib/tcl* lib/tk* lib/thread* lib/libtcl* lib/libtk*
  cd lib/python3.12 && rm -rf test idlelib tkinter turtledemo ensurepip lib2to3 pydoc_data site-packages/* lib-dynload/_tkinter* config-3.12-* )

# the toolchain must still build and link the game's C, and Python run the recompiler
GCC_BIN="$R/gcc/bin/gcc"; T=$(mktemp -d)
printf 'unsigned long GetEnvironmentVariableA(const char*,char*,unsigned long);\nint f(void){ char b[8]; return (int)GetEnvironmentVariableA("X",b,8); }\n' > "$T/t.c"
"$GCC_BIN" -O2 -fPIC -fvisibility=hidden -I "$R/runtime" -include "$R/linux/lx_compat.h" -c "$T/t.c" -o "$T/t.o"
"$GCC_BIN" -shared -o "$T/t.so" "$T/t.o" -lm -ldl
"$R/python/bin/python3" -I -c "import hashlib, json, zipfile, concurrent.futures, argparse, struct; import sys; sys.path.insert(0, '$R'); import switchrecomp"
rm -rf "$T" "$R/__pycache__"

# the updater's record of this build: version, release tag, and a hash over the recompiler (not GCC or Python), whose
# change means the game code must be rebuilt after an update
VERSION=${VERSION:-0.0.0-dev}; TAG=${TAG:-v$VERSION}
RHASH=$( cd "$R" && find . -path ./gcc -prune -o -path ./clang -prune -o -path ./python -prune -o -type f -print | LC_ALL=C sort | xargs -d '\n' sha256sum | sha256sum | cut -c1-64 )
printf 'version %s\ntag %s\nrecompiler %s\n' "$VERSION" "$TAG" "$RHASH" > "$A/usr/share/metroid-dread/update.txt"

# desktop entry, icon (the 256 px PNG inside runtime/app.ico) and AppRun
cp "$W/linux/appimage/AppRun" "$A/AppRun"; chmod +x "$A/AppRun"
cp "$W/linux/appimage/metroid-dread.desktop" "$A/"
"$PY" -I - "$W/runtime/app.ico" "$A/metroid-dread.png" <<'EOF'
import struct, sys
d = open(sys.argv[1], 'rb').read(); n = struct.unpack_from('<HHH', d)[2]
best = max((struct.unpack_from('<BBBBHHII', d, 6 + 16 * i) for i in range(n)), key=lambda e: e[0] or 256)
open(sys.argv[2], 'wb').write(d[best[7]:best[7] + best[6]])
EOF
ln -sf metroid-dread.png "$A/.DirIcon"

mkdir -p "$(dirname "$OUT")"
du -sh "$R/gcc" "$R/python" "$A"
if [ "${SWR_APPIMAGE_PREPARE_ONLY:-0}" = 1 ]; then
  echo "AppDir prepared at $A; on an x86_64 host finish it with: bash linux/package_appimage_aarch64.sh"
  exit 0
fi
ARCH=aarch64 "$C/appimagetool" --appimage-extract-and-run --no-appstream "$A" "$OUT"
ls -la "$OUT"
{ cat "$A/usr/share/metroid-dread/update.txt"
  printf 'package %s %s %s\n' "$(basename "$OUT")" "$(sha256sum "$OUT" | cut -c1-64)" "$(stat -c %s "$OUT")"; } > "$(dirname "$OUT")/update-linux.txt"
cat "$(dirname "$OUT")/update-linux.txt"
