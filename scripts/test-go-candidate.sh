#!/usr/bin/env bash
# Exercises inline candidate workflow logic and its isolation/security contract.
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
WORKFLOW="$ROOT/.github/workflows/go-candidate.yml"
TEST_ROOT=$(mktemp -d)
PASS=0
FAIL=0
cleanup() { rm -rf "$TEST_ROOT"; }
trap cleanup EXIT

record() {
  local name=$1 expected=$2 actual=$3
  if [[ "$actual" == "$expected" ]]; then
    printf '  PASS: %s\n' "$name"
    PASS=$((PASS + 1))
  else
    printf '  FAIL: %s -> expected %s, got %s\n' "$name" "$expected" "$actual"
    FAIL=$((FAIL + 1))
  fi
}

expect_status() {
  local name=$1 expected=$2 log=$3
  shift 3
  local status=0
  "$@" >"$log" 2>&1 || status=$?
  if [[ "$expected" == success && $status -eq 0 ]]; then
    record "$name" success success
  elif [[ "$expected" == failure && $status -ne 0 ]]; then
    record "$name" failure failure
  else
    record "$name" "$expected" "status-$status"
    sed -n '1,80p' "$log" >&2 || true
  fi
}

extract_step() {
  local name=$1 output=$2
  python3 - "$WORKFLOW" "$name" "$output" <<'PY'
from pathlib import Path
import sys
lines = Path(sys.argv[1]).read_text().splitlines()
name, output = sys.argv[2], Path(sys.argv[3])
step = next(i for i, line in enumerate(lines) if line == f"      - name: {name}")
run = next(i for i in range(step + 1, len(lines)) if lines[i] == "        run: |")
body = []
for line in lines[run + 1:]:
    if line and not line.startswith("          "):
        break
    body.append(line[10:] if line else "")
output.write_text("#!/usr/bin/env bash\nset -euo pipefail\n" + "\n".join(body) + "\n")
PY
  chmod +x "$output"
}

extract_step "Validate PR and base graph" "$TEST_ROOT/metadata.sh"
extract_step "Validate raw candidate statically" "$TEST_ROOT/static.sh"
extract_step "Extract only validated smoke binary" "$TEST_ROOT/extract.sh"
extract_step "Execute candidate in empty environment" "$TEST_ROOT/smoke.sh"
extract_step "Revalidate inventory and create manifest" "$TEST_ROOT/publish.sh"

configure_git() {
  git -C "$1" config user.name Test
  git -C "$1" config user.email test@example.com
}

echo "=== Trusted metadata and base graph ==="
base="$TEST_ROOT/base"
remote="$TEST_ROOT/base.git"
home="$TEST_ROOT/home"
mock_bin="$TEST_ROOT/mock-bin"
mkdir -p "$home" "$mock_bin"
git init --bare "$remote" >/dev/null
git init -b main "$base" >/dev/null
configure_git "$base"
printf 'one\n' > "$base/history"
git -C "$base" add history
git -C "$base" commit -m "chore: base tag" >/dev/null
git -C "$base" tag v1.2.3
git -C "$base" tag v1.2.4-rc.1
printf 'two\n' >> "$base/history"
git -C "$base" add history
git -C "$base" commit -m "fix: base tip" >/dev/null
base_sha=$(git -C "$base" rev-parse HEAD)
git -C "$base" remote add origin "$remote"
git -C "$base" push origin main --tags >/dev/null
HOME="$home" git config --global url."file://$remote".insteadOf https://github.com/base/repo.git
cat > "$mock_bin/curl" <<'CURL'
#!/usr/bin/env bash
cat "$MOCK_PR_PAYLOAD"
CURL
chmod +x "$mock_bin/curl"
source_lower=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
source_upper=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
payload="$TEST_ROOT/pr.json"
python3 - "$payload" "$source_lower" "$base_sha" <<'PY'
import json
from pathlib import Path
import sys
Path(sys.argv[1]).write_text(json.dumps({
    "head": {"repo": {"full_name": "fork/repo"}, "sha": sys.argv[2]},
    "base": {"sha": sys.argv[3], "ref": "main"},
}))
PY
metadata_output="$TEST_ROOT/metadata-output"
expect_status "uppercase SHA inputs normalize and valid base graph passes" success "$TEST_ROOT/metadata.log" \
  env HOME="$home" PATH="$mock_bin:$PATH" MOCK_PR_PAYLOAD="$payload" GH_TOKEN=test \
  GITHUB_API_URL=https://api.github.test CALLER_REPOSITORY=base/repo \
  SOURCE_REPOSITORY=fork/repo SOURCE_SHA_INPUT="$source_upper" BASE_SHA_INPUT="${base_sha^^}" \
  PR_NUMBER=42 BINARY_NAME=tool GO_VERSION=1.24.1 GORELEASER_CONFIG=.goreleaser.yml \
  GITHUB_OUTPUT="$metadata_output" "$TEST_ROOT/metadata.sh"
