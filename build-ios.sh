#!/bin/bash
# Builds TFLite (C API + XNNPACK delegate) as a static TensorFlowLiteC.xcframework for the ZenID iOS SDK and packs
# out-ios/tflite-<version>-ios.zip: TensorFlowLiteC.xcframework (arm64 device, arm64 + x86_64 simulator, plain
# static libraries) and include/ (TFLite and flatbuffers headers). Run on macOS with Xcode and bazel or bazelisk
# on PATH, from the repository root:
#
#   ./build-ios.sh
#
# TFLITE_CACHE (default ~/tflite-build-cache) holds the Bazel output base and repository cache, so reruns are
# incremental.
set -euo pipefail

VERSION=2.19.1
TARGET=//tensorflow/lite/ios:TensorFlowLiteC_static_framework
CACHE=${TFLITE_CACHE:-$HOME/tflite-build-cache}
OB=$CACHE/ob/$VERSION-ios
OUT=$PWD/out-ios
STAGE=$OUT/stage
OPTS=(-c opt --define=tflite_with_xnnpack=true --repository_cache="$CACHE/repo"
      --repo_env=TF_PYTHON_VERSION=3.10 --repo_env=HERMETIC_PYTHON_VERSION=3.10)
# Library names inside the xcframework, the same as in the 2.15.1 package.
DEVICE_LIB=TensorFlowLiteC_static_framework-arm64-apple-ios12.0-fl.a
SIM_LIB=TensorFlowLiteC_ios_sim.a

export BAZELISK_HOME=$CACHE/bazelisk
# Bazel 6.5.0 (.bazelversion) builds wrapped_clang without LC_UUID, which dyld on macOS 26 refuses to load.
export USE_BAZEL_VERSION=${USE_BAZEL_VERSION:-6.6.0}
bazel() { command bazel --output_base="$OB" "$@"; }

# Non-interactive configure; TF_CONFIGURE_IOS links the BUILD.apple files as BUILD.
TF_CONFIGURE_IOS=1 TF_NEED_CUDA=0 TF_NEED_ROCM=0 TF_SET_ANDROID_WORKSPACE=0 CC_OPT_FLAGS=-Wno-sign-compare \
  USE_DEFAULT_PYTHON_LIB_PATH=1 ./configure </dev/null

rm -rf "$STAGE"
mkdir -p "$STAGE/lib" "$STAGE/pack/include/flatbuffers"
for arch in ios_arm64 ios_sim_arm64 ios_x86_64; do
  bazel build "${OPTS[@]}" --config=$arch "$TARGET"
  unzip -p bazel-bin/tensorflow/lite/ios/TensorFlowLiteC_static_framework.zip TensorFlowLiteC.framework/TensorFlowLiteC \
    > "$STAGE/lib/$arch.a"
  lipo -info "$STAGE/lib/$arch.a"
done

mkdir -p "$STAGE/device" "$STAGE/sim"
cp "$STAGE/lib/ios_arm64.a" "$STAGE/device/$DEVICE_LIB"
lipo -create "$STAGE/lib/ios_sim_arm64.a" "$STAGE/lib/ios_x86_64.a" -output "$STAGE/sim/$SIM_LIB"
xcodebuild -create-xcframework -library "$STAGE/sim/$SIM_LIB" -library "$STAGE/device/$DEVICE_LIB" \
  -output "$STAGE/pack/TensorFlowLiteC.xcframework"

# include/ = headers under tensorflow/lite and tensorflow/compiler/mlir/lite (the C API includes them),
# flatc-generated headers, and the flatbuffers headers.
find tensorflow/lite tensorflow/compiler/mlir/lite -name '*.h' -print0 | tar --null -cf - -T - | tar -xf - -C "$STAGE/pack/include"
(cd bazel-bin/ &&{ find tensorflow/lite tensorflow/compiler/mlir/lite -name '*_generated.h' -print0 2>/dev/null || true; } \
  | tar --null -cf - -T -) | tar -xkf - -C "$STAGE/pack/include"
cp -R "$OB/external/flatbuffers/include/flatbuffers/." "$STAGE/pack/include/flatbuffers/"

zip_name=tflite-$VERSION-ios.zip
rm -f "$OUT/$zip_name"
(cd "$STAGE/pack" && zip -qrX "$OUT/$zip_name" TensorFlowLiteC.xcframework include -x '*.DS_Store')
bazel shutdown
echo "$(md5 -q "$OUT/$zip_name")  $OUT/$zip_name"
