#!/usr/bin/env bash
# Pre-commit: format check, lint, and secret scan
# Parameterized by ecosystem — see templates/ecosystems/*.yml

{{FORMAT_CHECK}}

{{LINT_CHECK}}

# Scan staged changes for secrets
if command -v gitleaks &>/dev/null; then
  gitleaks git --pre-commit --staged
else
  echo "Warning: gitleaks not installed, skipping secret scan"
fi