record "source SHA output is lowercase" "$source_lower" "$(sed -n 's/^source_sha=//p' "$metadata_output")"
record "candidate derives from stable tag merged in base SHA" \
  "1.2.4-pr.42.gaaaaaaa" "$(sed -n 's/^candidate_version=//p' "$metadata_output")"
printf 'three\n' >> "$base/history"
git -C "$base" add history
git -C "$base" commit -m "fix: advance base" >/dev/null
git -C "$base" push origin main >/dev/null
expect_status "divergent stale base graph fails closed" failure "$TEST_ROOT/divergent.log" \
  env HOME="$home" PATH="$mock_bin:$PATH" MOCK_PR_PAYLOAD="$payload" GH_TOKEN=test \
  GITHUB_API_URL=https://api.github.test CALLER_REPOSITORY=base/repo \
  SOURCE_REPOSITORY=fork/repo SOURCE_SHA_INPUT="$source_lower" BASE_SHA_INPUT="$base_sha" \
  PR_NUMBER=42 BINARY_NAME=tool GO_VERSION=1.24.1 GORELEASER_CONFIG=.goreleaser.yml \
  GITHUB_OUTPUT="$TEST_ROOT/divergent-output" "$TEST_ROOT/metadata.sh"
expect_status "minor-only Go toolchain rejected" failure "$TEST_ROOT/go-version.log" \
  env HOME="$home" PATH="$mock_bin:$PATH" MOCK_PR_PAYLOAD="$payload" GH_TOKEN=test \
  GITHUB_API_URL=https://api.github.test CALLER_REPOSITORY=base/repo \
  SOURCE_REPOSITORY=fork/repo SOURCE_SHA_INPUT="$source_lower" BASE_SHA_INPUT="$base_sha" \
  PR_NUMBER=42 BINARY_NAME=tool GO_VERSION=1.24 GORELEASER_CONFIG=.goreleaser.yml \
  GITHUB_OUTPUT="$TEST_ROOT/version-output" "$TEST_ROOT/metadata.sh"
expect_status "traversing base config rejected" failure "$TEST_ROOT/config-path.log" \
  env HOME="$home" PATH="$mock_bin:$PATH" MOCK_PR_PAYLOAD="$payload" GH_TOKEN=test \
  GITHUB_API_URL=https://api.github.test CALLER_REPOSITORY=base/repo \
  SOURCE_REPOSITORY=fork/repo SOURCE_SHA_INPUT="$source_lower" BASE_SHA_INPUT="$base_sha" \
  PR_NUMBER=42 BINARY_NAME=tool GO_VERSION=1.24.1 GORELEASER_CONFIG=../release.yml \
  GITHUB_OUTPUT="$TEST_ROOT/config-output" "$TEST_ROOT/metadata.sh"

echo ""
echo "=== Static archive validation ==="
fixture_repo="$TEST_ROOT/binary-source"
mkdir -p "$fixture_repo"
git init -b main "$fixture_repo" >/dev/null
configure_git "$fixture_repo"
cat > "$fixture_repo/go.mod" <<'MOD'
module example.test/candidate

