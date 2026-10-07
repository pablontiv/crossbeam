#!/usr/bin/env bash
# Executes the release workflow's inline shell against disposable Git repositories.
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
WORKFLOW="$ROOT/.github/workflows/go-release.yml"
README="$ROOT/README.md"
TEST_ROOT=$(mktemp -d)
PASS=0
FAIL=0

cleanup() { rm -rf "$TEST_ROOT"; }
trap cleanup EXIT

extract_release_script() {
  python3 - "$WORKFLOW" "$TEST_ROOT/compute-tag.sh" <<'PY'
from pathlib import Path
import sys

workflow = Path(sys.argv[1]).read_text().splitlines()
output = Path(sys.argv[2])

step = next(i for i, line in enumerate(workflow) if line == "      - name: Compute and push tag")
run = next(i for i in range(step + 1, len(workflow)) if workflow[i] == "        run: |")

body = []
for line in workflow[run + 1:]:
    if line and not line.startswith("          "):
        break
    body.append(line[10:] if line else "")

output.write_text("#!/usr/bin/env bash\nset -euo pipefail\n" + "\n".join(body) + "\n")
PY
  chmod +x "$TEST_ROOT/compute-tag.sh"
}

extract_smoke_script() {
  python3 - "$WORKFLOW" "$TEST_ROOT/smoke-test.sh" <<'PY'
from pathlib import Path
import sys

workflow = Path(sys.argv[1]).read_text().splitlines()
output = Path(sys.argv[2])

step = next(i for i, line in enumerate(workflow) if line == "      - name: Smoke test binary")
run = next(i for i in range(step + 1, len(workflow)) if workflow[i] == "        run: |")

body = []
for line in workflow[run + 1:]:
    if line and not line.startswith("          "):
        break
    body.append(line[10:] if line else "")

output.write_text("\n".join(body) + "\n")
PY
}

extract_attest_scripts() {
  python3 - "$WORKFLOW" "$TEST_ROOT" <<'PY'
from pathlib import Path
import sys

workflow = Path(sys.argv[1]).read_text().splitlines()
root = Path(sys.argv[2])

for step_name, filename in (
    ("Download published release assets", "download-release-assets.sh"),
    ("Validate published release assets", "validate-release-assets.sh"),
):
    step = next(i for i, line in enumerate(workflow) if line == f"      - name: {step_name}")
    run = next(i for i in range(step + 1, len(workflow)) if workflow[i] == "        run: |")
    body = []
    for line in workflow[run + 1:]:
        if line and not line.startswith("          "):
            break
        body.append(line[10:] if line else "")
    (root / filename).write_text("\n".join(body) + "\n")
    if step_name == "Download published release assets":
        start = body.index("python3 - <<'PY'") + 1
        end = body.index("PY", start)
        (root / "download-release-assets.py").write_text("\n".join(body[start:end]) + "\n")
PY
}

extract_readme_verify_script() {
  python3 - "$README" "$TEST_ROOT/readme-verify.sh" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text()
heading = text.index("### Verify a Go release")
start = text.index("```bash\n", heading) + len("```bash\n")
end = text.index("\n```", start)
Path(sys.argv[2]).write_text(text[start:end] + "\n")
PY
  chmod +x "$TEST_ROOT/readme-verify.sh"
}

record() {
  local name=$1 expected=$2 actual=$3
  if [[ "$actual" == "$expected" ]]; then
    printf '  PASS: %s -> %s\n' "$name" "$actual"
    PASS=$((PASS + 1))
  else
    printf '  FAIL: %s -> expected %s, got %s\n' "$name" "$expected" "$actual"
    FAIL=$((FAIL + 1))
  fi
}

make_commit() {
  local repo=$1 subject=$2 body=${3:-}
  printf '%s\n' "$subject" >> "$repo/history.txt"
  git -C "$repo" add history.txt
  if [[ -n "$body" ]]; then
    git -C "$repo" commit -m "$subject" -m "$body" >/dev/null
  else
    git -C "$repo" commit -m "$subject" >/dev/null
  fi
}

