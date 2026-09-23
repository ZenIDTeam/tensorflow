#!/bin/bash
# Builds TFLite (C API + XNNPACK delegate) as static WebAssembly libraries with emscripten 4.0.13 and packs
# them for ZenID into out-wasm/tflite-<version>-wasm-emsdk-4.0.13.tar.gz: lib/libtflite_c.a (single thread),
# lib/libtflite_c-mt.a (pthreads) and lib/libtflite_c-mt-relaxed.a (pthreads, relaxed SIMD). Run from the repository root:
#
#   docker build -t zenid-tflite-wasm -f Dockerfile.wasm .
#   docker run --rm -v "$PWD:/src" -v zenid-tflite-cache:/cache -w /src zenid-tflite-wasm ./build-wasm.sh [st] [mt] [mt-relaxed]
#
# Default variants: st mt mt-relaxed. The build configs are in .bazelrc (wasm, wasm_mt, wasm_mt_relaxed).
set -euo pipefail

VERSION=2.19.1
TARGETS=(//tensorflow/lite/core/c:c_api //tensorflow/lite/delegates/xnnpack:xnnpack_delegate)
OUT=$PWD/out-wasm
STAGE=/cache/stage/$VERSION

config() {
  case $1 in
    st) echo wasm ;;
    mt) echo wasm_mt ;;
    mt-relaxed) echo wasm_mt_relaxed ;;
    *) echo "unknown variant $1" >&2; exit 1 ;;
  esac
}

lib_name() {
  case $1 in
    st) echo libtflite_c.a ;;
    mt) echo libtflite_c-mt.a ;;
    mt-relaxed) echo libtflite_c-mt-relaxed.a ;;
  esac
}

# One Bazel output base per variant: they share the wasm-opt output dir, so with one output base
# every switch between variants would rebuild everything.
output_base() { echo /cache/ob/$VERSION-$1; }

build_variant() {
  local v=$1 ob bin lib opts
  ob=$(output_base "$v")
  opts=(-c opt --config="$(config "$v")" --repository_cache=/cache/repo --repo_env=TF_PYTHON_VERSION=3.10 --repo_env=HERMETIC_PYTHON_VERSION=3.10)
  bazel --output_base="$ob" build "${opts[@]}" "${TARGETS[@]}"
  bin=$(bazel --output_base="$ob" info "${opts[@]}" bazel-bin 2>/dev/null)

  # Only the objects the current build graph compiles; stale objects under bazel-bin are left out.
  bazel --output_base="$ob" aquery "${opts[@]}" --output=text \
      "mnemonic('CppCompile', deps(${TARGETS[0]}) union deps(${TARGETS[1]}))" 2>/dev/null \
    | sed -n 's/^  Outputs: \[\(.*\)\]$/\1/p' | tr ',' '\n' | sed 's/^ *//' | grep '\.o$' \
    | sed "s|^|$ob/execroot/org_tensorflow/|" | grep "^$bin/" | sort > /tmp/objs.txt

  mkdir -p "$STAGE/lib"
  lib=$STAGE/lib/$(lib_name "$v")
  rm -f "$lib"   # emar q appends
  emar qsL "$lib" $(cat /tmp/objs.txt)
  echo "Checking for duplicate symbols..."
  emcc -o /tmp/check.o -r "$lib" -s LINKABLE
}

# include/ = headers under tensorflow/lite and tensorflow/compiler/mlir/lite (the C API includes them),
# flatc-generated headers, and the flatbuffers headers.
make_include() {
  local ob bin
  ob=$(output_base st)
  bin=$(ls -d "$ob"/execroot/org_tensorflow/bazel-out/wasm-opt*/bin | head -1)
  rm -rf "$STAGE/include"
  mkdir -p "$STAGE/include/flatbuffers"
  find tensorflow/lite tensorflow/compiler/mlir/lite -name '*.h' -exec cp --parents {} "$STAGE/include/" \;
  (cd "$bin" && find tensorflow/lite tensorflow/compiler/mlir/lite -name '*_generated.h' -exec cp -n --parents {} "$STAGE/include/" \; 2>/dev/null || true)
  cp -r "$ob/external/flatbuffers/include/flatbuffers/." "$STAGE/include/flatbuffers/"
}

pack() {
  local name=tflite-$VERSION-wasm-emsdk-4.0.13.tar.gz dir=/tmp/pack/tflite-$VERSION-wasm v lib
  rm -rf /tmp/pack && mkdir -p "$dir/lib"
  cp -r "$STAGE/include" "$dir/"
  for v in st mt mt-relaxed; do
    lib=$(lib_name "$v")
    [ -f "$STAGE/lib/$lib" ] || { echo "$lib missing, build variant $v first" >&2; exit 1; }
    cp "$STAGE/lib/$lib" "$dir/lib/"
  done
  tar czf "$OUT/$name" -C /tmp/pack "tflite-$VERSION-wasm"
  (cd "$OUT" && md5sum "$name")
}

variants=("$@"); [ ${#variants[@]} -gt 0 ] || variants=(st mt mt-relaxed)
for v in "${variants[@]}"; do build_variant "$v"; done

mkdir -p "$OUT"
make_include
pack
