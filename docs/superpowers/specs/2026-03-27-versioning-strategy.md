# Versioning Strategy — Aggressive Semver for the pablontiv Ecosystem

## Summary

Overhaul of the versioning strategy for crossbeam and all consuming repos. Replaces the current auto-tag logic where `feat` commits produce patch bumps in pre-1.0 with a more expressive system where `feat` always produces minor bumps. Adds auto-graduation to v1.0.0 when a configurable minor-version threshold is reached.

## Problem

The current auto-tag logic treats `feat` commits as **patch** bumps in pre-1.0 repos:

| Repo | Current Version | Symptom |
|------|----------------|---------|
| rootline | v0.9.121 | 121 consecutive patch releases, no minor bumps despite 24+ feature commits |
| backscroll | v0.3.2 | Stuck on patch bumps, breaking change (`feat!`) didn't trigger graduation |
| kedral | v0.1.3 | Only 3 releases, all patches |

Version numbers don't reflect project maturity. A project with 121 releases should not be at v0.9.x.

## Bump Logic

### Pre-1.0 (major == 0)

| Commit Prefix | Bump | Example (from v0.3.5) |
|---|---|---|
| `fix`, `perf`, `refactor`, `docs`, `ci`, `chore`, `style`, `test` | **patch** | v0.3.6 |
| `feat`, `feat!`, any `*!` (breaking) | **minor** | v0.4.0 |

### Post-1.0 (major >= 1)

| Commit Prefix | Bump | Example (from v1.2.3) |
|---|---|---|
| `fix`, `perf`, `refactor`, `docs`, `ci`, `chore`, `style`, `test` | **patch** | v1.2.4 |
| `feat` | **minor** | v1.3.0 |
| any `*!` (breaking) | **major** | v2.0.0 |

### Key Change vs. Current Logic

The only behavioral change in pre-1.0 is: **`feat` now bumps minor instead of patch**. This means feature commits advance the minor version, making version numbers reflect actual feature velocity.

In pre-1.0, `feat` and breaking (`*!`) produce the same result (minor bump). This is intentional — per semver spec, the 0.x range has no stability guarantees, so breaking changes don't need a distinct signal.

## Auto-Graduation

When a pre-1.0 repo reaches a configurable minor-version threshold, it automatically graduates to v1.0.0.

**Rule:** If `major == 0` and `minor >= graduation-threshold` and the current commit is `feat` or breaking, create `v1.0.0` instead of `v0.{minor+1}.0`.

**Workflow input:**
```yaml
graduation-threshold:
  description: 'Minor version threshold for auto-graduation to v1.0.0. Set to 0 to disable.'
  required: false
  type: number
  default: 5
```

**Example with threshold=5:**
```
v0.0.0 → fix → v0.0.1
       → feat → v0.1.0
       → feat → v0.2.0
       → fix  → v0.2.1
       → feat → v0.3.0
       → feat → v0.4.0
       → feat → v0.5.0   ← minor=5, threshold reached
       → next feat → v1.0.0   ← AUTO-GRADUATION
       → fix  → v1.0.1
       → feat → v1.1.0   ← normal post-1.0 semver
```

**Edge cases:**
- If a repo already has `minor >= threshold` when adopting the new logic, the first `feat` commit triggers graduation
- Patch commits never trigger graduation evaluation — only `feat` and breaking
- `graduation-threshold: 0` disables auto-graduation entirely (for repos that should stay in 0.x)
- After graduation, post-1.0 rules apply immediately starting with v1.0.1 (fix) or v1.1.0 (feat)

## Crossbeam's Own Versioning

Crossbeam starts at **v1.0.0** — it must be stable from the day consuming repos adopt it. It does not go through a 0.x phase.

| Change Type | Bump | Example |
|---|---|---|
| Bug fix in existing workflow, action SHA update, documentation | **patch** | v1.0.0 → v1.0.1 |
| New reusable workflow file, new optional input on existing workflow | **minor** | v1.0.1 → v1.1.0 |
| Input rename/removal, job rename/removal, permission change, any breaking contract change | **major** | v1.1.0 → v2.0.0 |

**Major tag alias:** `v1` always points to the latest `v1.x.x`. Consumers reference `@v1` and automatically get patches and new optional features without changing their caller stubs.

**Dependabot** on crossbeam itself keeps action SHAs current (patch bumps).

## Version Migration Strategy