run_case() {
  local name=$1 latest=$2 graduation_threshold=$3 force_bump=$4
  local expected_tag=$5 expected_created=$6 expected_type=$7
  shift 7

  local slug=${name//[^a-zA-Z0-9]/-}
  local repo="$TEST_ROOT/$slug"
  local remote="$TEST_ROOT/$slug.git"
  local output="$repo/github-output"
  local log="$repo/run.log"

  git init --bare "$remote" >/dev/null
  git init -b main "$repo" >/dev/null
  git -C "$repo" config user.name Test
  git -C "$repo" config user.email test@example.com
  git -C "$repo" remote add origin "$remote"
  make_commit "$repo" "chore: initialize fixture"
  if [[ "$latest" == "none" ]]; then
    git -C "$repo" push origin main >/dev/null
  else
    git -C "$repo" tag "$latest"
    git -C "$repo" push origin main "$latest" >/dev/null
  fi

  while (( $# > 0 )); do
    local subject=$1 body=${2:-}
    shift 2
    make_commit "$repo" "$subject" "$body"
  done

  (
    cd "$repo"
    GRADUATION_THRESHOLD="$graduation_threshold" FORCE_BUMP="$force_bump" GITHUB_OUTPUT="$output" \
      "$TEST_ROOT/compute-tag.sh"
  ) >"$log" 2>&1

  local actual_tag actual_created actual_type
  actual_tag=$(sed -n 's/^new_tag=//p' "$output" | tail -1)
  actual_created=$(sed -n 's/^created=//p' "$output" | tail -1)
  actual_type=$(sed -n 's/.*type=\([^,]*\).*/\1/p' "$log" | tail -1)

  record "$name tag" "$expected_tag" "$actual_tag"
  record "$name created" "$expected_created" "$actual_created"
  if [[ -n "$expected_type" ]]; then
    record "$name classifier" "$expected_type" "$actual_type"
  fi

  if [[ "$expected_created" == "true" ]]; then
    if git --git-dir="$remote" show-ref --verify --quiet "refs/tags/$expected_tag"; then
      record "$name remote tag" "$expected_tag" "$expected_tag"
    else
      record "$name remote tag" "$expected_tag" "missing"
    fi
  else
    local remote_tags
    remote_tags=$(git --git-dir="$remote" tag -l | sort | tr '\n' ',' | sed 's/,$//')
    local expected_remote_tags=$latest
    [[ "$latest" == "none" ]] && expected_remote_tags=""
    record "$name leaves remote tags unchanged" "$expected_remote_tags" "$remote_tags"
  fi
}

assert_invalid_force_bump_fails() {
  local repo="$TEST_ROOT/invalid-force"
  local remote="$TEST_ROOT/invalid-force.git"
  git init --bare "$remote" >/dev/null
  git init -b main "$repo" >/dev/null
  git -C "$repo" config user.name Test
  git -C "$repo" config user.email test@example.com
  git -C "$repo" remote add origin "$remote"
  make_commit "$repo" "chore: initialize fixture"
  git -C "$repo" tag v1.2.3
  git -C "$repo" push origin main v1.2.3 >/dev/null
  make_commit "$repo" "fix: repair bug"

  local status=0
  (
    cd "$repo"
    GRADUATION_THRESHOLD=5 FORCE_BUMP=banana GITHUB_OUTPUT="$repo/github-output" \
      "$TEST_ROOT/compute-tag.sh"
  ) >"$repo/run.log" 2>&1 || status=$?

  if (( status != 0 )) && grep -q "Invalid force-bump" "$repo/run.log"; then
    record "invalid force-bump fails loudly" "rejected" "rejected"
  else
    record "invalid force-bump fails loudly" "rejected" "accepted"
  fi
}

assert_release_job_skips_without_created_tag() {
  local condition
  condition=$(python3 - "$WORKFLOW" <<'PY'
from pathlib import Path
import sys

lines = Path(sys.argv[1]).read_text().splitlines()
release = next(i for i, line in enumerate(lines) if line == "  release:")
condition = next(line.strip() for line in lines[release + 1:] if line.strip().startswith("if:"))
print(condition)
PY
)
  record "release job is gated by created=true" \
    "if: needs.auto-tag.outputs.created == 'true'" "$condition"
}

make_test_binary() {
  local repo=$1 path=$2 mode=$3
  mkdir -p "$(dirname "$repo/$path")"
  cat > "$repo/$path" <<'SH'
#!/usr/bin/env bash
set -u
mode=$(cat "$0.mode")
printf '%s %s\n' "$0" "${1-}" >> "$INVOCATION_LOG"
case "$mode:${1-}" in
  version-flag:--version|fallback:version) exit 0 ;;
  *) exit 1 ;;
esac
SH
  printf '%s\n' "$mode" > "$repo/$path.mode"
}

run_smoke_case() {
  local name=$1 repo=$2 binary_name=$3 expected=$4
  local status=0
  local invocation_log="$repo/invocations.log"
  local run_log="$repo/smoke.log"
  : > "$invocation_log"

  (
    cd "$repo"
    BINARY_NAME="$binary_name" INVOCATION_LOG="$invocation_log" \
      bash "$TEST_ROOT/smoke-test.sh"
  ) >"$run_log" 2>&1 || status=$?

  local actual=success
  (( status == 0 )) || actual=failure
  record "$name" "$expected" "$actual"
}

assert_smoke_darwin_first_linux_selected() {
  local repo="$TEST_ROOT/smoke-platform-selection"
  mkdir -p "$repo/dist"
  make_test_binary "$repo" "dist/tool_darwin_arm64/tool" both-fail
  make_test_binary "$repo" "dist/tool_linux_amd64/tool" version-flag
  cat > "$repo/dist/artifacts.json" <<'JSON'
[
  {"type":"Binary","name":"tool","goos":"darwin","goarch":"arm64","path":"dist/tool_darwin_arm64/tool"},
  {"type":"Binary","name":"tool","goos":"linux","goarch":"amd64","path":"dist/tool_linux_amd64/tool"}
]
JSON

  run_smoke_case "smoke selects Linux when Darwin is first" "$repo" tool success
  local selected
  selected=$(sed 's/.*dist\///' "$repo/invocations.log")
  record "smoke executes selected Linux artifact" "tool_linux_amd64/tool --version" "$selected"
}

assert_smoke_version_flag_succeeds() {
  local repo="$TEST_ROOT/smoke-version-flag"
  mkdir -p "$repo/dist"
  make_test_binary "$repo" "dist/tool_linux_amd64/tool" version-flag
  cat > "$repo/dist/artifacts.json" <<'JSON'
[{"type":"Binary","name":"tool","goos":"linux","goarch":"amd64","path":"dist/tool_linux_amd64/tool"}]
JSON

  run_smoke_case "smoke accepts --version" "$repo" tool success
  local arguments
  arguments=$(sed 's/.* //' "$repo/invocations.log" | paste -sd, -)
  record "successful --version does not use fallback" "--version" "$arguments"
}

assert_smoke_version_fallback_succeeds() {
  local repo="$TEST_ROOT/smoke-version-fallback"
  mkdir -p "$repo/dist"
  make_test_binary "$repo" "dist/tool_linux_amd64/tool" fallback
  cat > "$repo/dist/artifacts.json" <<'JSON'
[{"type":"Binary","name":"tool","goos":"linux","goarch":"amd64","path":"dist/tool_linux_amd64/tool"}]
JSON

  run_smoke_case "smoke accepts version fallback" "$repo" tool success
  local arguments
  arguments=$(sed 's/.* //' "$repo/invocations.log" | paste -sd, -)
  record "fallback runs after failed --version" "--version,version" "$arguments"
}

assert_smoke_both_version_commands_fail() {
  local repo="$TEST_ROOT/smoke-both-fail"
  mkdir -p "$repo/dist"
  make_test_binary "$repo" "dist/tool_linux_amd64/tool" both-fail
  cat > "$repo/dist/artifacts.json" <<'JSON'
[{"type":"Binary","name":"tool","goos":"linux","goarch":"amd64","path":"dist/tool_linux_amd64/tool"}]
JSON

  run_smoke_case "smoke fails when both version commands fail" "$repo" tool failure
}

assert_smoke_zero_matches_fails() {
  local repo="$TEST_ROOT/smoke-zero-match"
  mkdir -p "$repo/dist"
  make_test_binary "$repo" "dist/tool_darwin_arm64/tool" version-flag
  cat > "$repo/dist/artifacts.json" <<'JSON'
[{"type":"Binary","name":"tool","goos":"darwin","goarch":"arm64","path":"dist/tool_darwin_arm64/tool"}]
JSON

  run_smoke_case "smoke fails with zero matching artifacts" "$repo" tool failure
}

assert_smoke_multiple_matches_fail() {
  local repo="$TEST_ROOT/smoke-multiple-matches"
  mkdir -p "$repo/dist"
  make_test_binary "$repo" "dist/tool_linux_amd64_a/tool" version-flag
  make_test_binary "$repo" "dist/tool_linux_amd64_b/tool" version-flag
  cat > "$repo/dist/artifacts.json" <<'JSON'
[
  {"type":"Binary","name":"tool","goos":"linux","goarch":"amd64","path":"dist/tool_linux_amd64_a/tool"},
  {"type":"Binary","name":"tool","goos":"linux","goarch":"amd64","path":"dist/tool_linux_amd64_b/tool"}
]
JSON

  run_smoke_case "smoke fails with multiple matching artifacts" "$repo" tool failure
}

assert_smoke_missing_path_fails() {
  local repo="$TEST_ROOT/smoke-missing-path"
  mkdir -p "$repo/dist"
  cat > "$repo/dist/artifacts.json" <<'JSON'
[{"type":"Binary","name":"tool","goos":"linux","goarch":"amd64"}]
JSON

  run_smoke_case "smoke fails when artifact path is absent" "$repo" tool failure
}

assert_smoke_missing_file_fails() {
  local repo="$TEST_ROOT/smoke-missing-file"
  mkdir -p "$repo/dist"
  cat > "$repo/dist/artifacts.json" <<'JSON'
[{"type":"Binary","name":"tool","goos":"linux","goarch":"amd64","path":"dist/not-created/tool"}]
JSON

  run_smoke_case "smoke fails when artifact file is absent" "$repo" tool failure
}

assert_smoke_outside_dist_fails() {
  local repo="$TEST_ROOT/smoke-outside-dist"
  mkdir -p "$repo/dist"
  make_test_binary "$repo" tool version-flag
  cat > "$repo/dist/artifacts.json" <<'JSON'
[{"type":"Binary","name":"tool","goos":"linux","goarch":"amd64","path":"tool"}]
JSON

  run_smoke_case "smoke rejects artifact outside dist" "$repo" tool failure
}

assert_smoke_missing_manifest_fails() {
  local repo="$TEST_ROOT/smoke-missing-manifest"
  mkdir -p "$repo/dist"
  run_smoke_case "smoke fails when manifest is absent" "$repo" tool failure
}

assert_smoke_invalid_manifest_fails() {
  local repo="$TEST_ROOT/smoke-invalid-manifest"
  mkdir -p "$repo/dist"
  printf '%s\n' 'not json' > "$repo/dist/artifacts.json"
  run_smoke_case "smoke fails when manifest is invalid" "$repo" tool failure
}

assert_empty_binary_name_preserves_static_skip() {
  local metadata condition env_value
  metadata=$(python3 - "$WORKFLOW" <<'PY'
from pathlib import Path
import sys

lines = Path(sys.argv[1]).read_text().splitlines()
step = next(i for i, line in enumerate(lines) if line == "      - name: Smoke test binary")
end = next(
    (i for i in range(step + 1, len(lines)) if lines[i].startswith("      - name:")),
    len(lines),
)
block = lines[step:end]
print(next(line.strip() for line in block if line.strip().startswith("if:")))
print(next(line.strip() for line in block if line.strip().startswith("BINARY_NAME:")))
PY
)
  condition=$(printf '%s\n' "$metadata" | sed -n '1p')
  env_value=$(printf '%s\n' "$metadata" | sed -n '2p')
  record "empty binary-name preserves static skip" "if: inputs.binary-name != ''" "$condition"
  record "binary-name is passed through env" "BINARY_NAME: \${{ inputs.binary-name }}" "$env_value"
}

write_release_metadata() {
  local asset_dir=$1 metadata=$2
  python3 - "$asset_dir" "$metadata" <<'PY'
import json
from pathlib import Path
import sys
asset_dir = Path(sys.argv[1])
assets = [
    {"id": index, "name": path.name, "size": path.stat().st_size}
    for index, path in enumerate(sorted(asset_dir.iterdir()), 1)
]
Path(sys.argv[2]).write_text(json.dumps({"assets": assets}))
PY
}

run_published_asset_case() {
  local name=$1 fixture=$2 expected=$3
  local repo="$TEST_ROOT/published-${name//[^a-zA-Z0-9]/-}"
  local asset_dir="$repo/assets" metadata="$repo/inventory.json" output="$repo/github-output"
  local status=0 actual=success first_line mutator=""
  mkdir -p "$asset_dir"
  chmod 700 "$asset_dir"

  printf '%s\n' 'first published asset' > "$asset_dir/first.tar.gz"
  printf '%s\n' 'second published asset' > "$asset_dir/second.zip"
  (cd "$asset_dir" && sha256sum first.tar.gz second.zip > checksums.txt)
  write_release_metadata "$asset_dir" "$metadata"

  case "$fixture" in
    valid) ;;
    missing-file) rm "$asset_dir/checksums.txt" ;;
    missing-entry)
      first_line=$(head -n 1 "$asset_dir/checksums.txt")
      printf '%s\n' "$first_line" > "$asset_dir/checksums.txt"
      ;;
    tampered) printf '%s\n' 'tampered' >> "$asset_dir/first.tar.gz" ;;
    extra-existing)
      printf '%s\n' 'not in remote inventory' > "$asset_dir/extra.tar.gz"
      (cd "$asset_dir" && sha256sum extra.tar.gz >> checksums.txt)
      ;;
    duplicate)
      first_line=$(head -n 1 "$asset_dir/checksums.txt")
      printf '%s\n' "$first_line" >> "$asset_dir/checksums.txt"
      ;;
    traversal) printf '%064d  ../outside.tar.gz\n' 0 >> "$asset_dir/checksums.txt" ;;
    absolute) printf '%064d  /tmp/absolute.tar.gz\n' 0 >> "$asset_dir/checksums.txt" ;;
    duplicate-json-key) printf '%s' '{"assets":[],"assets":[]}' > "$metadata" ;;
    nonfinite-json)
      python3 - "$metadata" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
