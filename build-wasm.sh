#!/bin/bash


echo "Note: before building, the .a archives should be deleted."
echo "Run source emsdk/emsdk_env.sh before building"
echo "You have to install emsdk separately even though bazel supposedly downloads it"
echo "Make sure it's the same version as what you got in bazel config"
echo "To check for missing symbols run"
echo "emnm -C libtflite_c.so | sed -ne '/U /p' | less"
echo "and look for symbols that aren't in the standard libraries"
echo "Good luck!"
echo
read -p "(Press Enter to continue) "

emcc --version &> /dev/null
if [ ! $? -eq 0 ]; then
    echo "You forgot to run source emsdk/emsdk_env.sh! Goodbye!";
    exit 1
fi

set -e

echo "Building tflite for wasm..."
./bazel build --config=wasm -c opt //tensorflow/lite/core/c:c_api //tensorflow/lite/delegates/xnnpack:xnnpack_delegate
emar qsL libtflite_c.a `find bazel-bin/ -name '*.o'`
echo "Building a monolithic object to check for duplicate symbols..."
emcc -o libtflite_c.so -r libtflite_c.a -s LINKABLE

echo "Building tflite SIMD for wasm..."
./bazel build --config=wasm_simd -c opt //tensorflow/lite/core/c:c_api //tensorflow/lite/delegates/xnnpack:xnnpack_delegate
emar qsL libtflite_c-simd.a `find bazel-bin/ -name '*.o'`
echo "Building a monolithic object to check for duplicate symbols..."
emcc -o libtflite_c-simd.so -r libtflite_c-simd.a -s LINKABLE

echo "Build finished, resulting artifacts:"
ls -l libtflite_c*.a
