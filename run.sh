#!/bin/sh
# Runs Itri with the coach key from the git-ignored secrets.json.
# Extra arguments pass through, e.g. ./run.sh -d <device id>
cd "$(dirname "$0")"
if [ ! -f secrets.json ]; then
  echo "secrets.json missing: ask for the coach key, or the coach will be locked."
  exec flutter run "$@"
fi
exec flutter run --dart-define-from-file=secrets.json "$@"
