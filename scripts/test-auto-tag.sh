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
PY
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
  record "binary-name is passed through env" 'BINARY_NAME: ${{ inputs.binary-name }}' "$env_value"
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
  local asset_dir="$repo/assets" metadata="$repo/release.json" output="$repo/github-output"
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

make_download_fixture() {
  local repo=$1
  local remote="$repo/remote"
  mkdir -p "$remote/assets" "$repo/fake-bin" "$repo/runner"
  printf '%s\n' 'first published asset' > "$remote/assets/first.tar.gz"
  printf '%s\n' 'second published asset' > "$remote/assets/second.zip"
  (cd "$remote/assets" && sha256sum first.tar.gz second.zip > checksums.txt)
  python3 - "$remote" <<'PY'
import json
from pathlib import Path
import sys
root = Path(sys.argv[1])
repository, api, server, tag = "owner/repo", "https://api.github.test", "https://github.test", "v1.2.3"
assets = []
for asset_id, name in enumerate(("checksums.txt", "first.tar.gz", "second.zip"), 101):
    assets.append({"id": asset_id, "name": name, "size": (root / "assets" / name).stat().st_size,
                   "url": f"{api}/repos/{repository}/releases/assets/{asset_id}"})
release_id = 77
(root / "release.json").write_text(json.dumps({
    "id": release_id, "tag_name": tag,
    "url": f"{api}/repos/{repository}/releases/{release_id}",
    "assets_url": f"{api}/repos/{repository}/releases/{release_id}/assets",
    "html_url": f"{server}/{repository}/releases/tag/{tag}", "draft": False, "assets": assets,
}))
(root / "tag.json").write_text(json.dumps({"ref": f"refs/tags/{tag}", "object": {"type": "commit", "sha": "a" * 40}}))
PY
  cat > "$repo/fake-bin/gh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
endpoint=${!#}
case "$endpoint" in
  */releases/tags/v1.2.3) cat "$GH_FIXTURE/release.json" ;;
  */git/ref/tags/v1.2.3) cat "$GH_FIXTURE/tag.json" ;;
  */releases/assets/101) cat "$GH_FIXTURE/assets/checksums.txt" ;;
  */releases/assets/102) cat "$GH_FIXTURE/assets/first.tar.gz" ;;
  */releases/assets/103) cat "$GH_FIXTURE/assets/second.zip" ;;
  *) printf 'unexpected gh endpoint: %s\n' "$endpoint" >&2; exit 2 ;;
esac
SH
  chmod +x "$repo/fake-bin/gh"
}

