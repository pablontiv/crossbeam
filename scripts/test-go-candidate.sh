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
extract_step "Snapshot source workspace before build" "$TEST_ROOT/snapshot-before.sh"
extract_step "Verify source workspace after build" "$TEST_ROOT/verify-after.sh"
extract_step "Bound and stage raw dist" "$TEST_ROOT/stage-raw.sh"
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
binary_dir="$TEST_ROOT/binaries"
mkdir -p "$binary_dir"
for platform in linux_amd64 linux_arm64 darwin_amd64 darwin_arm64 windows_amd64 windows_arm64; do
  goos=${platform%_*}
  goarch=${platform#*_}
  suffix=
  [[ "$goos" == windows ]] && suffix=.exe
  (
    cd "$fixture_repo"
    CGO_ENABLED=0 GOOS="$goos" GOARCH="$goarch" GOTOOLCHAIN=local \
      go build -ldflags "-X main.version=$candidate_version" \
      -o "$binary_dir/${platform}${suffix}"
  )
done
(
  cd "$fixture_repo"
  GOTOOLCHAIN=local go build -ldflags "-X main.version=$candidate_version" -o "$TEST_ROOT/tool-host"
  printf '\n// dirty build fixture\n' >> main.go
  CGO_ENABLED=0 GOOS=linux GOARCH=amd64 GOTOOLCHAIN=local \
    go build -ldflags "-X main.version=$candidate_version" -o "$binary_dir/linux_amd64_dirty"
  git checkout -- main.go
)
go_version=$(go env GOVERSION)
go_version=${go_version#go}
real_go=$(command -v go)
mkdir -p "$TEST_ROOT/go-inspector-bin"
cat > "$TEST_ROOT/go-inspector-bin/go" <<'GOINSPECT'
#!/usr/bin/env bash
output=$("$REAL_GO" "$@")
case "${MOCK_BUILDINFO_MISMATCH:-}" in
  goos) output=${output/GOOS=linux/GOOS=xxxxx} ;;
  goarch) output=${output/GOARCH=amd64/GOARCH=xxxxx} ;;
esac
printf '%s\n' "$output"
GOINSPECT
chmod +x "$TEST_ROOT/go-inspector-bin/go"

