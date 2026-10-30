#!/bin/bash
# Builds Vendor/KanalFFmpeg.xcframework: a minimal FFmpeg plus Remux/, the
# repackager that lets AirPlay carry films the system player cannot open.
#
# Minimal on purpose — Matroska/MP4/AVI/TS in, HLS fragmented MP4 out, audio
# decoders for what films carry and one AAC encoder. A few megabytes, against
# tens for a general-purpose build. LGPL only: no --enable-gpl, no nonfree.
#
# Shipped as a dynamic framework so the LGPL relinking terms are met the same
# way as VLCKit's, and so that only `kanal_remux_*` is exported: the FFmpeg
# inside never meets the copy VLCKit carries.
#
#   ./Scripts/build-ffmpeg.sh            iPhone + simulator (+ macOS for tests)
#
# Vendor/ is gitignored; a fresh clone runs this once, like fetch-vlc.sh.
set -euo pipefail

VERSION="7.1.1"
SHA256="733984395e0dbbe5c046abda2dc49a5544e7e0e1e2366bba849222ae9e3a03b1"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/Vendor/KanalFFmpeg.xcframework"
# FFmpeg's configure cannot cope with a space in its path, and this
# repository lives under one ("IPTV "), so the build happens elsewhere.
WORK="${KANAL_FFMPEG_WORK:-$HOME/Library/Caches/kanal-ffmpeg}"
MIN_IOS="26.0"
MIN_MAC="26.0"

mkdir -p "$WORK"
cd "$WORK"

if [ ! -d "ffmpeg-$VERSION" ]; then
  curl -fsSL -o "ffmpeg-$VERSION.tar.xz" "https://ffmpeg.org/releases/ffmpeg-$VERSION.tar.xz"
  echo "$SHA256  ffmpeg-$VERSION.tar.xz" | shasum -a 256 -c -
  tar xf "ffmpeg-$VERSION.tar.xz"
fi
SRC="$WORK/ffmpeg-$VERSION"

CONFIGURE_FLAGS=(
  --disable-everything --disable-programs --disable-doc --disable-debug
  --disable-avdevice --disable-avfilter --disable-swscale --disable-postproc
  --disable-iconv --disable-xlib --disable-sdl2 --disable-audiotoolbox
  --disable-videotoolbox --disable-appkit --disable-avfoundation --disable-coreimage
  --disable-securetransport --disable-libxcb --disable-lzma --disable-bzlib
  --enable-static --disable-shared --enable-pic
  --enable-zlib
  --enable-network
  --enable-protocol=file,http,tcp
  --enable-demuxer=matroska,mov,avi,mpegts,flv
  --enable-muxer=hls,mp4,mov
  --enable-parser=h264,hevc,aac,ac3,dca,mpegaudio,opus,vorbis,flac
  --enable-bsf=extract_extradata,aac_adtstoasc
  --enable-decoder=ac3,eac3,dca,mp2,mp3,mp3float,opus,vorbis,flac,truehd,pcm_s16le,pcm_s24le,aac
  --enable-encoder=aac
  --enable-swresample
)

build() {
  local name="$1" sdk="$2" target="$3"
  local prefix="$WORK/install-$name"
  [ -f "$prefix/lib/libavformat.a" ] && { echo "$name: FFmpeg already built"; return; }
  local sysroot cc
  sysroot="$(xcrun --sdk "$sdk" --show-sdk-path)"
  cc="$(xcrun --sdk "$sdk" -f clang)"
  rm -rf "$WORK/obj-$name" && mkdir -p "$WORK/obj-$name"
  (
    cd "$WORK/obj-$name"
    "$SRC/configure" "${CONFIGURE_FLAGS[@]}" \
      --prefix="$prefix" --enable-cross-compile --target-os=darwin --arch=arm64 \
      --cc="$cc" --sysroot="$sysroot" \
      --extra-cflags="-target $target -fvisibility=hidden" \
      --extra-ldflags="-target $target" > configure.log
    make -j"$(sysctl -n hw.ncpu)" > make.log 2>&1
    make install > /dev/null
  )
}