go 1.21.0
MOD
cat > "$fixture_repo/main.go" <<'GO'
package main
import (
  "fmt"
  "os"
)
var version = "dev"
func main() {
  if len(os.Args) == 2 && os.Args[1] == "--version" { fmt.Println("tool " + version); return }
  os.Exit(2)
}
GO
git -C "$fixture_repo" add go.mod main.go
git -C "$fixture_repo" commit -m "feat: fixture" >/dev/null
fixture_sha=$(git -C "$fixture_repo" rev-parse HEAD)
candidate_version="1.2.4-pr.42.g${fixture_sha:0:7}"
(
  cd "$fixture_repo"
  GOTOOLCHAIN=local go build -ldflags "-X main.version=$candidate_version" -o "$TEST_ROOT/tool"
)
go_version=$(go env GOVERSION)
go_version=${go_version#go}

make_raw() {
  local dir=$1 mode=${2:-valid}
  mkdir -p "$dir/raw/dist"
  python3 - "$TEST_ROOT/tool" "$dir/raw/dist/tool_linux_amd64.tar.gz" "$mode" <<'PY'
from pathlib import Path
import io
import sys
import tarfile
binary = Path(sys.argv[1]).read_bytes()
out = sys.argv[2]
mode = sys.argv[3]
with tarfile.open(out, "w:gz") as bundle:
    def regular(name, data=binary):
        info = tarfile.TarInfo(name)
        info.mode = 0o755
        info.size = len(data)
        bundle.addfile(info, io.BytesIO(data))
    if mode == "traversal": regular("../tool")
    elif mode == "absolute": regular("/tool")
    elif mode == "symlink":
        info = tarfile.TarInfo("tool"); info.type = tarfile.SYMTYPE; info.linkname = "target"; bundle.addfile(info)
    elif mode == "hardlink":
        info = tarfile.TarInfo("tool"); info.type = tarfile.LNKTYPE; info.linkname = "target"; bundle.addfile(info)
    elif mode == "device":
        info = tarfile.TarInfo("tool"); info.type = tarfile.CHRTYPE; bundle.addfile(info)
    elif mode == "hidden":
        regular(".hidden", b"x"); regular("tool")
    elif mode == "duplicate":
        regular("tool"); regular("tool")
    elif mode == "casefold":
        regular("TOOL", b"x"); regular("tool")
    elif mode == "entry-bomb":
        for number in range(129): regular(f"file-{number}", b"")
        regular("tool")
    else: regular("tool")
PY
  (
    cd "$dir/raw/dist"
    sha256sum tool_linux_amd64.tar.gz > checksums.txt
  )
  python3 - "$dir" "$fixture_sha" "$candidate_version" <<'PY'
import json
from pathlib import Path
import sys
root = Path(sys.argv[1]) / "raw/dist"
(root / "metadata.json").write_text(json.dumps({"commit": sys.argv[2], "version": sys.argv[3]}))
(root / "artifacts.json").write_text(json.dumps({"artifacts": [
    {"type": "Archive", "name": "tool", "path": "dist/tool_linux_amd64.tar.gz", "goos": "linux", "goarch": "amd64"},
    {"type": "Checksum", "name": "checksums", "path": "dist/checksums.txt"},
]}))
PY
}

run_static_case() {
  local name=$1 mode=$2 expected=$3 expected_go=${4:-$go_version}
  local dir="$TEST_ROOT/static-${name// /-}"
  make_raw "$dir" "$mode"
  expect_status "$name" "$expected" "$dir/run.log" \
    env SOURCE_SHA="$fixture_sha" CANDIDATE_VERSION="$candidate_version" \
    BINARY_NAME=tool GO_VERSION="$expected_go" \
    bash -c "cd '$dir' && '$TEST_ROOT/static.sh'"
}
run_static_case "valid archive passes without execution" valid success
run_static_case "archive traversal rejected" traversal failure
run_static_case "absolute archive member rejected" absolute failure
run_static_case "archive symlink rejected" symlink failure
run_static_case "archive hardlink rejected" hardlink failure
run_static_case "archive device rejected" device failure
run_static_case "hidden archive member rejected" hidden failure
run_static_case "duplicate archive member rejected" duplicate failure
run_static_case "casefold collision rejected" casefold failure
run_static_case "archive entry bomb rejected" entry-bomb failure
run_static_case "toolchain mismatch rejected" valid failure 0.0.1

echo ""
echo "=== Isolated smoke and deterministic publication ==="
smoke_dir="$TEST_ROOT/smoke-valid"
make_raw "$smoke_dir" valid
extract_output="$smoke_dir/extract-output"
expect_status "safe smoke extraction succeeds" success "$smoke_dir/extract.log" \
  env BINARY_NAME=tool GITHUB_OUTPUT="$extract_output" \
  bash -c "cd '$smoke_dir' && '$TEST_ROOT/extract.sh'"
sandbox=$(sed -n 's/^sandbox=//p' "$extract_output")
binary=$(sed -n 's/^binary=//p' "$extract_output")
# macOS lacks GNU timeout; this fixture preserves the workflow command contract
# while the actual ubuntu-24.04 runner supplies coreutils timeout.
cat > "$mock_bin/timeout" <<'TIMEOUT'
#!/usr/bin/env bash
shift
exec "$@"
TIMEOUT
chmod +x "$mock_bin/timeout"
expect_status "isolated candidate smoke succeeds" success "$smoke_dir/smoke.log" \
  env PATH="$mock_bin:$PATH" SANDBOX="$sandbox" SMOKE_BINARY="$binary" \
  CANDIDATE_VERSION="$candidate_version" "$TEST_ROOT/smoke.sh"
expect_status "smoke version failure blocks success" failure "$smoke_dir/smoke-fail.log" \
  env PATH="$mock_bin:$PATH" SANDBOX="$sandbox" SMOKE_BINARY="$binary" \
  CANDIDATE_VERSION=9.9.9-bad "$TEST_ROOT/smoke.sh"
record "failed smoke creates no final staging" absent "$([[ -e "$smoke_dir/candidate-upload" ]] && echo present || echo absent)"
publish_output="$smoke_dir/publish-output"
expect_status "publish revalidation and manifest succeed" success "$smoke_dir/publish.log" \
  env SOURCE_SHA="$fixture_sha" BASE_SHA=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb \
  BASE_VERSION=v1.2.3 CANDIDATE_VERSION="$candidate_version" PR_NUMBER=42 \
  GITHUB_OUTPUT="$publish_output" bash -c "cd '$smoke_dir' && '$TEST_ROOT/publish.sh'"
published=$(find "$smoke_dir/candidate-upload" -maxdepth 1 -type f -exec basename {} \; | sort | tr '\n' ',')
record "final allowlist is exact" "candidate.json,checksums.txt,tool_linux_amd64.tar.gz," "$published"
manifest_order=$(python3 - "$smoke_dir/candidate-upload/candidate.json" <<'PY'
import json
import sys
value = json.load(open(sys.argv[1]))
print("valid" if list(value) == sorted(value) and value["archives"] == sorted(value["archives"], key=lambda item: item["file"]) else "invalid")
PY
)
record "manifest is deterministic" valid "$manifest_order"

echo ""
echo "=== DAG, permissions, artifact identity, and trusted inputs ==="
static_result=$(python3 - "$WORKFLOW" <<'PY'
from pathlib import Path
import re
import sys
text = Path(sys.argv[1]).read_text()
checks = {
    "top permissions empty": "permissions: {}" in text,
    "metadata only PR read": re.search(r"(?ms)^  metadata:.*?^    permissions:\n      pull-requests: read\n", text) is not None,
    "isolated jobs empty permissions": all(re.search(rf"(?ms)^  {job}:.*?^    permissions: \{{\}}$", text) for job in ("build", "static-validate", "smoke", "publish")),
    "same raw artifact id": text.count("artifact-ids: ${{ needs.build.outputs.raw-artifact-id }}") == 3,
    "publish waits for both validators": "needs: [metadata, build, static-validate, smoke]" in text,
    "smoke waits for static": "needs: [metadata, build, static-validate]" in text,
    "only raw and final uploads": text.count("actions/upload-artifact@") == 2,
    "final upload only in publish": text.index("Upload final validated candidate") > text.index("  publish:"),
    "no privileged triggers or permissions": all(value not in text for value in ("pull_request_target", "contents: write", "id-token:", "secrets.")),
    "toolchain cannot auto-upgrade": "GOTOOLCHAIN=local" in text and "token: ''" in text,
    "trusted base config": 'git -C source show "${BASE_SHA}:${GORELEASER_CONFIG}"' in text,
    "PR config never selected": "go-version-file" not in text and "inputs.goreleaser-config }}" not in text.split("Build candidate with sanitized environment", 1)[1],
    "goreleaser action install only": "install-only: true" in text,
    "smoke execution is last": text.rfind("- name: Execute candidate in empty environment") < text.index("  publish:"),
}
uses = re.findall(r"(?m)^\s*uses:\s*([^\s#]+)", text)
checks["actions pinned"] = bool(uses) and all(re.fullmatch(r"[^@]+@[0-9a-f]{40}", use) for use in uses)
failed = [name for name, passed in checks.items() if not passed]
print("valid" if not failed else "invalid:" + ",".join(failed))
PY
)
record "workflow isolation contract" valid "$static_result"

printf '\nResults: %d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