path.write_text(path.read_text().replace('"size": ', '"size": NaN, "original_size": ', 1))
PY
      ;;
    oversized-json)
      python3 - "$metadata" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
path.write_bytes(b" " * (1024 * 1024 + 1))
PY
      ;;
    oversized-manifest)
      truncate -s 1048577 "$asset_dir/checksums.txt"
      write_release_metadata "$asset_dir" "$metadata"
      ;;
    oversized-asset)
      truncate -s 268435457 "$asset_dir/first.tar.gz"
      write_release_metadata "$asset_dir" "$metadata"
      ;;
    oversized-aggregate)
      for number in 1 2 3 4 5; do
        truncate -s 268435456 "$asset_dir/aggregate-$number.tgz"
      done
      write_release_metadata "$asset_dir" "$metadata"
      ;;
    malformed-asset)
      python3 - "$metadata" <<'PY'
import json
from pathlib import Path
import sys
path = Path(sys.argv[1])
data = json.loads(path.read_text())
data["assets"][0]["name"] = 7
path.write_text(json.dumps(data))
PY
      ;;
    remote-missing-checksum)
      python3 - "$metadata" <<'PY'
import json
from pathlib import Path
import sys
path = Path(sys.argv[1])
data = json.loads(path.read_text())
data["assets"] = [asset for asset in data["assets"] if asset["name"] != "checksums.txt"]
path.write_text(json.dumps(data))
PY
      ;;
    remote-extra)
      python3 - "$metadata" <<'PY'
