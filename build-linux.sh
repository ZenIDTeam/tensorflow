#!/bin/bash
# Builds the TFLite C API shared library with XNNPACK (libtensorflowlite_c.so) for Linux and packs it for ZenID:
# out-linux/tflite-<version>-linux-<arch>.tar.gz with lib/libtensorflowlite_c.so and include/.
# The build image is Ubuntu 20.04, so the library needs glibc 2.31 or older. Run from the repository root:
#
#   docker build -t zenid-tflite-linux -f Dockerfile.linux .
#   docker run --rm -v "$PWD:/src" -v zenid-tflite-cache:/cache -w /src zenid-tflite-linux ./build-linux.sh [x86_64] [aarch64]
#
# Default architectures: x86_64 aarch64 (cross-compiled). The build configs are in .bazelrc (zenid_linux_<arch>).
set -euo pipefail

VERSION=2.19.1
TARGET=//tensorflow/lite/c:tensorflowlite_c
OUT=$PWD/out-linux

# include/ = headers under tensorflow/lite and tensorflow/compiler/mlir/lite (the C API includes them),
# flatc-generated headers, and the flatbuffers headers.
make_include() {  # make_include <output base> <bazel-bin> <include dir>
  mkdir -p "$3/flatbuffers"
  find tensorflow/lite tensorflow/compiler/mlir/lite -name '*.h' -exec cp --parents {} "$3/" \;
  (cd "$2" && find tensorflow/lite tensorflow/compiler/mlir/lite -name '*_generated.h' -exec cp -n --parents {} "$3/" \; 2>/dev/null || true)
  cp -r "$1/external/flatbuffers/include/flatbuffers/." "$3/flatbuffers/"
}

build_arch() {
  local arch=$1 ob bin name opts
  case $arch in x86_64|aarch64) ;; *) echo "unknown architecture $arch" >&2; exit 1 ;; esac
  ob=/cache/ob/$VERSION-linux-$arch
  opts=(-c opt --config="zenid_linux_$arch" --repository_cache=/cache/repo --repo_env=TF_PYTHON_VERSION=3.10 --repo_env=HERMETIC_PYTHON_VERSION=3.10)
  bazel --output_base="$ob" build "${opts[@]}" "$TARGET"
  bin=$(bazel --output_base="$ob" info "${opts[@]}" bazel-bin 2>/dev/null)

  name=tflite-$VERSION-linux-$arch
  rm -rf /tmp/pack && mkdir -p "/tmp/pack/$name/lib"
  cp "$bin/tensorflow/lite/c/libtensorflowlite_c.so" "/tmp/pack/$name/lib/"
  make_include "$ob" "$bin" "/tmp/pack/$name/include"
  mkdir -p "$OUT"
  tar czf "$OUT/$name.tar.gz" -C /tmp/pack "$name"
  (cd "$OUT" && md5sum "$name.tar.gz")
}

archs=("$@"); [ ${#archs[@]} -gt 0 ] || archs=(x86_64 aarch64)
for a in "${archs[@]}"; do build_arch "$a"; done
