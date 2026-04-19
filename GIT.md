# Git Management Strategy

This document outlines the Git branching and versioning strategy for the `acp-cli-manager` project.

## 1. Branching Strategy (GitHub Flow)

- **`main`**: Stable production branch. Only contains the final, tested code (e.g., `README.md`, `.gitignore`) and merge points from `dev`.
- **`dev`**: Primary development branch. All feature integrations and daily development happen here.

### Branch Naming Convention
- **`feature/*`**: New feature development (e.g., `feature/explorer`).
- **`fix/*`**: Bug fixes (e.g., `fix/memory-leak`).
- **`refactor/*`**: Code restructuring without changing behavior.
- **`docs/*`**: Documentation updates.

## 2. Versioning (Semantic Versioning)

Use tags to manage releases (e.g., `v0.0.1`):
- **Major**: Significant architecture changes or breaking changes.
- **Minor**: New feature additions.
- **Patch**: Bug fixes and minor maintenance.

## 3. Workflow

1. Sync with remote: `git pull origin dev`
2. Develop and commit locally.
3. Push changes: `git push origin dev`
4. Release: Merge `dev` into `main`, tag the version, and push.

## 4. Commit Message Convention

- `feat:` New feature
- `fix:` Bug fix
- `docs:` Documentation changes
- `style:` Formatting/UI changes (no logic changes)
- `refactor:` Code restructuring
- `chore:` Build system or library updates