import json
from pathlib import Path
import sys
path = Path(sys.argv[1])
data = json.loads(path.read_text())
data["assets"].append({"id": 99, "name": "remote-only.tar.gz", "size": 1})
path.write_text(json.dumps(data))
PY
      ;;
    remote-casefold)
      python3 - "$metadata" <<'PY'
import json
from pathlib import Path
import sys
path = Path(sys.argv[1])
data = json.loads(path.read_text())
data["assets"].append({"id": 99, "name": "FIRST.TAR.GZ", "size": 1})
path.write_text(json.dumps(data))
PY
      ;;
    remote-alias)
      python3 - "$metadata" <<'PY'
import json
from pathlib import Path
import sys
path = Path(sys.argv[1])
data = json.loads(path.read_text())
data["assets"].append({"id": 99, "name": "../alias.tar.gz", "size": 1})
path.write_text(json.dumps(data))
PY
      ;;
    zero-size)
      python3 - "$metadata" <<'PY'
import json
from pathlib import Path
import sys
path = Path(sys.argv[1])
data = json.loads(path.read_text())
data["assets"][0]["size"] = 0
path.write_text(json.dumps(data))
PY
      ;;
    api-digest-mismatch)
      python3 - "$metadata" <<'PY'
import json
from pathlib import Path
import sys
path = Path(sys.argv[1])
data = json.loads(path.read_text())
for asset in data["assets"]:
    if asset["name"] == "first.tar.gz": asset["digest"] = "sha256:" + "0" * 64
