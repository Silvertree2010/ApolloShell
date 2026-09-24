#!/bin/zsh
set -u
root=${0:A:h:h:h}
out=${1:?usage: render.sh <folder> [light|dark]}
appearance=${2:-light}
binary=$root/.build/debug/ApolloShell
system=$root/.build/render/fixed-system.dylib
fixed_env=(
  TZ=Europe/Zurich
  APOLLO_FIXED_CLOCK=${APOLLO_FIXED_CLOCK:-1790235660}
  APOLLO_FIXED_OS=26.6.2
  "APOLLO_FIXED_OS_STRING=Version 26.6.2 (Build 25G83)"
  APOLLO_FIXED_CPUS=14
  "APOLLO_FIXED_SYSCTL_STR=machdep.cpu.brand_string=Apple M4 Pro"
  APOLLO_FIXED_GPU_CORES=20
)
defaults_args=(
  -AppleAccentColor 4
  -AppleHighlightColor "0.698039 0.843137 1.000000 Blue"
  -AppleLanguages "(en)"
  -AppleLocale en_US
)
[[ -x $binary ]] || { print -u2 "missing $binary"; exit 1 }
mkdir -p ${system:h} $out
clang -dynamiclib -framework CoreFoundation -framework IOKit -o $system $root/scripts/render/fixed-system.c || exit 1
env $fixed_env DYLD_INSERT_LIBRARIES=$system $binary --render $out --fixture $root/Resources/render/fixture.kdl --resources $root/Resources --appearance $appearance --scale 2 ${=APOLLO_RENDER_EXTRA:-} $defaults_args
