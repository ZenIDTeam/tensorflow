#Requires -Version 7
# Builds tensorflowlite_c.dll (C API + XNNPACK delegate) with MSVC for the ZenID Windows SDK and packs
# out-windows/tflite-<version>-windows.tar.gz (tflite-<version>/lib and tflite-<version>/include).
# Run from any folder:
#
#   pwsh -File build-windows.ps1
#
# Needs Visual Studio (Build Tools) with the C++ workload, Git for Windows (its bash runs Bazel genrules)
# and Python 3 on PATH (the @llvm-project repository rule runs it).
# Does not need Windows Developer Mode or admin rights: Bazel copies files instead of creating symlinks,
# and the LLVM overlay script gets hard links and junctions from a sitecustomize shim (see below).
param(
    # Short Bazel output root: MSVC tools fail on paths longer than 260 characters.
    [string]$BazelRoot = 'C:/b',
    # bazelisk.exe and the Bazel binaries it downloads.
    [string]$ToolsDir = 'C:/temp/bazel-tools'
)
$ErrorActionPreference = 'Stop'
$Version = '2.19.1'
$Target = '//tensorflow/lite/c:tensorflowlite_c'
Set-Location $PSScriptRoot

if (-not $env:BAZEL_VC) {
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    $vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    $env:BAZEL_VC = "$vs\VC"
}
if (-not $env:BAZEL_VC_FULL_VERSION) {
    $env:BAZEL_VC_FULL_VERSION = (Get-Content "$env:BAZEL_VC\Auxiliary\Build\Microsoft.VCToolsVersion.default.txt").Trim()
}
if (-not $env:BAZEL_SH) { $env:BAZEL_SH = "$env:ProgramFiles\Git\usr\bin\bash.exe" }
$env:BAZELISK_HOME = "$ToolsDir/cache"
Write-Host "MSVC $env:BAZEL_VC_FULL_VERSION in $env:BAZEL_VC"

$bazel = "$ToolsDir/bazelisk.exe"
if (-not (Test-Path $bazel)) {
    New-Item -ItemType Directory -Force $ToolsDir | Out-Null
    Invoke-WebRequest https://github.com/bazelbuild/bazelisk/releases/download/v1.25.0/bazelisk-windows-amd64.exe -OutFile $bazel
}

# The @llvm-project repository rule runs overlay_directories.py, which calls os.symlink. Without Developer Mode
# that fails, so for this script only, os.symlink makes a junction (directory) or a hard link (file).
$shim = "$BazelRoot/pyshim"
New-Item -ItemType Directory -Force $shim | Out-Null
Set-Content "$shim/sitecustomize.py" @'
import os, sys
if os.name == "nt" and sys.argv and sys.argv[0].endswith("overlay_directories.py"):
    import _winapi

    def _link(src, dst, target_is_directory=False, **kwargs):
        if os.path.isdir(src):
            _winapi.CreateJunction(src, dst)
        else:
            os.link(src, dst)

    os.symlink = _link
'@
$env:PYTHONPATH = $shim

# No symlinks: --nowindows_enable_symlinks overrides "startup --windows_enable_symlinks" in .bazelrc, and
# py_binary tools used by genrules run from a zip instead of a runfiles tree.
$startup = "--output_user_root=$BazelRoot", '--nowindows_enable_symlinks'
$opts = '-c', 'opt', '--noenable_runfiles', '--build_python_zip', "--repository_cache=$BazelRoot/repo",
    '--repo_env=HERMETIC_PYTHON_VERSION=3.10', '--repo_env=TF_PYTHON_VERSION=3.10',
    '--define=tflite_with_xnnpack=true',
    # std::mutex with a constexpr constructor crashes with VC++ redistributables older than the compiler.
    '--cxxopt=-D_DISABLE_CONSTEXPR_MUTEX_CONSTRUCTOR'
& $bazel @startup build @opts $Target
if ($LASTEXITCODE) { throw 'bazel build failed' }
$bin = & $bazel @startup info @opts bazel-bin
$outputBase = & $bazel @startup info @opts output_base

$out = "$PSScriptRoot/out-windows"
$stage = "$out/stage"
$dir = "$stage/tflite-$Version"
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory -Force "$dir/lib", "$dir/include/flatbuffers" | Out-Null
foreach ($f in 'tensorflowlite_c.dll', 'tensorflowlite_c.dll.if.lib', 'tensorflowlite_c.pdb') {
    Copy-Item "$bin/tensorflow/lite/c/$f" "$dir/lib/"
}

# include/ = headers under tensorflow/lite and tensorflow/compiler/mlir/lite (the C API includes them),
# flatc-generated headers, and the flatbuffers headers. Same content as the wasm build (build-wasm.sh).
function Copy-Headers($root, $filter, [switch]$NoOverwrite) {
    foreach ($sub in 'tensorflow/lite', 'tensorflow/compiler/mlir/lite') {
        Get-ChildItem "$root/$sub" -Recurse -File -Filter $filter | ForEach-Object {
            $dest = Join-Path "$dir/include" ([IO.Path]::GetRelativePath($root, $_.FullName))
            if ($NoOverwrite -and (Test-Path $dest)) { return }
            New-Item -ItemType Directory -Force (Split-Path $dest) | Out-Null
            Copy-Item $_.FullName $dest
        }
    }
}
Copy-Headers $PSScriptRoot '*.h'
Copy-Headers $bin '*_generated.h' -NoOverwrite
Copy-Item "$outputBase/external/flatbuffers/include/flatbuffers/*" "$dir/include/flatbuffers/" -Recurse

$tarball = "$out/tflite-$Version-windows.tar.gz"
& "$env:SystemRoot\System32\tar.exe" -czf $tarball -C $stage "tflite-$Version"
if ($LASTEXITCODE) { throw 'tar failed' }
Write-Host "$((Get-FileHash -Algorithm MD5 $tarball).Hash.ToLower())  $tarball"