path.write_text(json.dumps(data))
PY
      ;;
    symlink-asset)
      cp "$asset_dir/first.tar.gz" "$repo/outside.tar.gz"
      rm "$asset_dir/first.tar.gz"
      ln -s ../outside.tar.gz "$asset_dir/first.tar.gz"
      ;;
    symlink-checksum)
      cp "$asset_dir/checksums.txt" "$repo/checksums.txt"
      rm "$asset_dir/checksums.txt"
      ln -s ../checksums.txt "$asset_dir/checksums.txt"
      ;;
    concurrent-mutation)
      truncate -s 268435456 "$asset_dir/first.tar.gz"
      (cd "$asset_dir" && sha256sum first.tar.gz second.zip > checksums.txt)
      write_release_metadata "$asset_dir" "$metadata"
      ;;
    *) printf 'unknown published asset fixture: %s\n' "$fixture" >&2; exit 1 ;;
  esac

  if [[ "$fixture" == concurrent-mutation ]]; then
    rm -f "$repo/stop-mutator"
    (while [[ ! -e "$repo/stop-mutator" ]]; do touch "$asset_dir/first.tar.gz"; sleep 0.001; done) &
    mutator=$!
  fi

  ASSET_DIR="$asset_dir" GITHUB_OUTPUT="$output" \
    bash "$TEST_ROOT/validate-release-assets.sh" >"$repo/validation.log" 2>&1 || status=$?
  if [[ -n "$mutator" ]]; then
    touch "$repo/stop-mutator"
    wait "$mutator" || true
  fi
  (( status == 0 )) || actual=failure
  record "$name" "$expected" "$actual"
  if [[ "$fixture" == concurrent-mutation ]]; then
    local mutation_result=missing
    grep -q "changed while reading" "$repo/validation.log" && mutation_result=detected
    record "$name is detected by fstat" "detected" "$mutation_result"
  fi
  if [[ "$expected" == success ]]; then
    local expected_digest actual_digest
    expected_digest=$(sha256sum "$asset_dir/checksums.txt" | cut -d' ' -f1)
    actual_digest=$(sed -n 's/^checksums-digest=//p' "$output")
    record "$name emits only validated checksum digest" "$expected_digest" "$actual_digest"
  fi
}

