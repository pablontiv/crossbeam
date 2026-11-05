# Changelog

All notable changes to this project will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Releases are automated via CI from conventional commits.

## [Unreleased]

### Added

- `go-release.yml`: `release-on` input (`push` | `explicit`). With `explicit`, pushes to the default branch accumulate and a tag is cut only on `workflow_dispatch` or `schedule`, with the bump computed over the whole batch. Default `push` keeps the previous behaviour.
- `LICENSE`, `SECURITY.md`, `CODE_OF_CONDUCT.md`, `CONTRIBUTING.md`, `CHANGELOG.md` at repo root (ecosystem documentation baseline)
- Squash-only merge + delete-branch-on-merge enabled via GitHub settings