run_download_case() {
  local name=$1 event_sha=$2 expected=$3
  local repo="$TEST_ROOT/download-${name//[^a-zA-Z0-9]/-}" output status=0 actual=success
  output="$repo/github-output"
  make_download_fixture "$repo"
  PATH="$repo/fake-bin:$PATH" GH_FIXTURE="$repo/remote" RUNNER_TEMP="$repo/runner" \
    REPOSITORY=owner/repo EVENT_REPOSITORY=owner/repo EVENT_SHA="$event_sha" RELEASE_TAG=v1.2.3 \
    API_URL=https://api.github.test SERVER_URL=https://github.test GITHUB_OUTPUT="$output" \
    bash "$TEST_ROOT/download-release-assets.sh" >"$repo/download.log" 2>&1 || status=$?
  (( status == 0 )) || actual=failure
  record "$name" "$expected" "$actual"
  if [[ "$expected" == success ]]; then
    local asset_dir inventory
    asset_dir=$(sed -n 's/^asset-dir=//p' "$output")
    inventory=$(find "$asset_dir" -maxdepth 1 -type f -exec basename {} \; | sort | paste -sd, -)
    record "$name downloads exact API inventory" "checksums.txt,first.tar.gz,second.zip" "$inventory"
    local validation_status=success
    ASSET_DIR="$asset_dir" GITHUB_OUTPUT="$repo/validation-output" \
      bash "$TEST_ROOT/validate-release-assets.sh" >"$repo/download-validation.log" 2>&1 || validation_status=failure
    record "$name validates downloaded API bytes" "success" "$validation_status"
  fi
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
permissions = {line.strip() for line in header if line.startswith("      ") and ":" in line}
joined = "\n".join(attest_block)
print("clean" if not any("Validate published release assets" in line or "Generate SLSA attestation" in line for line in release_block) else "mixed")
print(value("needs:")); print(value("runs-on:"))
print("exact" if permissions == {"contents: read", "id-token: write", "attestations: write"} else ",".join(sorted(permissions)))
print("absent" if "actions/checkout" not in joined else "present")
print("absent" if not any(token in joined for token in ("Smoke test binary", "chmod +x", "--version")) else "present")
print("present" if all(token in joined for token in ("releases/tags/", "git/ref/tags/", "releases/assets/")) else "missing")
print("present" if all(token in joined for token in ("dir_fd=directory_fd", "O_NOFOLLOW", "os.fstat")) else "missing")
print(next((line.strip() for line in attest_block if line.strip().startswith("subject-name:")), "missing"))
print(next((line.strip() for line in attest_block if line.strip().startswith("subject-digest:")), "missing"))
print("absent" if not any(line.strip().startswith(("subject-path:", "subject-checksums:")) for line in attest_block) else "present")
PY
)
  record "release job excludes validation and attestation" "clean" "$(printf '%s\n' "$metadata" | sed -n '1p')"
  record "attest job needs release" "needs: release" "$(printf '%s\n' "$metadata" | sed -n '2p')"
  record "attest job uses fresh pinned runner" "runs-on: ubuntu-24.04" "$(printf '%s\n' "$metadata" | sed -n '3p')"
  record "attest job permissions are minimal" "exact" "$(printf '%s\n' "$metadata" | sed -n '4p')"
  record "attest job has no checkout" "absent" "$(printf '%s\n' "$metadata" | sed -n '5p')"
  record "attest job does not execute release binaries" "absent" "$(printf '%s\n' "$metadata" | sed -n '6p')"
  record "attest job downloads release tag ref and assets" "present" "$(printf '%s\n' "$metadata" | sed -n '7p')"
  record "attest validator uses FD-relative nofollow reads" "present" "$(printf '%s\n' "$metadata" | sed -n '8p')"
  record "attestation subject name is checksums.txt" "subject-name: checksums.txt" "$(printf '%s\n' "$metadata" | sed -n '9p')"
  record "attestation uses validated digest output" \
    "subject-digest: sha256:\${{ steps.validate.outputs.checksums-digest }}" "$(printf '%s\n' "$metadata" | sed -n '10p')"
  record "attestation has no path or checksums reopening" "absent" "$(printf '%s\n' "$metadata" | sed -n '11p')"
}

assert_readme_signer_ref_consistency() {
  local metadata examples identity guidance
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
print("present" if "@refs/tags/v1" in text and "exact SHA suffix" in text else "missing")
PY
)
  examples=$(printf '%s\n' "$metadata" | sed -n '1p')
  identity=$(printf '%s\n' "$metadata" | sed -n '2p')
  guidance=$(printf '%s\n' "$metadata" | sed -n '3p')
  record "README release examples use v2" "v2" "$examples"
  record "README verifier identity uses v2" "v2" "$identity"
  record "README explains v1 and SHA signer refs" "present" "$guidance"
}

extract_release_script
extract_smoke_script
extract_attest_scripts

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
run_download_case "downloads current published release" "$(printf 'a%.0s' {1..40})" success
run_download_case "rejects release tag event mismatch" "$(printf 'b%.0s' {1..40})" failure
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
run_published_asset_case "malformed release asset record fails" malformed-asset failure
run_published_asset_case "remote inventory missing checksum fails" remote-missing-checksum failure
run_published_asset_case "remote-only asset fails" remote-extra failure
run_published_asset_case "remote casefold collision fails" remote-casefold failure
run_published_asset_case "remote path alias fails" remote-alias failure
run_published_asset_case "symlink published asset fails" symlink-asset failure
run_published_asset_case "symlink checksum manifest fails" symlink-checksum failure
run_published_asset_case "concurrent published asset mutation fails" concurrent-mutation failure
assert_isolated_attestation_job
assert_readme_signer_ref_consistency

echo ""
printf 'Results: %d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
