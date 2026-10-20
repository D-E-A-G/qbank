#!/usr/bin/env bash
# Fails when a change adds a secret. It runs gitleaks twice: over the lines the
# change's commits add, and over every tracked file as they stand at HEAD, with
# gitleaks' own rules and this repository's exceptions (.gitleaks.toml).
#
# CI runs it on every pull request and every push to main (the "Secrets" job
# in .github/workflows/ci.yml). From the repository root:
#   test/leak-check.sh <base commit> <head commit>
#
# GITLEAKS names the gitleaks binary (default: gitleaks on PATH). Findings are
# printed redacted, so the log never shows the value it found.
set -Eeuo pipefail

base="${1:?usage: leak-check.sh <base commit> <head commit>}"
head="${2:?usage: leak-check.sh <base commit> <head commit>}"
gitleaks="${GITLEAKS:-gitleaks}"
config="$PWD/.gitleaks.toml"

work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT

# The change's own commits. A base that is all zeros (a new branch) or that this
# clone does not hold (history rewritten by a force push) leaves just the head
# commit to check; the full check of the files below still covers the rest.
if [[ "$base" =~ ^0+$ ]] || ! git cat-file -e "$base^{commit}" 2>/dev/null; then
  echo "::warning::base commit $base is not available; checking only $head among the commits"
  log_opts="-1 $head"
else
  log_opts="$base..$head"
fi
echo "Commits: $log_opts"
"$gitleaks" git --config "$config" --log-opts "$log_opts" --redact --no-banner --verbose --exit-code 1 .

# Every tracked file at HEAD, so a secret that came in before this check did is
# found too.
mkdir "$work/tree"
git archive HEAD | tar -x -C "$work/tree"
echo "Files at HEAD ($(git rev-parse --short HEAD))"
"$gitleaks" dir --config "$config" --redact --no-banner --verbose --exit-code 1 "$work/tree"