make_raw() {
  local dir=$1 mode=${2:-valid}
  mkdir -p "$dir/raw/dist"
  python3 - "$binary_dir" "$dir/raw/dist" "$mode" <<'PY'
from pathlib import Path
import gzip
import hashlib
import io
import json
import stat
import struct
import sys
import tarfile
import zipfile

binaries = Path(sys.argv[1])
dist = Path(sys.argv[2])
mode = sys.argv[3]
platforms = [
    ("linux", "amd64"), ("linux", "arm64"),
    ("darwin", "amd64"), ("darwin", "arm64"),
    ("windows", "amd64"), ("windows", "arm64"),
]
archives = []

def binary_for(goos, goarch):
    suffix = ".exe" if goos == "windows" else ""
    override = None
    if mode == "header-linux" and (goos, goarch) == ("linux", "amd64"):
        override = ("linux", "arm64")
    elif mode == "header-darwin" and (goos, goarch) == ("darwin", "amd64"):
        override = ("darwin", "arm64")
    elif mode == "header-windows" and (goos, goarch) == ("windows", "amd64"):
        override = ("windows", "arm64")
    actual_os, actual_arch = override or (goos, goarch)
    actual_suffix = ".exe" if actual_os == "windows" else ""
    path = binaries / f"{actual_os}_{actual_arch}{actual_suffix}"
    if mode == "vcs-modified" and (goos, goarch) == ("linux", "amd64"):
        path = binaries / "linux_amd64_dirty"
    data = path.read_bytes()
    if mode == "buildinfo-goos" and (goos, goarch) == ("linux", "amd64"):
        changed = data.replace(b"GOOS=linux", b"GOOS=xxxxx", 1)
        if changed == data: raise SystemExit("GOOS build setting fixture not found")
        data = changed
    if mode == "buildinfo-goarch" and (goos, goarch) == ("linux", "amd64"):
        changed = data.replace(b"GOARCH=amd64", b"GOARCH=xxxxx", 1)
        if changed == data: raise SystemExit("GOARCH build setting fixture not found")
        data = changed
    if mode == "elf-class" and (goos, goarch) == ("linux", "amd64"):
        data = data[:4] + b"\x01" + data[5:]
    if mode == "elf-endian" and (goos, goarch) == ("linux", "amd64"):
        data = data[:5] + b"\x02" + data[6:]
    if mode == "pe32" and (goos, goarch) == ("windows", "amd64"):
        offset = struct.unpack_from("<I", data, 0x3C)[0] + 24
        data = data[:offset] + b"\x0b\x01" + data[offset + 2:]
    return data

def add_tar(bundle, name, data=b"x", permissions=0o644, kind=tarfile.REGTYPE, link=""):
    info = tarfile.TarInfo(name)
    info.mode = permissions
    info.type = kind
    info.linkname = link
    if kind == tarfile.REGTYPE:
        info.size = len(data)
        bundle.addfile(info, io.BytesIO(data))
    else:
        bundle.addfile(info)

def add_zip(bundle, name, data=b"x", permissions=0o644, kind=stat.S_IFREG):
    info = zipfile.ZipInfo(name)
    info.create_system = 3
    info.external_attr = (kind | permissions) << 16
    bundle.writestr(info, data, compress_type=zipfile.ZIP_DEFLATED)

for goos, goarch in platforms:
    suffix = ".zip" if goos == "windows" else ".tar.gz"
    archive_name = f"tool_{goos}_{goarch}{suffix}"
    archive = dist / archive_name
    expected_binary = "tool.exe" if goos == "windows" else "tool"
    payload = binary_for(goos, goarch)
    if goos == "windows":
        with zipfile.ZipFile(archive, "w") as bundle:
            binary_name = expected_binary
            if mode == "windows-no-exe" and goarch == "amd64": binary_name = "tool"
            if mode == "zip-dir" and goarch == "amd64": add_zip(bundle, "docs/", b"", 0o755, stat.S_IFDIR)
            elif mode == "zip-symlink" and goarch == "amd64": add_zip(bundle, "link", b"target", 0o777, stat.S_IFLNK)
            else:
                add_zip(bundle, binary_name, payload, 0o755)
                add_zip(bundle, "README.md", b"representative roadmapctl docs", 0o644)
                if goarch == "arm64": add_zip(bundle, "docs/USAGE.md", b"nested regular docs", 0o644)
                malware = {
                    "windows-malware-exe": "malware.exe",
                    "windows-malware-dll": "malware.dll",
                    "windows-malware-cmd": "malware.cmd",
                    "windows-malware-ps1": "malware.ps1",
                }.get(mode)
                if malware and goarch == "amd64": add_zip(bundle, malware, b"not documentation", 0o644)
    else:
        with tarfile.open(archive, "w:gz") as bundle:
            is_primary = (goos, goarch) == ("linux", "amd64")
            if is_primary and mode == "traversal": add_tar(bundle, "../tool", payload, 0o755)
            elif is_primary and mode == "absolute": add_tar(bundle, "/tool", payload, 0o755)
            elif is_primary and mode == "backslash": add_tar(bundle, "bin\\tool", payload, 0o755)
            elif is_primary and mode == "noncanonical": add_tar(bundle, "docs//USAGE.md", b"x", 0o644); add_tar(bundle, "tool", payload, 0o755)
            elif is_primary and mode == "symlink": add_tar(bundle, "tool", kind=tarfile.SYMTYPE, permissions=0o777, link="target")
            elif is_primary and mode == "hardlink": add_tar(bundle, "tool", kind=tarfile.LNKTYPE, permissions=0o777, link="target")
            elif is_primary and mode == "device": add_tar(bundle, "tool", kind=tarfile.CHRTYPE, permissions=0o600)
            elif is_primary and mode == "fifo": add_tar(bundle, "tool", kind=tarfile.FIFOTYPE, permissions=0o600)
            elif is_primary and mode == "tar-dir": add_tar(bundle, "docs", kind=tarfile.DIRTYPE, permissions=0o755); add_tar(bundle, "tool", payload, 0o755)
            elif is_primary and mode == "pax": add_tar(bundle, "pax", b"path=tool\n", 0o644, tarfile.XHDTYPE); add_tar(bundle, "tool", payload, 0o755)
            elif is_primary and mode == "gnu-longname": add_tar(bundle, "././@LongLink", b"tool\x00", 0o644, tarfile.GNUTYPE_LONGNAME); add_tar(bundle, "tool", payload, 0o755)
            elif is_primary and mode == "hidden": add_tar(bundle, ".hidden", b"x", 0o644); add_tar(bundle, "tool", payload, 0o755)
            elif is_primary and mode == "duplicate": add_tar(bundle, "tool", payload, 0o755); add_tar(bundle, "tool", payload, 0o755)
            elif is_primary and mode == "casefold": add_tar(bundle, "README.md", b"x", 0o644); add_tar(bundle, "readme.md", b"y", 0o644); add_tar(bundle, "tool", payload, 0o755)
            elif is_primary and mode == "entry-bomb":
                for number in range(129): add_tar(bundle, f"file-{number}", b"", 0o644)
                add_tar(bundle, "tool", payload, 0o755)
            elif is_primary and mode == "unix-exe": add_tar(bundle, "tool.exe", payload, 0o755)
            elif is_primary and mode == "nested-binary": add_tar(bundle, "bin/tool", payload, 0o755)
            elif is_primary and mode == "ambiguous-binary": add_tar(bundle, "tool", payload, 0o755); add_tar(bundle, "docs/tool.exe", payload, 0o755)
            elif is_primary and mode == "binary-nonexec": add_tar(bundle, "tool", payload, 0o644)
            elif is_primary and mode == "binary-world-write": add_tar(bundle, "tool", payload, 0o777)
            elif is_primary and mode == "binary-setuid": add_tar(bundle, "tool", payload, 0o4755)
            elif is_primary and mode == "docs-executable": add_tar(bundle, "tool", payload, 0o755); add_tar(bundle, "README.md", b"x", 0o755)
            elif is_primary and mode == "arbitrary-payload": add_tar(bundle, "tool", payload, 0o755); add_tar(bundle, "payload.bin", b"arbitrary", 0o644)
            elif is_primary and mode == "binary-document": add_tar(bundle, "tool", payload, 0o755); add_tar(bundle, "README.md", b"text\x00binary", 0o644)
            elif is_primary and mode == "invalid-utf8-document": add_tar(bundle, "tool", payload, 0o755); add_tar(bundle, "README.md", b"\xff\xfe", 0o644)
            elif is_primary and mode == "control-document": add_tar(bundle, "tool", payload, 0o755); add_tar(bundle, "README.md", b"text\x07control", 0o644)
            elif is_primary and mode == "unicode-c1-85": add_tar(bundle, "tool", payload, 0o755); add_tar(bundle, "README.md", "text\u0085control".encode(), 0o644)
            elif is_primary and mode == "unicode-c1-9b": add_tar(bundle, "tool", payload, 0o755); add_tar(bundle, "README.md", "text\u009bcontrol".encode(), 0o644)
            elif is_primary and mode == "unicode-bidi-202e": add_tar(bundle, "tool", payload, 0o755); add_tar(bundle, "README.md", "text\u202eformat".encode(), 0o644)
            elif is_primary and mode == "unicode-bidi-2066": add_tar(bundle, "tool", payload, 0o755); add_tar(bundle, "README.md", "text\u2066format".encode(), 0o644)
            else:
                add_tar(bundle, expected_binary, payload, 0o755)
                docs = b"representative backscroll docs" if goos == "linux" else b"representative rootline docs"
                add_tar(bundle, "LICENSE", docs, 0o644)
                if goarch == "amd64": add_tar(bundle, "README.md", "Documentación segura — español".encode(), 0o644)
    archives.append({"type": "Archive", "name": archive_name, "path": f"dist/{archive_name}", "goos": goos, "goarch": goarch})

primary_tar = dist / "tool_linux_amd64.tar.gz"
primary_zip = dist / "tool_windows_amd64.zip"

def ustar_header(name, size, permissions=0o644, kind=b"0"):
    header = bytearray(512)
    header[:len(name)] = name.encode("ascii")
    def octal(offset, length, value):
        encoded = f"{value:0{length - 1}o}".encode("ascii") + b"\x00"
        header[offset:offset + length] = encoded
    octal(100, 8, permissions); octal(108, 8, 0); octal(116, 8, 0)
    octal(124, 12, size); octal(136, 12, 0)
    header[148:156] = b" " * 8
    header[156:157] = kind
    header[257:263] = b"ustar\x00"
    header[263:265] = b"00"
    checksum = sum(header)
    header[148:156] = f"{checksum:06o}".encode("ascii") + b"\x00 "
    return bytes(header)

if mode in ("tar-huge-declared", "tar-truncated", "tar-high-ratio"):
    if mode == "tar-huge-declared": size, payload = 256 * 1024 * 1024 + 1, b""
    elif mode == "tar-high-ratio": size, payload = 256 * 1024 * 1024, b""
    else: size, payload = 1024, b"short"
    with gzip.open(primary_tar, "wb") as stream:
        stream.write(ustar_header("tool", size, 0o755))
        stream.write(payload)

if mode in ("zip64", "zip-many", "zip-huge-central"):
    entries = 0xFFFF if mode == "zip64" else (129 if mode == "zip-many" else 1)
    central_size = 0 if mode != "zip-huge-central" else 4 * 1024 * 1024 + 1
    prefix = b"PAYLOAD_MUST_NOT_BE_READ"
    eocd = struct.pack("<4s4H2LH", b"PK\x05\x06", 0, 0, entries, entries, central_size, 0, 0)
    primary_zip.write_bytes(prefix + eocd)
elif mode in ("zip-corrupt-doc", "zip-local-name"):
    with zipfile.ZipFile(primary_zip) as bundle:
        info = next(value for value in bundle.infolist() if value.filename == "README.md")
        offset = info.header_offset
    with primary_zip.open("r+b") as stream:
        stream.seek(offset)
        fixed = stream.read(30)
        name_size, extra_size = struct.unpack_from("<HH", fixed, 26)
        if mode == "zip-local-name":
            stream.seek(offset + 30)
            raw_name = stream.read(name_size)
            stream.seek(offset + 30)
            stream.write(b"X" + raw_name[1:])
        else:
            data_offset = offset + 30 + name_size + extra_size
            stream.seek(data_offset + max(info.compress_size // 2, 0))
            original = stream.read(1)
            stream.seek(data_offset + max(info.compress_size // 2, 0))
            stream.write(bytes([original[0] ^ 0xFF]))

checksum_lines = []
for item in sorted(archives, key=lambda value: value["path"]):
    archive = dist / Path(item["path"]).name
    checksum_lines.append(f"{hashlib.sha256(archive.read_bytes()).hexdigest()}  {archive.name}")
if mode == "checksum-mismatch": checksum_lines[0] = "0" * 64 + checksum_lines[0][64:]
if mode == "checksum-extra": checksum_lines.append("0" * 64 + "  extra.tar.gz")
if mode == "checksum-duplicate": checksum_lines.append(checksum_lines[0])
(dist / "checksums.txt").write_text("\n".join(checksum_lines) + "\n")
if mode == "reserved-archive":
    (dist / "candidate.json").write_bytes((dist / Path(archives[0]["path"]).name).read_bytes())
    archives[0]["path"] = "dist/candidate.json"
if mode == "duplicate-archive-path":
    archives[1]["path"] = archives[0]["path"]
if mode == "untrusted-artifact-name":
    for item in archives: item["name"] = {"untrusted": ["object"]}
checksum_item = {"type": "Checksum", "name": "checksums", "path": "dist/checksums.txt"}
if mode == "reserved-checksum": checksum_item["path"] = "dist/metadata.json"
artifacts = archives + [checksum_item]
if mode == "wrapper-shape": artifacts = {"artifacts": artifacts}
(dist / "artifacts.json").write_text(json.dumps(artifacts))
if mode == "config-extra": (dist / "config.yaml").write_text("should not be uploaded\n")
PY
  python3 - "$dir" "$fixture_sha" "$candidate_version" <<'PY'
import json
from pathlib import Path
import sys
root = Path(sys.argv[1]) / "raw/dist"
(root / "metadata.json").write_text(json.dumps({"commit": sys.argv[2], "version": sys.argv[3]}))
PY
}

echo ""
echo "=== Post-build provenance and raw allowlist ==="
stage_fixture="$TEST_ROOT/stage-fixture"
make_raw "$stage_fixture/generated" config-extra
mkdir -p "$stage_fixture/source"
git init -b main "$stage_fixture/source" >/dev/null
configure_git "$stage_fixture/source"
printf 'dist/\nignored-generated.txt\n' > "$stage_fixture/source/.gitignore"
printf 'trusted\n' > "$stage_fixture/source/tracked.txt"
git -C "$stage_fixture/source" add .gitignore tracked.txt
git -C "$stage_fixture/source" commit -m "chore: stage fixture" >/dev/null
stage_sha=$(git -C "$stage_fixture/source" rev-parse HEAD)
snapshot_path="$stage_fixture/source-snapshot.json"
expect_status "pre-build workspace snapshot succeeds" success "$stage_fixture/snapshot.log" \
  env SNAPSHOT_PATH="$snapshot_path" bash -c "cd '$stage_fixture' && '$TEST_ROOT/snapshot-before.sh'"
cp -R "$stage_fixture/generated/raw/dist" "$stage_fixture/source/dist"
expect_status "clean exact HEAD and workspace snapshot pass" success "$stage_fixture/clean.log" \
  env SOURCE_SHA="$stage_sha" SNAPSHOT_PATH="$snapshot_path" \
  bash -c "cd '$stage_fixture' && '$TEST_ROOT/verify-after.sh'"
expect_status "clean build stages only raw allowlist" success "$stage_fixture/stage.log" \
  env RAW_ROOT="$stage_fixture/staged" bash -c "cd '$stage_fixture' && '$TEST_ROOT/stage-raw.sh'"
staged_count=$(find "$stage_fixture/staged/dist" -maxdepth 1 -type f | wc -l | tr -d ' ')
record "raw stage has control files checksum and six archives" 9 "$staged_count"
record "raw stage excludes config.yaml" absent "$([[ -e "$stage_fixture/staged/dist/config.yaml" ]] && echo present || echo absent)"
printf 'mutated\n' >> "$stage_fixture/source/tracked.txt"
expect_status "tracked build mutation rejected" failure "$stage_fixture/mutation.log" \
  env SOURCE_SHA="$stage_sha" SNAPSHOT_PATH="$snapshot_path" \
  bash -c "cd '$stage_fixture' && '$TEST_ROOT/verify-after.sh'"
git -C "$stage_fixture/source" checkout -- tracked.txt
printf 'hook output\n' > "$stage_fixture/source/hook-output.txt"
expect_status "untracked hook output rejected" failure "$stage_fixture/hook.log" \
  env SOURCE_SHA="$stage_sha" SNAPSHOT_PATH="$snapshot_path" \
  bash -c "cd '$stage_fixture' && '$TEST_ROOT/verify-after.sh'"
rm "$stage_fixture/source/hook-output.txt"
printf 'ignored mutation\n' > "$stage_fixture/source/ignored-generated.txt"
record "ignored mutation is absent from git status" clean \
  "$([[ -z "$(git -C "$stage_fixture/source" status --porcelain --untracked-files=all)" ]] && echo clean || echo dirty)"
expect_status "ignored generated source rejected by workspace snapshot" failure "$stage_fixture/ignored.log" \
  env SOURCE_SHA="$stage_sha" SNAPSHOT_PATH="$snapshot_path" \
  bash -c "cd '$stage_fixture' && '$TEST_ROOT/verify-after.sh'"
rm "$stage_fixture/source/ignored-generated.txt"
expect_status "changed HEAD rejected" failure "$stage_fixture/head.log" \
  env SOURCE_SHA=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb SNAPSHOT_PATH="$snapshot_path" \
  bash -c "cd '$stage_fixture' && '$TEST_ROOT/verify-after.sh'"

run_static_case() {
  local name=$1 mode=$2 expected=$3 expected_go=${4:-$go_version}
  local dir="$TEST_ROOT/static-${name// /-}"
  local inspect_path=$PATH mismatch=
  if [[ "$mode" == buildinfo-goos ]]; then
    inspect_path="$TEST_ROOT/go-inspector-bin:$PATH"
    mismatch=goos
  elif [[ "$mode" == buildinfo-goarch ]]; then
    inspect_path="$TEST_ROOT/go-inspector-bin:$PATH"
    mismatch=goarch
  fi
  make_raw "$dir" "$mode"
  expect_status "$name" "$expected" "$dir/run.log" \
    env PATH="$inspect_path" REAL_GO="$real_go" MOCK_BUILDINFO_MISMATCH="$mismatch" \
    SOURCE_SHA="$fixture_sha" CANDIDATE_VERSION="$candidate_version" \
    BINARY_NAME=tool GO_VERSION="$expected_go" \
    bash -c "cd '$dir' && '$TEST_ROOT/static.sh'"
}
run_static_case "direct-list six-target TAR and ZIP archives pass" valid success
run_static_case "archive traversal rejected" traversal failure
run_static_case "absolute archive member rejected" absolute failure
run_static_case "backslash archive member rejected" backslash failure
run_static_case "noncanonical archive member rejected" noncanonical failure
run_static_case "archive symlink rejected" symlink failure
run_static_case "archive hardlink rejected" hardlink failure
run_static_case "archive device rejected" device failure
run_static_case "archive FIFO rejected" fifo failure
run_static_case "archive TAR directory rejected" tar-dir failure
run_static_case "PAX header rejected" pax failure
run_static_case "GNU longname header rejected" gnu-longname failure
run_static_case "huge declared TAR member rejected before payload" tar-huge-declared failure
run_static_case "truncated TAR payload rejected" tar-truncated failure
run_static_case "high-ratio TAR rejected before payload" tar-high-ratio failure
run_static_case "archive ZIP symlink rejected" zip-symlink failure
run_static_case "archive ZIP directory rejected" zip-dir failure
run_static_case "ZIP64 sentinel rejected in preflight" zip64 failure
run_static_case "many-entry ZIP rejected in preflight" zip-many failure
run_static_case "huge ZIP central directory rejected in preflight" zip-huge-central failure
run_static_case "corrupt ZIP documentation payload rejected" zip-corrupt-doc failure
run_static_case "ZIP local and central filename mismatch rejected" zip-local-name failure
run_static_case "hidden archive member rejected" hidden failure
run_static_case "duplicate archive member rejected" duplicate failure
run_static_case "casefold collision rejected" casefold failure
run_static_case "archive entry bomb rejected" entry-bomb failure
run_static_case "Unix exe suffix rejected" unix-exe failure
run_static_case "Windows extensionless binary rejected" windows-no-exe failure
run_static_case "nested binary rejected" nested-binary failure
run_static_case "ambiguous platform binary copies rejected" ambiguous-binary failure
run_static_case "non-executable binary rejected" binary-nonexec failure
run_static_case "world-writable binary rejected" binary-world-write failure
run_static_case "setuid binary rejected" binary-setuid failure
run_static_case "executable documentation rejected" docs-executable failure
run_static_case "arbitrary TAR payload rejected" arbitrary-payload failure
run_static_case "binary documentation payload rejected" binary-document failure
run_static_case "invalid UTF-8 documentation rejected" invalid-utf8-document failure
run_static_case "control characters in documentation rejected" control-document failure
run_static_case "Unicode C1 U+0085 rejected" unicode-c1-85 failure
run_static_case "Unicode C1 U+009B rejected" unicode-c1-9b failure
run_static_case "Unicode bidi U+202E rejected" unicode-bidi-202e failure
run_static_case "Unicode bidi U+2066 rejected" unicode-bidi-2066 failure
run_static_case "Windows malware exe rejected even non-executable" windows-malware-exe failure
run_static_case "Windows malware dll rejected even non-executable" windows-malware-dll failure
run_static_case "Windows malware cmd rejected even non-executable" windows-malware-cmd failure
run_static_case "Windows malware ps1 rejected even non-executable" windows-malware-ps1 failure
run_static_case "checksum mismatch rejected" checksum-mismatch failure
run_static_case "extra checksum rejected" checksum-extra failure
run_static_case "duplicate checksum rejected" checksum-duplicate failure
run_static_case "wrapped speculative artifacts shape rejected" wrapper-shape failure
run_static_case "reserved archive basename rejected" reserved-archive failure
run_static_case "reserved checksum basename rejected" reserved-checksum failure
run_static_case "duplicate archive path rejected without set masking" duplicate-archive-path failure
run_static_case "raw config and intermediates excluded" config-extra failure
run_static_case "ELF architecture label mismatch rejected" header-linux failure
run_static_case "Mach-O architecture label mismatch rejected" header-darwin failure
run_static_case "PE architecture label mismatch rejected" header-windows failure
run_static_case "ELF32 class rejected" elf-class failure
run_static_case "big-endian ELF rejected" elf-endian failure
run_static_case "PE32 instead of PE32+ rejected" pe32 failure
run_static_case "dirty VCS build rejected" vcs-modified failure
run_static_case "build-info GOOS mismatch rejected" buildinfo-goos failure
run_static_case "build-info GOARCH mismatch rejected" buildinfo-goarch failure
run_static_case "exact compiler version rejects substring" valid failure "${go_version}0"
for preflight_log in \
  "$TEST_ROOT/static-ZIP64-sentinel-rejected-in-preflight/run.log" \
  "$TEST_ROOT/static-many-entry-ZIP-rejected-in-preflight/run.log" \
  "$TEST_ROOT/static-huge-ZIP-central-directory-rejected-in-preflight/run.log"; do
  record "ZIP rejection is explicitly preflighted: $(basename "$(dirname "$preflight_log")")" present \
    "$(grep -q 'ZIP preflight' "$preflight_log" && echo present || echo absent)"
done
record "TAR ratio rejected before payload read" present \
  "$(grep -q 'before payload read' "$TEST_ROOT/static-high-ratio-TAR-rejected-before-payload/run.log" && echo present || echo absent)"

echo ""
echo "=== Isolated smoke and deterministic publication ==="
smoke_dir="$TEST_ROOT/smoke-valid"
make_raw "$smoke_dir" valid
# Smoke execution must be host-native in local tests (macOS or Linux). Static
# validation above independently verifies the real linux/amd64 ELF fixture.
python3 - "$TEST_ROOT/tool-host" "$smoke_dir/raw/dist" <<'PY'
from pathlib import Path
import hashlib
import io
import sys
import tarfile
binary = Path(sys.argv[1]).read_bytes()
dist = Path(sys.argv[2])
archive = dist / "tool_linux_amd64.tar.gz"
with tarfile.open(archive, "w:gz") as bundle:
    info = tarfile.TarInfo("tool")
    info.mode = 0o755
    info.size = len(binary)
    bundle.addfile(info, io.BytesIO(binary))
    doc = tarfile.TarInfo("README.md")
    doc.mode = 0o644
    doc.size = 4
    bundle.addfile(doc, io.BytesIO(b"docs"))
lines = []
for line in (dist / "checksums.txt").read_text().splitlines():
    name = line.split("  ", 1)[1]
    if name == archive.name:
        line = f"{hashlib.sha256(archive.read_bytes()).hexdigest()}  {name}"
    lines.append(line)
(dist / "checksums.txt").write_text("\n".join(lines) + "\n")
PY
extract_output="$smoke_dir/extract-output"
if [[ "$(uname -s)" == Linux ]] && command -v sudo >/dev/null && sudo -n -u nobody true >/dev/null 2>&1 && [[ -x /usr/bin/timeout ]]; then
  smoke_runner_temp="$smoke_dir/runner-temp"
  mkdir -p "$smoke_runner_temp"
  expect_status "safe smoke extraction creates nobody-owned sandbox" success "$smoke_dir/extract.log" \
    env BINARY_NAME=tool GITHUB_OUTPUT="$extract_output" RUNNER_TEMP="$smoke_runner_temp" \
    bash -c "cd '$smoke_dir' && '$TEST_ROOT/extract.sh'"
  sandbox=$(sed -n 's/^sandbox=//p' "$extract_output")
  binary=$(sed -n 's/^binary=//p' "$extract_output")
  record "smoke binary is owned by nobody" nobody "$(stat -c '%U' "$binary")"
  expect_status "isolated candidate smoke succeeds as nobody" success "$smoke_dir/smoke.log" \
    env SANDBOX="$sandbox" SMOKE_BINARY="$binary" CANDIDATE_VERSION="$candidate_version" \
    "$TEST_ROOT/smoke.sh"
  expect_status "smoke version failure blocks success" failure "$smoke_dir/smoke-fail.log" \
    env SANDBOX="$sandbox" SMOKE_BINARY="$binary" CANDIDATE_VERSION=9.9.9-bad \
    "$TEST_ROOT/smoke.sh"

  malicious="$smoke_dir/proc-environ-probe"
  cat > "$malicious" <<PROBE
#!/bin/sh
pid=\$PPID
while [ "\$pid" -gt 1 ] 2>/dev/null; do
  if tr '\\0' '\\n' < "/proc/\$pid/environ" 2>/dev/null | grep -q '^SMOKE_SENTINEL_SECRET='; then
    echo "sentinel leaked from ancestor"
    exit 97
  fi
  pid=\$(awk '{print \$4}' "/proc/\$pid/stat" 2>/dev/null || echo 1)
done
printf '%s\n' 'tool $candidate_version'
PROBE
  sudo -n install -o nobody -g "$(id -gn nobody)" -m 0500 "$malicious" "$sandbox/probe"
  expect_status "malicious candidate cannot read sentinel from ancestor environments" success "$smoke_dir/probe.log" \
    env SMOKE_SENTINEL_SECRET=must-not-leak SANDBOX="$sandbox" SMOKE_BINARY="$sandbox/probe" \
    CANDIDATE_VERSION="$candidate_version" "$TEST_ROOT/smoke.sh"
else
  record "dynamic nobody smoke requires Linux passwordless sudo" skipped skipped
  record "dynamic ancestor environ probe requires Linux procfs" skipped skipped
  record "dynamic timeout smoke requires ubuntu coreutils" skipped skipped
fi
record "failed smoke creates no final staging" absent "$([[ -e "$smoke_dir/candidate-upload" ]] && echo present || echo absent)"
python3 - "$smoke_dir/raw/dist/artifacts.json" <<'PY'
import json
from pathlib import Path
import sys
path = Path(sys.argv[1])
artifacts = json.loads(path.read_text())
for item in artifacts:
    if item.get("type") == "Archive":
        item["name"] = {"untrusted": ["must not reach manifest"]}
path.write_text(json.dumps(artifacts))
PY
run_publish_invalid() {
  local name=$1 source=$2 base=$3 base_version=$4 version=$5 pr=$6 binary_name=$7
  expect_status "$name" failure "$smoke_dir/${name// /-}.log" \
    env SOURCE_SHA="$source" BASE_SHA="$base" BASE_VERSION="$base_version" \
    CANDIDATE_VERSION="$version" PR_NUMBER="$pr" BINARY_NAME="$binary_name" \
    GITHUB_OUTPUT="$smoke_dir/invalid-output" bash -c "cd '$smoke_dir' && '$TEST_ROOT/publish.sh'"
}
run_publish_invalid "manifest rejects uppercase source SHA" "${fixture_sha^^}" \
  bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb v1.2.3 "$candidate_version" 42 tool
run_publish_invalid "manifest rejects malformed base SHA" "$fixture_sha" short \
  v1.2.3 "$candidate_version" 42 tool
run_publish_invalid "manifest rejects malformed base version" "$fixture_sha" \
  bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb 1.2.3 "$candidate_version" 42 tool
run_publish_invalid "manifest rejects malformed candidate version" "$fixture_sha" \
  bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb v1.2.3 bad-version 42 tool
run_publish_invalid "manifest rejects unsafe binary scalar" "$fixture_sha" \
  bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb v1.2.3 "$candidate_version" 42 ../tool
publish_output="$smoke_dir/publish-output"
expect_status "publish ignores untrusted artifact names" success "$smoke_dir/publish.log" \
  env SOURCE_SHA="$fixture_sha" BASE_SHA=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb \
  BASE_VERSION=v1.2.3 CANDIDATE_VERSION="$candidate_version" PR_NUMBER=42 BINARY_NAME=tool \
  GITHUB_OUTPUT="$publish_output" bash -c "cd '$smoke_dir' && '$TEST_ROOT/publish.sh'"
published_count=$(find "$smoke_dir/candidate-upload" -maxdepth 1 -type f | wc -l | tr -d ' ')
record "final allowlist contains six archives checksum and manifest" 8 "$published_count"
for forbidden in artifacts.json metadata.json config.yaml; do
  record "final excludes $forbidden" absent "$([[ -e "$smoke_dir/candidate-upload/$forbidden" ]] && echo present || echo absent)"
done
manifest_order=$(python3 - "$smoke_dir/candidate-upload/candidate.json" <<'PY'
import json
import sys
value = json.load(open(sys.argv[1]))
expected = {
    ("linux", "amd64"), ("linux", "arm64"),
    ("darwin", "amd64"), ("darwin", "arm64"),
    ("windows", "amd64"), ("windows", "arm64"),
}
matrix = {(item["goos"], item["goarch"]) for item in value["archives"]}
names = {item["name"] for item in value["archives"]}
valid = list(value) == sorted(value) and value["archives"] == sorted(value["archives"], key=lambda item: item["file"]) and matrix == expected and names == {"tool"}
print("valid" if valid else "invalid")
PY
)
record "six-target manifest is deterministic" valid "$manifest_order"

echo ""
echo "=== DAG, permissions, artifact identity, and trusted inputs ==="
static_result=$(python3 - "$WORKFLOW" <<'PY'
from pathlib import Path
import re
import sys
text = Path(sys.argv[1]).read_text()
smoke_job = text.split("  smoke:\n", 1)[1].split("\n  publish:\n", 1)[0]
execute_section = smoke_job.split("      - name: Execute candidate in empty environment\n", 1)[1]
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
    "smoke execution is last": "\n      - name:" not in execute_section,
    "smoke uses distinct nobody UID": "sudo -n -u nobody -- /usr/bin/env -i" in execute_section,
    "timeout is inside sanitized command": execute_section.index("/usr/bin/env -i") < execute_section.index("/usr/bin/timeout 30s"),
    "smoke receives no runtime credentials": all(value not in execute_section for value in ("ACTIONS_", "github.token", "GITHUB_TOKEN", "GH_TOKEN")),
    "sandbox leaves runner-owned ancestry": "mktemp -d /var/tmp/go-candidate-smoke.XXXXXX" in smoke_job and 'install -o "$smoke_user"' in smoke_job,
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
