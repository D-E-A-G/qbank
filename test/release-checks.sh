#!/usr/bin/env bash
# Repository and pipeline rule checks.
#
# Credential-free by construction: these checks read repository files only.
# They never touch Apple credentials, App Store Connect, or the network, and
# they run the same on a Linux CI machine and on a developer Mac. They need
# bash, git, grep, and ruby (for YAML).
# shellcheck disable=SC2016 # the Ruby programs are single-quoted on purpose
set -u

cd "$(dirname "$0")/.." || exit 1

FAILURES=0

fail() {
  echo "FAIL: $1" >&2
  FAILURES=$((FAILURES + 1))
}

pass() {
  echo "ok: $1"
}

require_grep() {
  local pattern="$1" file="$2" message="$3"
  if grep -qE -- "$pattern" "$file"; then
    pass "$message"
  else
    fail "$message ($file does not match: $pattern)"
  fi
}

forbid_grep() {
  local pattern="$1" file="$2" message="$3"
  if grep -qE -- "$pattern" "$file"; then
    fail "$message ($file matches forbidden pattern: $pattern)"
  else
    pass "$message"
  fi
}

# Runs a Ruby program over the YAML workflow named by $1 and reports its
# result. The program aborts with a reason on failure.
ruby_check() {
  local message="$1" file="$2" program="$3" out
  if out="$(ruby -ryaml -e "$program" "$file" 2>&1)"; then
    pass "$message"
  else
    fail "$message: $out"
  fi
}

CI=.github/workflows/ci.yml
XCODE=.github/workflows/xcode.yml
MAC_RUNS_ON="\${{ vars.MAC_RUNNER || 'macos-26' }}"

if ! command -v ruby >/dev/null 2>&1; then
  echo "FAIL: ruby is required to parse the workflows" >&2
  exit 1
fi

# --- Workflow syntax --------------------------------------------------------

for workflow in "$CI" "$XCODE"; do
  [ -f "$workflow" ] || fail "workflow exists: $workflow"
done

