#!/usr/bin/env bash
# Pre-push: validate docs, check drift, rebuild binary, sync skills
# Parameterized by ecosystem — see templates/ecosystems/*.yml

remote="$1"
REPO_ROOT="$(git rev-parse --show-toplevel)"
PROJECT_NAME="{{PROJECT_NAME}}"

while read local_ref local_sha remote_ref remote_sha; do
  # Skip delete pushes
  [ "$local_sha" = "0000000000000000000000000000000000000000" ] && continue

  if [ "$remote_sha" = "0000000000000000000000000000000000000000" ]; then
    range="$local_sha"
  else
    range="$remote_sha..$local_sha"
  fi

  # Validate docs/epics/ if changed
  if git diff --name-only "$range" -- docs/epics/ 2>/dev/null | grep -q .; then
    echo "Validating docs/epics/ before push..."
    if command -v rootline &>/dev/null; then
      if ! rootline validate --all docs/epics/ > /dev/null 2>&1; then
        echo "rootline validate --all docs/epics/ failed. Fix errors before pushing."
        echo "Run: rootline validate --all docs/epics/"
        echo "Or:  rootline fix --all docs/epics/"
        exit 1
      fi
      echo "docs/epics/ validation passed"
    else
      echo "Warning: rootline not installed, skipping docs validation"
    fi
  fi

  # Check if source code changed but docs weren't updated
  if git diff --name-only "$range" -- {{SOURCE_DIR}} 2>/dev/null | grep -q .; then
    if ! git diff --name-only "$range" -- docs/ README.md CLAUDE.md 2>/dev/null | grep -q .; then
      echo "{{SOURCE_DIR}} code changed but docs were not updated."
      echo "Update docs/, README.md, or CLAUDE.md before pushing."
      exit 1
    fi
  fi

  # Check if CI, install scripts, or build config changed but docs weren't updated
  if git diff --name-only "$range" -- {{INFRA_PATHS}} 2>/dev/null | grep -q .; then
    if ! git diff --name-only "$range" -- README.md docs/ CLAUDE.md 2>/dev/null | grep -q .; then
      echo "CI/scripts/config changed but docs were not updated."
      echo "Update README.md, docs/, or CLAUDE.md before pushing."
      exit 1
    fi
  fi

done

# Sync skills
SKILLS_SRC="$REPO_ROOT/.claude/skills"
SKILLS_DEST="$HOME/.claude/skills"
if [ -d "$SKILLS_SRC" ]; then
  mkdir -p "$SKILLS_DEST"
  for skill_dir in "$SKILLS_SRC"/*/; do
    [ -d "$skill_dir" ] || continue
    skill_name=$(basename "$skill_dir")
    [[ "$skill_name" == *-workspace ]] && continue
    rm -rf "${SKILLS_DEST:?}/$skill_name"
    cp -r "$skill_dir" "$SKILLS_DEST/$skill_name"
  done
  echo "$PROJECT_NAME: synced skills → $SKILLS_DEST"
fi

# Rebuild binary
echo "Rebuilding $PROJECT_NAME..."
if {{BUILD_RELEASE_CMD}}; then
  echo "$PROJECT_NAME rebuilt: $($PROJECT_NAME --version 2>/dev/null || echo 'installed')"
else
  echo "Warning: $PROJECT_NAME rebuild failed (push continues)"
fi