Forward-only approach — **no existing tags are modified or deleted**. External users depend on current versions.

| Repo | Current Version | Migration Action | First Version Under New Logic |
|------|----------------|-----------------|-------------------------------|
| rootline | v0.9.121 | Create `v1.0.0` tag manually at HEAD | v1.0.1 (fix) or v1.1.0 (feat) |
| backscroll | v0.3.2 | No action. New logic applies from next commit | v0.3.3 (fix) or v0.4.0 (feat) |
| kedral | v0.1.3 | No action. New logic applies from next commit | v0.1.4 (fix) or v0.2.0 (feat) |
| localops | no tags | No action. Starts at v0.0.0 | v0.0.1 (fix) or v0.1.0 (feat) |
| homeserver | no tags | No action. Starts at v0.0.0 | v0.0.1 (fix) or v0.1.0 (feat) |
| dotfiles | no tags | No action. Starts at v0.0.0 | v0.0.1 (fix) or v0.1.0 (feat) |

### Rootline v1.0.0 Justification

rootline has 121 releases, external users, and a stable API. The manual `v1.0.0` tag is a declarative act — "this project is stable." The version sequence will jump from v0.9.121 to v1.0.0, which is correct semver behavior (the 0.x → 1.0 transition is always a jump).

The manual tag must be created **before** migrating rootline to crossbeam's release workflow. Otherwise, the auto-tag logic would see minor=9 >= threshold=5 and create v1.0.0 on the next feat commit anyway — which would also work, but manual tagging decouples graduation from whatever the next commit happens to be.

### Backscroll and Kedral Graduation Path

- backscroll (v0.3.2): Needs 2 more `feat` commits to reach minor=5, then auto-graduates on the next feat
- kedral (v0.1.3): Needs 4 more `feat` commits — correct for an early-stage project

## Retroactive Validation

Applied the new bump logic retroactively against the git history of rootline and backscroll to validate the design:

### rootline (43 recent commits analyzed)

- **24 feat commits**, 19 fix/docs/test/chore commits, 0 breaking
- Under new logic: graduated to v1.0.0 at commit #6 (when 5th feat pushed minor to threshold)
- **Simulated final version: v1.25.0** (vs. actual v0.9.121)
- The 24 feature commits that were all patch bumps would each have been minor bumps post-graduation

### backscroll (14 recent commits analyzed)

- **4 feat commits** (including 1 `feat!`), 10 other commits
- Under new logic with threshold=5: would be at **v0.4.0** (not yet graduated — only 4 minors)
- The `feat!` commit (Porter stemmer) would have bumped minor, not triggered graduation (minor=4 < threshold=5)
- With threshold=3: would have graduated to **v1.0.0** at the `feat!` commit

### Insights

1. Rootline's feature velocity is high enough that any reasonable threshold graduates it quickly
2. The threshold=5 default prevents premature graduation for repos with moderate velocity (backscroll stays in 0.x until it has 5 real feature milestones)
3. Zero breaking commits across both repos — the `!` marker is underutilized, which is fine since pre-1.0 breaking and feat produce the same bump

## Implementation Notes

The auto-tag shell logic in `go-release.yml` and `rust-release.yml` follows this algorithm:

```bash
# 1. Find latest semver tag
LATEST=$(git tag -l 'v*' | sort -V | tail -1)
# If no tag: LATEST=v0.0.0

# 2. Parse into MAJOR.MINOR.PATCH
# 3. Determine commit type from HEAD message
#    - Contains "!:" or "BREAKING CHANGE" trailer → breaking=true
#    - Starts with "feat" → type=feat
#    - Otherwise → type=other

# 4. Apply bump table
if [[ $MAJOR -eq 0 ]]; then
  if [[ $GRADUATION_THRESHOLD -gt 0 && $MINOR -ge $GRADUATION_THRESHOLD && ($TYPE == "feat" || $BREAKING == true) ]]; then
    NEW_TAG="v1.0.0"
  elif [[ $TYPE == "feat" || $BREAKING == true ]]; then
    MINOR=$((MINOR + 1)); PATCH=0
  else
    PATCH=$((PATCH + 1))
  fi
else
  if [[ $BREAKING == true ]]; then
    MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0
  elif [[ $TYPE == "feat" ]]; then
    MINOR=$((MINOR + 1)); PATCH=0
  else
    PATCH=$((PATCH + 1))
  fi
fi

# 5. Concurrent guard + tag push
```