run_download_helper_tests() {
  local output status=0
  output=$(python3 - "$TEST_ROOT/download-release-assets.py" <<'PY'
import hashlib
import importlib.util
import io
import os
from pathlib import Path
import tempfile
import sys
from urllib.parse import parse_qs, urlparse

spec = importlib.util.spec_from_file_location("download_release_assets", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class Response:
    def __init__(self, status, body=b"", headers=None):
        self.status = status
        self.stream = io.BytesIO(body)
        self.headers = headers or {}
    def read(self, size=-1): return self.stream.read(size)
    def close(self): pass

class Opener:
    def __init__(self, responses):
        self.responses = list(responses)
        self.requests = []
    def open(self, request, timeout=0):
        self.requests.append(request)
        if not self.responses: raise AssertionError("unexpected HTTP request")
        return self.responses.pop(0)

def rejected(call, text):
    try: call()
    except SystemExit as error:
        assert text in str(error), (text, str(error))
    else: raise AssertionError(f"expected rejection containing {text}")

def asset(number, name, size=1, digest=None):
    return {"id": number, "name": name, "size": size, "digest": digest}

def enumerate_with(pages, maximum=None):
    calls = []
    original = module.api_json
    old_max = module.MAX_ASSETS
    if maximum is not None: module.MAX_ASSETS = maximum
    def fake(url, token, label):
        calls.append(url)
        page = int(parse_qs(urlparse(url).query)["page"][0])
        return pages[page - 1], b"[]"
    module.api_json = fake
    try: return module.enumerate_assets("https://api.github.test", "owner/repo", 7, "token"), calls
    finally:
        module.api_json = original
        module.MAX_ASSETS = old_max

page1 = [asset(1, "checksums.txt")] + [asset(i, f"asset-{i}.tar.gz") for i in range(2, 51)]
page2 = [asset(51, "asset-51.tar.gz"), asset(52, "asset-52.tar.gz")]
assets, calls = enumerate_with([page1, page2], maximum=64)
assert len(assets) == 52 and len(calls) == 2
assert "per_page=50" in calls[0] and "page=1" in calls[0] and "page=2" in calls[1]
print("pagination spans pages and stops on short page")

rejected(lambda: enumerate_with([[asset(1, "checksums.txt")] + [asset(i, f"a-{i}.tgz") for i in range(2, 34)]]), "more than 32")
print("asset count over 32 is rejected immediately")

rejected(lambda: enumerate_with([page1, [asset(1, "duplicate-id.tgz")]], maximum=64), "duplicated")
print("duplicate IDs across pages are rejected")

module.OPENER = Opener([Response(200, b"x" * (module.MAX_JSON + 1))])
rejected(lambda: module.api_json("https://api.github.test/release", "token", "release metadata"), "byte limit")
print("oversized API JSON is rejected")

rejected(lambda: enumerate_with([[asset(1, "checksums.txt", module.MAX_MANIFEST + 1), asset(2, "a.tgz")]]), "checksums.txt exceeds")
rejected(lambda: enumerate_with([[asset(1, "checksums.txt"), asset(2, "a.tgz", module.MAX_ASSET + 1)]]), "256 MiB")
rejected(lambda: enumerate_with([[asset(1, "checksums.txt"), *[asset(i, f"a-{i}.tgz", module.MAX_ASSET) for i in range(2, 7)]]]), "aggregate")
print("manifest asset and aggregate bounds are enforced")

def transfer(name, body, expected, responses=None, digest=None):
    with tempfile.TemporaryDirectory() as temporary:
        directory_fd = os.open(temporary, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
        try:
            module.OPENER = Opener(responses or [Response(200, body)])
            module.download_asset("https://api.github.test", "owner/repo", asset(9, name, expected, digest), "secret", directory_fd)
            data = (Path(temporary) / name).read_bytes()
            return module.OPENER.requests, data
        finally: os.close(directory_fd)

rejected(lambda: transfer("truncated.tgz", b"1234", 5), "truncated")
rejected(lambda: transfer("overlong.tgz", b"12345", 4), "exceeds declared")
print("truncated and overlong transfers are rejected")

responses = [
    Response(302, headers={"Location": "https://release-assets.githubusercontent.com/signed"}),
    Response(200, b"data"),
]
requests, data = transfer("redirect.tgz", b"data", 4, responses)
assert data == b"data"
assert requests[0].get_header("Authorization") == "Bearer secret"
assert requests[1].get_header("Authorization") is None
print("allowed redirect strips authorization")

bad = [Response(302, headers={"Location": "https://evil.example/asset"})]
rejected(lambda: transfer("bad-host.tgz", b"data", 4, bad), "not allowed")
print("untrusted redirect host is rejected")

wrong = "sha256:" + "0" * 64
rejected(lambda: transfer("digest.tgz", b"data", 4, digest=wrong), "API digest mismatch")
correct = "sha256:" + hashlib.sha256(b"data").hexdigest()
_, data = transfer("digest-ok.tgz", b"data", 4, digest=correct)
assert data == b"data"
print("API digest is verified when present")
PY
) || status=$?
  if (( status != 0 )); then
    record "extracted bounded download helper" "success" "failure"
    printf '%s\n' "$output" >&2
    return
  fi
  while IFS= read -r name; do
    record "$name" "success" "success"
  done <<< "$output"
}

assert_isolated_attestation_job() {
  local metadata
  metadata=$(python3 - "$WORKFLOW" <<'PY'
from pathlib import Path
import sys
lines = Path(sys.argv[1]).read_text().splitlines()
release = next(i for i, line in enumerate(lines) if line == "  release:")
attest = next(i for i, line in enumerate(lines) if line == "  attest:")
release_block, attest_block = lines[release:attest], lines[attest:]
steps = next(i for i, line in enumerate(attest_block) if line == "    steps:")
header = attest_block[:steps]
def value(prefix): return next((line.strip() for line in header if line.strip().startswith(prefix)), "missing")

try:
    import yaml
except ImportError as error:
    raise SystemExit(f"PyYAML is required to parse workflow YAML: {error}") from error
try:
    workflow = yaml.safe_load(Path(sys.argv[1]).read_text())
except yaml.YAMLError as error:
    raise SystemExit(f"could not parse workflow YAML: {error}") from error

expected_permissions = {
    "auto-tag": {"contents": "write"},
    "release": {"contents": "write"},
    "attest": {"contents": "read", "id-token": "write", "attestations": "write"},
}
jobs = workflow.get("jobs")
parsed_permissions = (
    {name: job.get("permissions") for name, job in jobs.items()}
    if isinstance(jobs, dict) and all(isinstance(job, dict) for job in jobs.values())
    else None
)
permission_result = (
    "exact"
    if workflow.get("permissions") == {} and parsed_permissions == expected_permissions
    else str(parsed_permissions)
)
joined = "\n".join(attest_block)
print("clean" if not any("Validate published release assets" in line or "Generate SLSA attestation" in line for line in release_block) else "mixed")
print(value("needs:")); print(value("runs-on:"))
print(permission_result)
print("absent" if "actions/checkout" not in joined else "present")
print("absent" if not any(token in joined for token in ("Smoke test binary", "chmod +x", "--version")) else "present")
print("present" if all(token in joined for token in (
    "releases/tags/", "git/ref/tags/", "releases/assets/", "per_page", "O_EXCL",
    "release-assets.githubusercontent.com", "MAX_ASSETS = 32", "MAX_JSON = 1024 * 1024",
)) else "missing")
print("present" if all(token in joined for token in ("dir_fd=directory_fd", "O_NOFOLLOW", "os.fstat")) else "missing")
print(next((line.strip() for line in attest_block if line.strip().startswith("subject-name:")), "missing"))
print(next((line.strip() for line in attest_block if line.strip().startswith("subject-digest:")), "missing"))
print("absent" if not any(line.strip().startswith(("subject-path:", "subject-checksums:")) for line in attest_block) else "present")
PY
)
  record "release job excludes validation and attestation" "clean" "$(printf '%s\n' "$metadata" | sed -n '1p')"
  record "attest job needs release" "needs: release" "$(printf '%s\n' "$metadata" | sed -n '2p')"
  record "attest job uses fresh pinned runner" "runs-on: ubuntu-24.04" "$(printf '%s\n' "$metadata" | sed -n '3p')"
  record "every release job has exact scoped permissions" "exact" "$(printf '%s\n' "$metadata" | sed -n '4p')"
  record "attest job has no checkout" "absent" "$(printf '%s\n' "$metadata" | sed -n '5p')"
  record "attest job does not execute release binaries" "absent" "$(printf '%s\n' "$metadata" | sed -n '6p')"
  record "attest job downloads release tag ref and assets" "present" "$(printf '%s\n' "$metadata" | sed -n '7p')"
  record "attest validator uses FD-relative nofollow reads" "present" "$(printf '%s\n' "$metadata" | sed -n '8p')"
  record "attestation subject name is checksums.txt" "subject-name: checksums.txt" "$(printf '%s\n' "$metadata" | sed -n '9p')"
  record "attestation uses validated digest output" \
    "subject-digest: sha256:\${{ steps.validate.outputs.checksums-digest }}" "$(printf '%s\n' "$metadata" | sed -n '10p')"
  record "attestation has no path or checksums reopening" "absent" "$(printf '%s\n' "$metadata" | sed -n '11p')"
}

run_readme_verification_case() {
  local name=$1 mode=$2 expected=$3
  local repo="$TEST_ROOT/readme-${name//[^a-zA-Z0-9]/-}"
  local remote="$repo/remote" status=0 actual=success
  mkdir -p "$remote/assets" "$repo/fake-bin" "$repo/tmp"
  printf '%s\n' 'first published asset' > "$remote/assets/first.tar.gz"
  printf '%s\n' 'second published asset' > "$remote/assets/second.zip"
  (cd "$remote/assets" && sha256sum first.tar.gz second.zip > checksums.txt)
  python3 - "$remote" <<'PY'
import hashlib
from pathlib import Path
import sys
root = Path(sys.argv[1])
rows = []
for asset_id, name in enumerate(("checksums.txt", "first.tar.gz", "second.zip"), 101):
    data = (root / "assets" / name).read_bytes()
    rows.append(f"{asset_id}\t{name}\t{len(data)}\tsha256:{hashlib.sha256(data).hexdigest()}")
(root / "assets.tsv").write_text("\n".join(rows) + "\n")
bad = rows.copy()
bad[1] = bad[1].rsplit("\t", 1)[0] + "\tsha256:" + "0" * 64
(root / "assets-bad.tsv").write_text("\n".join(bad) + "\n")
PY
  cat > "$repo/fake-bin/gh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1-}" == attestation && "${2-}" == verify ]]; then
  [[ "$FIXTURE_MODE" != attestation-failure ]]
  exit
fi
case "$*" in
  *releases/tags/v1.2.3*) printf '%s\n' 77 ;;
  *releases/77/assets?per_page=50*)
    if [[ "$FIXTURE_MODE" == digest-mismatch ]]; then
      cat "$GH_FIXTURE/assets-bad.tsv"
    else
      cat "$GH_FIXTURE/assets.tsv"
    fi
    ;;
  *releases/assets/101*) cat "$GH_FIXTURE/assets/checksums.txt" ;;
  *releases/assets/102*) cat "$GH_FIXTURE/assets/first.tar.gz" ;;
  *releases/assets/103*) cat "$GH_FIXTURE/assets/second.zip" ;;
  *) printf 'unexpected gh invocation: %s\n' "$*" >&2; exit 2 ;;
