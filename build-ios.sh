#!/bin/bash

echo "== Installing bazelisk"
brew install bazelisk

echo
echo "== Running configure, answer yes for the iOS question, otherwise choose default (press enter)"
echo
./configure

for i in ios_arm64 ios_x86_64 ios_sim_arm64; do
    echo
    echo "== Building for arch $i"
    echo
    bazel build --config=$i -c opt --define tflite_with_xnnpac=true //tensorflow/lite/ios:TensorFlowLiteC_static_framework
    cp bazel-bin/tensorflow/lite/ios/*.a .
done


echo "== Combining into a single framework"
lipo -create TensorFlowLiteC_static_framework-arm64-apple-ios12.0-simulator-fl.a  TensorFlowLiteC_static_framework-x86_64-apple-ios12.0-simulator-fl.a -output TensorFlowLiteC_ios_sim.a
xcodebuild -create-xcframework -library TensorFlowLiteC_ios_sim.a -library TensorFlowLiteC_static_framework-arm64-apple-ios12.0-fl.a -output TensorFlowLiteC.xcframework

echo "== Resulting artifact:"
ls -ld TensorFlowLiteC.xcframework