# Links FFmpeg and the repackager into one dylib inside a framework bundle.
package() {
  local name="$1" sdk="$2" target="$3" kind="$4"
  local prefix="$WORK/install-$name"
  local fw="$WORK/fw-$name/KanalFFmpeg.framework"
  local sysroot cc
  sysroot="$(xcrun --sdk "$sdk" --show-sdk-path)"
  cc="$(xcrun --sdk "$sdk" -f clang)"
  rm -rf "$WORK/fw-$name" && mkdir -p "$fw/Headers" "$fw/Modules"

  local binary="$fw/KanalFFmpeg" plist="$fw/Info.plist" install_name="@rpath/KanalFFmpeg.framework/KanalFFmpeg"
  if [ "$kind" = "macos" ]; then
    mkdir -p "$fw/Versions/A/Headers" "$fw/Versions/A/Modules" "$fw/Versions/A/Resources"
    rm -rf "$fw/Headers" "$fw/Modules"
    binary="$fw/Versions/A/KanalFFmpeg"
    plist="$fw/Versions/A/Resources/Info.plist"
    install_name="@rpath/KanalFFmpeg.framework/Versions/A/KanalFFmpeg"
  fi

  "$cc" -target "$target" -isysroot "$sysroot" -O2 -fvisibility=hidden \
    -I"$prefix/include" -I"$ROOT/Remux/include" \
    -c "$ROOT/Remux/kanal_remux.c" -o "$WORK/kanal_remux-$name.o"
  "$cc" -target "$target" -isysroot "$sysroot" -dynamiclib \
    -install_name "$install_name" \
    -Wl,-exported_symbol,_kanal_remux_run \
    "$WORK/kanal_remux-$name.o" \
    "$prefix/lib/libavformat.a" "$prefix/lib/libavcodec.a" \
    "$prefix/lib/libswresample.a" "$prefix/lib/libavutil.a" \
    -lz -framework CoreFoundation -framework Security \
    -o "$binary"

  local headers="$fw/Headers" modules="$fw/Modules"
  if [ "$kind" = "macos" ]; then
    headers="$fw/Versions/A/Headers"; modules="$fw/Versions/A/Modules"
  fi
  cp "$ROOT/Remux/include/kanal_remux.h" "$headers/"
  cat > "$modules/module.modulemap" <<'MAP'
framework module KanalFFmpeg {
  header "kanal_remux.h"
  export *
}
MAP
  cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key><string>KanalFFmpeg</string>
	<key>CFBundleIdentifier</key><string>com.bomann.kanal.ffmpeg</string>
	<key>CFBundleName</key><string>KanalFFmpeg</string>
	<key>CFBundlePackageType</key><string>FMWK</string>
	<key>CFBundleShortVersionString</key><string>$VERSION</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
	<key>MinimumOSVersion</key><string>$MIN_IOS</string>
</dict>
</plist>
PLIST
  if [ "$kind" = "macos" ]; then
    ln -sfn A "$fw/Versions/Current"
    ln -sfn Versions/Current/KanalFFmpeg "$fw/KanalFFmpeg"
    ln -sfn Versions/Current/Headers "$fw/Headers"
    ln -sfn Versions/Current/Modules "$fw/Modules"
    ln -sfn Versions/Current/Resources "$fw/Resources"
  fi
}

build ios iphoneos "arm64-apple-ios$MIN_IOS"
build sim iphonesimulator "arm64-apple-ios$MIN_IOS-simulator"
build mac macosx "arm64-apple-macos$MIN_MAC"
package ios iphoneos "arm64-apple-ios$MIN_IOS" ios
package sim iphonesimulator "arm64-apple-ios$MIN_IOS-simulator" ios
package mac macosx "arm64-apple-macos$MIN_MAC" macos

rm -rf "$OUT"
xcodebuild -create-xcframework \
  -framework "$WORK/fw-ios/KanalFFmpeg.framework" \
  -framework "$WORK/fw-sim/KanalFFmpeg.framework" \
  -framework "$WORK/fw-mac/KanalFFmpeg.framework" \
  -output "$OUT" > /dev/null
du -sh "$WORK/fw-ios/KanalFFmpeg.framework/KanalFFmpeg"
echo "Built $OUT"
