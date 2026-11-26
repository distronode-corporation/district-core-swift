#!/usr/bin/env bash
#
# Build the package in release twice from clean, and fail unless every compiled artifact of
# the two builds is byte for byte the same.
#
#     ci/repeatable-build.sh
#
# Run from the package root, in CI's Linux container (the `repeatable` job) or anywhere with
# the same toolchain. A release of this package is a source tag that the apps compile
# themselves, so the artifacts compared are what that compile produces from these sources:
# every object file (`*.o`) and every module (`*.swiftmodule`, `*.swiftdoc`) under
# `.build/release`, for the seven libraries and the dependencies they link. The build
# system's own bookkeeping (dependency files, output maps, the build database, timestamps)
# is not an artifact and is not compared.
#
# Each build deletes `.build` first, so the second cannot reuse the first one's outputs, and
# both build in the same directory, so paths the compiler embeds (debug info) are the same.
#
# Expected differences: none. Every artifact is compared; nothing is skipped.
#
# ⛔ SWIFT_DETERMINISTIC_HASHING=1 IS PART OF THE RECIPE. Parts of the toolchain are written in
# Swift (the driver, optimizer passes), and a Swift Dictionary's iteration order follows a
# hash seed that is random per process unless this variable is set; district-ios's two
# clean builds differed for that reason. It changes no source and no build setting.
#
# ⛔ EVERY DEPENDENCY SOURCE FILE'S MODIFICATION TIME IS SET TO THE COMMIT'S TIME BEFORE EACH
# BUILD (SOURCE_DATE_EPOCH, the reproducible-builds.org convention). swift-crypto's Swift code imports
# its C module CCryptoBoringSSL, and clang records the mtime of every header in that module's
# precompiled form, whose signature then lands in each importing object file's
# `.swift_modhash` and debug info. SwiftPM clones the dependencies afresh into `.build` for
# each clean build, so without this the headers' mtimes, and with them 106 of swift-crypto's
# object files, differed between two builds of the same commit (first run on #101). This
# package's own seven modules import no C module and were identical either way.
# ⚠️ ONLY `.build/checkouts` IS TOUCHED, which SwiftPM creates for this build and the next build
# deletes. The working tree's own files keep their times, so a local run cannot hide a
# changed file from anything that goes by modification time (a backup, make).
#
# On a difference it prints each differing file and keeps both sets of artifacts under
# $RUNNER_TEMP/repeatable (or /tmp/repeatable) for the job to upload.
set -euo pipefail

OUT=${RUNNER_TEMP:-/tmp}/repeatable
export SWIFT_DETERMINISTIC_HASHING=1
SOURCE_DATE_EPOCH=$(git -c safe.directory="$PWD" log -1 --format=%ct)
export SOURCE_DATE_EPOCH
rm -rf "$OUT"
mkdir -p "$OUT"

for n in 1 2; do
  echo "== build $n"
  rm -rf .build
  swift package resolve > "$OUT/resolve-$n.log" 2>&1 || {
    tail -n 100 "$OUT/resolve-$n.log"
    exit 1
  }
  find .build/checkouts -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +
  swift build -c release > "$OUT/build-$n.log" 2>&1 || {
    tail -n 100 "$OUT/build-$n.log"
    exit 1
  }
  mkdir -p "$OUT/$n"
  # The real directory behind the `.build/release` link, so the copy holds files, not a link.
  release=$(cd .build/release && pwd -P)
  (cd "$release" && find . -type f \( -name '*.o' -o -name '*.swiftmodule' -o -name '*.swiftdoc' \) -print0 \
    | sort -z | xargs -0 cp --parents -t "$OUT/$n")
  (cd "$OUT/$n" && find . -type f -print0 | sort -z | xargs -0 sha256sum) > "$OUT/$n.sha256"
  count=$(wc -l < "$OUT/$n.sha256" | tr -d ' ')
  echo "$count artifacts in build $n"
  # ⛔ A BUILD THAT PRODUCED NOTHING COMPARES EQUAL TO ANOTHER THAT PRODUCED NOTHING.
  if [ "$count" -lt 7 ]; then
    echo "FAIL: build $n produced $count artifacts; expected at least the seven libraries"
    exit 1
  fi
done

for module in DistrictL10n DistrictModel DistrictAuthCore DistrictNetwork DistrictData DistrictCall DistrictLive; do
  grep -q "/$module.swiftmodule\$" "$OUT/1.sha256" || {
    echo "FAIL: no $module.swiftmodule in the release build"
    exit 1
  }
done

if diff -u "$OUT/1.sha256" "$OUT/2.sha256" > "$OUT/sha256.diff"; then
  echo "PASS: both release builds' $(wc -l < "$OUT/1.sha256" | tr -d ' ') artifacts are byte for byte identical"
  exit 0
fi

echo "FAIL: the two builds differ in these files:"
grep -E '^[-+][0-9a-f]{64} ' "$OUT/sha256.diff" | sed -E 's/^[-+][0-9a-f]{64}  //' | sort -u | tee "$OUT/differing.txt"
exit 1