WORKFLOWS=()
for workflow in .github/workflows/*.yml .github/workflows/*.yaml; do
  [ -f "$workflow" ] && WORKFLOWS+=("$workflow")
done

for workflow in "${WORKFLOWS[@]}"; do
  if ruby -ryaml -e 'YAML.load_file(ARGV[0])' "$workflow" >/dev/null 2>&1; then
    pass "workflow parses as YAML: $workflow"
  else
    fail "workflow parses as YAML: $workflow"
  fi
done

# --- Every workflow ---------------------------------------------------------

for workflow in "${WORKFLOWS[@]}"; do
  unpinned="$(grep -nE '^[[:space:]]*(- )?uses:' "$workflow" | grep -vE 'uses:[[:space:]]*[^[:space:]]+@[0-9a-f]{40}( |$)' || true)"
  if [ -n "$unpinned" ]; then
    fail "every action is pinned to a full commit SHA in $workflow: $unpinned"
  else
    pass "every action is pinned to a full commit SHA in $workflow"
  fi

  forbid_grep 'pull_request_target' "$workflow" "no pull_request_target trigger in $workflow"
  require_grep '^permissions:' "$workflow" "$workflow sets top-level permissions"

  # A Mac job may run on the self-hosted MAC_RUNNER, so code from a pull
  # request (possibly from a fork) must never reach it.
  ruby_check "$workflow runs no Mac or self-hosted job on pull requests" "$workflow" '
    wf = YAML.load_file(ARGV[0])
    on = wf[true] || wf["on"]
    events = on.is_a?(Hash) ? on.keys.map(&:to_s) : Array(on).map(&:to_s)
    exit 0 unless events.any? { |e| e.start_with?("pull_request") }
    (wf["jobs"] || {}).each do |name, job|
      runs_on = job["runs-on"].to_s
      if runs_on =~ /MAC_RUNNER|self-hosted|macos/i
        abort "job #{name} runs on #{runs_on} and the workflow triggers on #{events.inspect}"
      end
    end
  '
done

# --- ci.yml: pull requests, Linux only, no secrets ---------------------------

forbid_grep 'secrets\.' "$CI" "ci.yml references no secrets"
require_grep '^  contents: read$' "$CI" "ci.yml permissions are contents: read"
forbid_grep ':[[:space:]]*write' "$CI" "ci.yml grants no write permission"
ruby_check "ci.yml triggers only on pull_request and runs only on Linux" "$CI" '
  wf = YAML.load_file(ARGV[0])
  on = wf[true] || wf["on"]
  keys = on.is_a?(Hash) ? on.keys.map(&:to_s) : Array(on).map(&:to_s)
  abort "on: is #{keys.inspect}, expected [\"pull_request\"]" unless keys == ["pull_request"]
  jobs = wf["jobs"] || {}
  abort "no jobs" if jobs.empty?
  jobs.each do |name, job|
    runs_on = job["runs-on"]
    abort "job #{name} runs on #{runs_on.inspect}" unless runs_on.is_a?(String) && runs_on.start_with?("ubuntu-")
  end
'
require_grep 'release-checks\.sh' "$CI" "ci.yml runs test/release-checks.sh"
require_grep 'package-tests\.sh --linux' "$CI" "ci.yml tests the Swift packages on Linux"

# --- xcode.yml: trusted events only, MAC_RUNNER with hosted fallback ---------

forbid_grep 'secrets\.' "$XCODE" "xcode.yml references no secrets"
require_grep '^  contents: read$' "$XCODE" "xcode.yml permissions are contents: read"
forbid_grep ':[[:space:]]*write' "$XCODE" "xcode.yml grants no write permission"
ruby_check "xcode.yml triggers only on main pushes, qbank-v* tags, and manual runs" "$XCODE" '
  wf = YAML.load_file(ARGV[0])
  on = wf[true] || wf["on"]
  abort "on: must be a mapping" unless on.is_a?(Hash)
  keys = on.keys.map(&:to_s)
  abort "on: keys are #{keys.inspect}, expected [\"push\", \"workflow_dispatch\"]" unless keys == %w[push workflow_dispatch]
  push = on["push"]
  unless push.is_a?(Hash) && push.keys.map(&:to_s).sort == %w[branches tags] &&
         push["branches"] == ["main"] && push["tags"] == ["qbank-v*"]
    abort "push must be exactly branches: [main] and tags: [qbank-v*] (got #{push.inspect})"
  end
'
ruby_check "every xcode.yml job runs on $MAC_RUNS_ON" "$XCODE" '
  jobs = YAML.load_file(ARGV[0])["jobs"] || {}
  abort "no jobs" if jobs.empty?
  expected = "${{ vars.MAC_RUNNER || '"'"'macos-26'"'"' }}"
  jobs.each do |name, job|
    abort "job #{name} runs on #{job["runs-on"].inspect}" unless job["runs-on"] == expected
  end
'
require_grep 'package-tests\.sh --macos' "$XCODE" "xcode.yml tests the Swift packages on macOS"
forbid_grep '^[^#]*sudo[[:space:]]' "$XCODE" "xcode.yml needs no sudo (the self-hosted runner has none)"

# --- Simulators only through test/sim.sh -------------------------------------

for workflow in "${WORKFLOWS[@]}"; do
  forbid_grep 'simctl' "$workflow" "$workflow never drives simctl directly"
  bad_destination="$(grep -nE 'platform=iOS Simulator' "$workflow" | grep -vF 'platform=iOS Simulator,id={{UDID}}' || true)"
  if [ -n "$bad_destination" ]; then
    fail "$workflow targets simulators only through test/sim.sh's {{UDID}}: $bad_destination"
  else
    pass "$workflow targets simulators only through test/sim.sh's {{UDID}}"
  fi
done

# --- Xcode project ------------------------------------------------------------

PBXPROJ=QBank.xcodeproj/project.pbxproj
SCHEME=QBank.xcodeproj/xcshareddata/xcschemes/QBank.xcscheme

if [ -f "$SCHEME" ]; then
  pass "shared QBank scheme exists"
else
  fail "shared QBank scheme exists: $SCHEME"
fi

targets="$(grep -oE 'IPHONEOS_DEPLOYMENT_TARGET = [^;]+;' "$PBXPROJ" | sort -u)"
if [ "$targets" = "IPHONEOS_DEPLOYMENT_TARGET = 18.0;" ]; then
  pass "iOS deployment target is 18.0 everywhere"
else
  fail "iOS deployment target is 18.0 everywhere (found: ${targets:-none})"
fi

families="$(grep -oE 'TARGETED_DEVICE_FAMILY = [^;]+;' "$PBXPROJ" | sort -u)"
if [ "$families" = "TARGETED_DEVICE_FAMILY = 1;" ]; then
  pass "every target is iPhone only"
else
  fail "every target is iPhone only (found: ${families:-none})"
fi

require_grep 'PRODUCT_BUNDLE_IDENTIFIER = com\.dimitrygallego\.qbank;' "$PBXPROJ" "app bundle id is com.dimitrygallego.qbank"
require_grep 'INFOPLIST_KEY_CFBundleDisplayName = QBank;' "$PBXPROJ" "app display name is QBank"
# The Apple team id is a repository variable, never committed.
forbid_grep 'DEVELOPMENT_TEAM = [^";]' "$PBXPROJ" "no Apple team id is committed in the project"

# --- Debug-only launch seam -----------------------------------------------------

SEAM=QBank/DebugLaunchScenario.swift
if [ -f "$SEAM" ] && [ "$(head -n 1 "$SEAM")" = "#if DEBUG" ] && [ "$(tail -n 1 "$SEAM")" = "#endif" ]; then
  pass "the launch seam is wrapped in #if DEBUG"
else
  fail "the launch seam is wrapped in #if DEBUG ($SEAM must start with #if DEBUG and end with #endif)"
fi

# --- Frontend only ----------------------------------------------------------------

require_grep 'Keep this repository frontend-only: do not add backend source, migrations, credentials, deployment assets, or infrastructure configuration here\.' AGENTS.md "AGENTS.md carries the frontend-only rule"

forbidden_files="$(git ls-files | grep -iE '(^|/)(migrations?|deploy|infra|terraform)/|(^|/)(Dockerfile|docker-compose[^/]*|Caddyfile)$|\.(sql|tf|tfvars|p8|p12|pem|key|cer|mobileprovision)$|(^|/)\.env($|\.)' || true)"
if [ -n "$forbidden_files" ]; then
  fail "no backend, deployment, infrastructure, or credential files are tracked: $forbidden_files"
else
  pass "no backend, deployment, infrastructure, or credential files are tracked"
fi

echo
if [ "$FAILURES" -gt 0 ]; then
  echo "$FAILURES check(s) failed." >&2
  exit 1
fi
echo "All checks passed."
