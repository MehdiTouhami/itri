#!/bin/sh
# Puts Itri on GitHub (private repo MehdiTouhami/itri). Output also goes to publish_log.txt.
cd "$(dirname "$0")"
REPO="MehdiTouhami/itri"

run() {
  [ -d .git ] || git init -b main
  git add -A

  echo "== staged files: $(git diff --cached --name-only | wc -l | tr -d ' ')"
  # Stop if anything that looks like a key or personal data is staged.
  if git diff --cached --name-only | grep -Eq '(^|/)\.env$|garmin_bundle\.json$'; then
    echo "!! .env or garmin_bundle.json staged: aborting"; return 1
  fi
  if git diff --cached -U0 | grep -Eq 'AIza[0-9A-Za-z_-]{30,}|(QDRANT|GOOGLE)_API_KEY *= *["'\'']?[A-Za-z0-9_.-]{20,}'; then
    echo "!! something that looks like an API key is staged: aborting"; return 1
  fi

  if git diff --cached --quiet; then
    echo "== nothing new to commit"
  else
    git commit -q -m "Itri: training and recovery in one app

Merges Itri Fitness and Itri Sleep. Training/Recovery mode switch,
readiness, nights and trends, and a coach grounded in on-device facts
plus research RAG (FastAPI + Gemini + Qdrant in backend/).

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01WxvF4apxgJR6nFYdEtKPdU" && echo "== committed $(git rev-parse --short HEAD)"
  fi

  if git remote get-url origin >/dev/null 2>&1; then
    git push -u origin main
  elif command -v gh >/dev/null 2>&1; then
    gh auth status >/dev/null 2>&1 || { echo "!! run: gh auth login   then ./publish.sh again"; return 1; }
    gh repo create "$REPO" --private --source . --remote origin --push \
      --description "Training and recovery in one Flutter app, with an AI coach"
  else
    echo "!! GitHub CLI not installed. Either: brew install gh && gh auth login && ./publish.sh"
    echo "   or create an empty private repo 'itri' on github.com, then:"
    echo "   git remote add origin https://github.com/$REPO.git && git push -u origin main"
    return 1
  fi
  echo "== done: https://github.com/$REPO"
}

run 2>&1 | tee publish_log.txt
