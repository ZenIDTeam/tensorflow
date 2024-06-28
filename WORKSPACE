workspace(name = "org_tensorflow")

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

http_archive(
  name = "mediapipe",
  strip_prefix = "mediapipe-0.8.10",
  url = "https://github.com/google/mediapipe/archive/refs/tags/v0.8.10.tar.gz",
  sha256 = "6b43a4304ca4aa3a698906e4b4ff696d698d0b788baffd8284c03632712b1020",
  patches = [
    "//tensorflow:mediapipe_visibility.patch",
  ]
)

# Initialize the TensorFlow repository and all dependencies.
#
# The cascade of load() statements and tf_workspace?() calls works around the
# restriction that load() statements need to be at the top of .bzl files.
# E.g. we can not retrieve a new repository with http_archive and then load()
# a macro from that repository in the same file.
load("@//tensorflow:workspace3.bzl", "tf_workspace3")

tf_workspace3()

load("@//tensorflow:workspace2.bzl", "tf_workspace2")

tf_workspace2()

load("@//tensorflow:workspace1.bzl", "tf_workspace1")

tf_workspace1()

load("@//tensorflow:workspace0.bzl", "tf_workspace0")

tf_workspace0()

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
http_archive(
    name = "emsdk",
    sha256 = "a6387de363af5685e30920648a6b8122c2fe8c224c0ab6fe39808db6f1bcac2e",
    strip_prefix = "emsdk-3.1.60/bazel",
    url = "https://github.com/emscripten-core/emsdk/archive/refs/tags/3.1.60.tar.gz",
)

load("@emsdk//:deps.bzl", emsdk_deps = "deps")
emsdk_deps()

load("@emsdk//:emscripten_deps.bzl", emsdk_emscripten_deps = "emscripten_deps")
emsdk_emscripten_deps(emscripten_version = "3.1.60")
