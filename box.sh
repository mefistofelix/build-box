#!/bin/bash
# Client of the blind build machine: packs a folder (which must have build.sh at its root) into an encrypted 7z,
# uploads it, runs the workflow, waits, downloads the encrypted result and opens it.
#
# usage: box.sh <folder> <password file> <result folder> [options]
#   --runner LABEL   GitHub runner (default ubuntu-latest): ubuntu-24.04, windows-latest, macos-latest, ...
#   --setup "LIST"   toolchains: java android node python
#   --java V --node V --python V   versions for --setup
#   --cache NAME     keep $CACHE between runs under this name (the public key is a hash of it, not the name)
#   --cache-save W   when $CACHE is saved back: success (default), always (also after a failed build), never
#   --timeout MIN    stop the build after these minutes (default 90)
#   --repo OWNER/NAME   the build machine (default mefistofelix/build-box)
# Needs: bash, gh (logged in), 7z (or 7zz), sha256sum. Exit status: 0 built, 1 build failed (log printed), 2 usage.
# The result folder gets what build.sh put in $OUT plus build.log.
set -e
[ $# -ge 3 ] || { sed -n 2,15p "$0"; exit 2; }
SRC="$1"; PASSFILE="$2"; RESULT="$3"; shift 3
RUNNER=ubuntu-latest; SETUP=""; JAVA=17; NODE=22; PYTHON=3.12; CACHE=""; CACHESAVE=success; TIMEOUT=90; REPO=mefistofelix/build-box
while [ $# -gt 0 ]; do
  case "$1" in
    --runner) RUNNER="$2";; --setup) SETUP="$2";; --java) JAVA="$2";; --node) NODE="$2";; --python) PYTHON="$2";;
    --cache) CACHE="$2";; --cache-save) CACHESAVE="$2";; --timeout) TIMEOUT="$2";; --repo) REPO="$2";; *) echo "unknown option $1"; exit 2;;
  esac; shift 2
done
[ -f "$SRC/build.sh" ] || { echo "$SRC has no build.sh"; exit 2; }
SEVEN="$(command -v 7z || command -v 7zz || true)"
[ -z "$SEVEN" ] && [ -x "/c/Program Files/7-Zip/7z.exe" ] && SEVEN="/c/Program Files/7-Zip/7z.exe"
[ -n "$SEVEN" ] || { echo "7z not found"; exit 2; }
PASS="$(cat "$PASSFILE")"
# opaque names: they are visible on the public repository
JOB="$(head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n')"
KEY=""; [ -n "$CACHE" ] && KEY="c$(printf '%s' "$PASS$CACHE" | sha256sum | cut -c1-16)"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
(cd "$SRC" && "$SEVEN" a -y -mhe=on -mx=5 -p"$PASS" "$W/in-$JOB.7z" . > /dev/null)
echo "packed $(du -h "$W/in-$JOB.7z" | cut -f1)"
gh release upload inbox "$W/in-$JOB.7z" -R "$REPO" --clobber > /dev/null
gh workflow run box.yml -R "$REPO" -f job="$JOB" -f runner="$RUNNER" -f setup="$SETUP" -f java="$JAVA" -f node="$NODE" -f python="$PYTHON" -f cache="$KEY" -f cache_save="$CACHESAVE" -f timeout="$TIMEOUT" > /dev/null
ID=""
for i in $(seq 1 45); do ID="$(gh run list -R "$REPO" -w box.yml -L 20 --json databaseId,displayTitle -q ".[] | select(.displayTitle==\"box $JOB\") | .databaseId" | head -1)"; [ -n "$ID" ] && break; sleep 2; done
[ -n "$ID" ] || { echo "the run did not start"; exit 1; }
echo "run $ID on $RUNNER"
STATUS=0; gh run watch "$ID" -R "$REPO" --exit-status > /dev/null 2>&1 || STATUS=$?
if gh release download outbox -R "$REPO" -p "out-$JOB.7z" -D "$W" > /dev/null 2>&1; then
  gh release delete-asset outbox "out-$JOB.7z" -R "$REPO" -y > /dev/null
  mkdir -p "$RESULT"; "$SEVEN" x -y -p"$PASS" -o"$RESULT" "$W/out-$JOB.7z" > /dev/null
else echo "no result came back (the run stopped before sealing it)"; gh release delete-asset inbox "in-$JOB.7z" -R "$REPO" -y > /dev/null 2>&1 || true; exit 1; fi
if [ "$STATUS" != 0 ]; then echo "BUILD FAILED, end of $RESULT/build.log:"; tail -40 "$RESULT/build.log"; exit 1; fi
echo "built: $RESULT"