esac
SH
  cat > "$repo/fake-bin/find" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
"$REAL_FIND" "$@"
if [[ "$FIXTURE_MODE" == inventory-diff ]]; then
  printf '%s\n' unexpected.bin
fi
SH
  cat > "$repo/fake-bin/mkdir" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$FIXTURE_MODE" == mkdir-failure ]]; then
  exit 73
fi
exec "$REAL_MKDIR" "$@"
SH
  chmod +x "$repo/fake-bin/gh" "$repo/fake-bin/find" "$repo/fake-bin/mkdir"

  PATH="$repo/fake-bin:$PATH" GH_FIXTURE="$remote" FIXTURE_MODE="$mode" \
    REAL_FIND="$(command -v find)" REAL_MKDIR="$(command -v mkdir)" \
    TMPDIR="$repo/tmp" REPO=owner/repo TAG=v1.2.3 \
    bash "$TEST_ROOT/readme-verify.sh" >"$repo/run.log" 2>&1 || status=$?
  (( status == 0 )) || actual=failure
  record "$name" "$expected" "$actual"
  record "$name removes temporary verification state" empty \
    "$([[ -z "$(find "$repo/tmp" -mindepth 1 -print -quit)" ]] && echo empty || echo retained)"
}

assert_readme_signer_ref_consistency() {
  local metadata examples identity guidance signer pagination inventory_warning shell_safety
  metadata=$(python3 - "$README" <<'PY'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text()
refs = re.findall(r"pablontiv/crossbeam/\.github/workflows/go-release\.yml@(v[0-9]+)", text)
identities = re.findall(
    r"https://github\.com/pablontiv/crossbeam/\.github/workflows/go-release\.yml@refs/tags/(v[0-9]+)",
    text,
)
print("v2" if refs and set(refs) == {"v2"} else ",".join(refs) or "missing")
print("v2" if identities == ["v2"] else ",".join(identities) or "missing")
print("present" if "@refs/tags/v1" in text and "@<exact-40-character-crossbeam-SHA>" in text else "missing")
print("present" if "--signer-workflow pablontiv/crossbeam/.github/workflows/go-release.yml" in text else "missing")
print("present" if all(value in text for value in (
    "RELEASE_ID=$(gh api", "gh api --paginate", "/releases/$RELEASE_ID/assets?per_page=50",
    "(.digest //", '"$VERIFY_ROOT/remote.names"', '"$VERIFY_ROOT/downloaded.names"',
)) else "missing")
print("present" if "sha256sum --check` alone" in text and "remote release inventory" in text else "missing")
heading = text.index("### Verify a Go release")
start = text.index("```bash\n", heading) + len("```bash\n")
end = text.index("\n```", start)
block = text[start:end]
print("present" if block.splitlines()[0] == "set -euo pipefail" and 'trap cleanup EXIT' in block else "missing")
PY
)
  examples=$(printf '%s\n' "$metadata" | sed -n '1p')
  identity=$(printf '%s\n' "$metadata" | sed -n '2p')
  guidance=$(printf '%s\n' "$metadata" | sed -n '3p')
  signer=$(printf '%s\n' "$metadata" | sed -n '4p')
  pagination=$(printf '%s\n' "$metadata" | sed -n '5p')
  inventory_warning=$(printf '%s\n' "$metadata" | sed -n '6p')
  shell_safety=$(printf '%s\n' "$metadata" | sed -n '7p')
  record "README release examples use v2" "v2" "$examples"
  record "README verifier identity uses v2" "v2" "$identity"
  record "README explains v1 and SHA signer refs" "present" "$guidance"
  record "README uses signer-workflow without ref" "present" "$signer"
  record "README enumerates paginated release assets" "present" "$pagination"
  record "README does not equate sha256sum with inventory proof" "present" "$inventory_warning"
  record "README recipe enables strict mode and cleanup trap" "present" "$shell_safety"
}

