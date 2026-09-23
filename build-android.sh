#!/bin/bash
# Builds the TFLite C API (with XNNPACK) as libtensorflowlite_c.so for Android (API 21, NDK r27b) and packs
# it for ZenID: out-android/tflite-<version>-android-api-21-ndk-27b-16kb.zip (lib/<abi>/*.so + include/).
# Run from the repository root:
#
#   docker build -t zenid-tflite-android -f Dockerfile.android .
#   docker run --rm -v "$PWD:/src" -v zenid-tflite-cache:/cache -w /src zenid-tflite-android ./build-android.sh [abi...]
#
# Default ABIs: armeabi-v7a arm64-v8a x86 x86_64. The zip contains all ABIs built so far.
# The libraries link libunwind statically. 64-bit ABIs use 16 KB page alignment (Android 15+ requirement).
set -euo pipefail

VERSION=2.19.1
API=21
TARGET=//tensorflow/lite/c:tensorflowlite_c
OUT=$PWD/out-android
STAGE=/cache/stage/$VERSION-android
OB=/cache/ob/$VERSION-android
TOOLS=$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin

# The android_configure repository rule reads these instead of the output of ./configure.
OPTS=(-c opt --repository_cache=/cache/repo --define=tflite_with_xnnpack=true --linkopt=-lunwind
  --repo_env=TF_PYTHON_VERSION=3.10 --repo_env=HERMETIC_PYTHON_VERSION=3.10
  --repo_env=ANDROID_NDK_HOME="$ANDROID_NDK_HOME" --repo_env=ANDROID_NDK_VERSION=27 --repo_env=ANDROID_NDK_API_LEVEL=$API
  --repo_env=ANDROID_SDK_HOME="$ANDROID_SDK_HOME" --repo_env=ANDROID_SDK_API_LEVEL=$API
  --repo_env=ANDROID_BUILD_TOOLS_VERSION=30.0.2)

config() {
  case $1 in
    armeabi-v7a) echo android_arm ;;
    arm64-v8a) echo android_arm64 ;;
    x86) echo android_x86 ;;
    x86_64) echo android_x86_64 ;;
    *) echo "unknown ABI $1" >&2; exit 1 ;;
  esac
}

build_abi() {
  local abi=$1 opts so
  opts=("${OPTS[@]}" --config="$(config "$abi")")
  case $abi in arm64-v8a|x86_64) opts+=(--linkopt=-Wl,-z,max-page-size=16384) ;; esac
  bazel --output_base="$OB" build "${opts[@]}" "$TARGET"
  so=$STAGE/lib/$abi/libtensorflowlite_c.so
  mkdir -p "$(dirname "$so")"
  cp "$(bazel --output_base="$OB" info "${opts[@]}" bazel-bin 2>/dev/null)/tensorflow/lite/c/libtensorflowlite_c.so" "$so"
  chmod u+w "$so"
  "$TOOLS/llvm-readelf" -lW "$so" | grep LOAD
  "$TOOLS/llvm-readelf" -d "$so" | grep NEEDED
}

# include/ = headers under tensorflow/lite and tensorflow/compiler/mlir/lite (the C API includes them),
# flatc-generated headers, and the flatbuffers headers.
make_include() {
  local bin
  bin=$(ls -d "$OB"/execroot/org_tensorflow/bazel-out/*-opt/bin | head -1)
  rm -rf "$STAGE/include"
  mkdir -p "$STAGE/include/flatbuffers"
  find tensorflow/lite tensorflow/compiler/mlir/lite -name '*.h' -exec cp --parents {} "$STAGE/include/" \;
  (cd "$bin" && find tensorflow/lite tensorflow/compiler/mlir/lite -name '*_generated.h' -exec cp -n --parents {} "$STAGE/include/" \; 2>/dev/null || true)
  cp -r "$OB/external/flatbuffers/include/flatbuffers/." "$STAGE/include/flatbuffers/"
}

abis=("$@"); [ ${#abis[@]} -gt 0 ] || abis=(armeabi-v7a arm64-v8a x86 x86_64)
for abi in "${abis[@]}"; do build_abi "$abi"; done

make_include
mkdir -p "$OUT"
zip=tflite-$VERSION-android-api-$API-ndk-27b-16kb.zip
rm -f "$OUT/$zip"
(cd "$STAGE" && zip -qr "$OUT/$zip" include lib)
(cd "$OUT" && md5sum "$zip")
