#!/bin/sh
set -eu
revision=$1
root=$PWD
build=$root/vendor/toaststunt/build/$revision
cmake -S vendor/toaststunt -B "$build" -DCMAKE_BUILD_TYPE=Release
cmake --build "$build" --parallel "${BUILD_JOBS:-2}"
test -x "$build/moo"
ln -sfT -- "$build/moo" state/engine.next
mv -fT -- state/engine.next state/engine