extract_release_script
extract_smoke_script
extract_attest_scripts
extract_readme_verify_script

echo "=== Post-1.0 policy ==="
run_case "breaking defaults to minor" v2.3.4 5 "" v2.4.0 true feat \
  "feat!: change command contract" ""
run_case "docs-only creates no release" v2.3.4 5 "" "" false other \
  "docs: clarify usage" ""
run_case "fix creates patch" v2.3.4 5 "" v2.3.5 true fix \
  "fix: repair command" ""
run_case "perf creates patch" v2.3.4 5 "" v2.3.5 true perf \
  "perf: reduce allocations" ""
run_case "breaking trailer defaults to minor" v2.3.4 5 "" v2.4.0 true other \
  "refactor: change command contract" "BREAKING CHANGE: command output changed"
run_case "force major overrides breaking minor" v2.3.4 5 major v3.0.0 true feat \
  "feat!: change command contract" ""
run_case "force minor overrides patch" v2.3.4 5 minor v2.4.0 true fix \
  "fix: repair command" ""
run_case "force patch overrides breaking minor" v2.3.4 5 patch v2.3.5 true feat \
  "feat!: change command contract" ""
run_case "feat outranks fix across range" v2.3.4 5 "" v2.4.0 true feat \
  "fix: repair command" "" \
  "feat: add command" ""
run_case "breaking outranks feat across range" v2.3.4 5 "" v2.4.0 true feat \
  "feat: add command" "" \
  "refactor!: change command contract" "" \
  "fix: repair command" ""

echo ""
echo "=== Pre-1.0 graduation policy ==="
run_case "fix stays patch before 1.0" v0.2.14 5 "" v0.2.15 true fix \
  "fix: repair command" ""
run_case "feat stays minor before threshold" v0.2.14 5 "" v0.3.0 true feat \
  "feat: add command" ""
run_case "maintenance creates no release before 1.0" v0.2.14 5 "" "" false other \
  "test: expand coverage" ""
run_case "breaking still graduates at threshold" v0.5.4 5 "" v1.0.0 true feat \
  "feat!: change command contract" ""
run_case "custom threshold still graduates" v0.3.1 3 "" v1.0.0 true feat \
  "feat: add command" ""
run_case "disabled graduation stays in 0.x" v0.10.0 0 "" v0.11.0 true feat \
  "feat: add command" ""

echo ""
echo "=== Initial repository policy ==="
run_case "first feat creates v0.1.0" none 5 "" v0.1.0 true feat \
  "feat: add command" ""
run_case "first fix creates v0.0.1" none 5 "" v0.0.1 true fix \
  "fix: repair command" ""
run_case "first maintenance commit creates no tag" none 5 "" "" false other \
  "docs: explain command" ""

echo ""
echo "=== Validation and downstream gating ==="
assert_invalid_force_bump_fails
assert_release_job_skips_without_created_tag

echo ""
echo "=== Go release binary smoke test ==="
assert_smoke_darwin_first_linux_selected
assert_smoke_version_flag_succeeds
assert_smoke_version_fallback_succeeds
assert_smoke_both_version_commands_fail
assert_smoke_zero_matches_fails
assert_smoke_multiple_matches_fail
assert_smoke_missing_path_fails
assert_smoke_missing_file_fails
assert_smoke_outside_dist_fails
assert_smoke_missing_manifest_fails
assert_smoke_invalid_manifest_fails
assert_empty_binary_name_preserves_static_skip

echo ""
echo "=== Isolated published release attestation ==="
run_download_helper_tests
run_published_asset_case "valid published assets pass" valid success
run_published_asset_case "missing checksum file fails" missing-file failure
run_published_asset_case "missing asset checksum fails" missing-entry failure
run_published_asset_case "tampered published asset fails" tampered failure
run_published_asset_case "extra downloaded asset fails" extra-existing failure
run_published_asset_case "duplicate checksum fails" duplicate failure
run_published_asset_case "traversing checksum fails" traversal failure
run_published_asset_case "absolute checksum fails" absolute failure
run_published_asset_case "duplicate release JSON keys fail" duplicate-json-key failure
run_published_asset_case "non-finite release JSON fails" nonfinite-json failure
run_published_asset_case "oversized release JSON fails" oversized-json failure
run_published_asset_case "oversized checksum manifest fails" oversized-manifest failure
run_published_asset_case "oversized individual asset fails" oversized-asset failure
run_published_asset_case "oversized aggregate fails" oversized-aggregate failure
run_published_asset_case "malformed release asset record fails" malformed-asset failure
run_published_asset_case "remote inventory missing checksum fails" remote-missing-checksum failure
run_published_asset_case "remote-only asset fails" remote-extra failure
run_published_asset_case "remote casefold collision fails" remote-casefold failure
run_published_asset_case "remote path alias fails" remote-alias failure
run_published_asset_case "zero-sized API asset fails" zero-size failure
run_published_asset_case "API digest mismatch fails" api-digest-mismatch failure
run_published_asset_case "symlink published asset fails" symlink-asset failure
run_published_asset_case "symlink checksum manifest fails" symlink-checksum failure
run_published_asset_case "concurrent published asset mutation fails" concurrent-mutation failure
assert_isolated_attestation_job
run_readme_verification_case "README verification recipe passes valid release" valid success
run_readme_verification_case "README verification fails on attestation error" attestation-failure failure
run_readme_verification_case "README verification fails on inventory diff" inventory-diff failure
run_readme_verification_case "README verification fails on API digest mismatch" digest-mismatch failure
run_readme_verification_case "README verification fails when mkdir fails" mkdir-failure failure
assert_readme_signer_ref_consistency

echo ""
printf 'Results: %d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
