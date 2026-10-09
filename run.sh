#!/bin/sh
# Builds, then starts Butterlight and Butterfinder in the background (they keep running after this exits).
cd "$(dirname "$0")" && swift build || exit 1
pkill -x Butterlight; pkill -x Butterfinder; sleep 1
nohup .build/out/Products/Debug/Butterlight >/tmp/bl.log 2>&1 &
nohup .build/out/Products/Debug/Butterfinder >/tmp/bf.log 2>&1 &
