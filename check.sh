#!/bin/sh
# One-shot setup + verification. Writes everything to check_log.txt so Claude can read it.
cd "$(dirname "$0")"
{
  echo "== flutter --version"; flutter --version
  if [ ! -d ios ] || [ ! -d android ]; then
    echo "== flutter create (platform folders)"
    flutter create --org com.itri --project-name itri_fitness --platforms=ios,android,macos,web .
    rm -f test/widget_test.dart
  fi
  echo "== pub get"; flutter pub get
  echo "== analyze"; flutter analyze
  echo "== test"; flutter test
  echo "== done"
} > check_log.txt 2>&1
tail -25 check_log.txt
