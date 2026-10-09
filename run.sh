#!/bin/sh
# Builds, then starts BetterLauncher and BetterFiles in the background (they keep running after this exits).
cd "$(dirname "$0")" && swift build || exit 1
pkill -x BetterLauncher; pkill -x BetterFiles; sleep 1
nohup .build/out/Products/Debug/BetterLauncher >/tmp/bl.log 2>&1 &
nohup .build/out/Products/Debug/BetterFiles >/tmp/bf.log 2>&1 &
