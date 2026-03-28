#!/usr/bin/env bash
# Post-merge: sync skills, rebuild binary, propagate doc aggregates
# Parameterized by ecosystem — see templates/ecosystems/*.yml

[ -z "$HOME" ] && HOME=$(eval echo ~)

REPO_ROOT="$(git rev-parse --show-toplevel)"
PROJECT_NAME="{{PROJECT_NAME}}"

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

  # Propagate aggregate values after merge (fix stale parent READMEs)
  rootline fix --all "$REPO_ROOT/docs/epics/" 2>/dev/null || true
else
  echo "Warning: $PROJECT_NAME rebuild failed"
fi
