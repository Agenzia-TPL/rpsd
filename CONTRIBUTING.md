# Contributing to rpsd

Thank you for considering contributing to this project. This document explains how to report bugs, propose changes, and the conventions we follow.

## Reporting Bugs

Please report bugs using [GitHub Issues](https://github.com/Agenzia-TPL/rpsd/issues). Include:

- A clear description of the problem.
- Steps to reproduce the issue.
- Expected vs. actual behaviour.
- Your environment (OS, Docker version, etc.).

For security vulnerabilities, **do not** open a public issue. Instead, contact the maintainers privately through the channels listed in the repository settings.

## Proposing Changes

1. **Fork** the repository and create a feature branch from `main`.
2. Make your changes in small, focused commits.
3. Ensure your changes follow the coding standards described below.
4. Open a **Pull Request** against `main` with a clear description of what your changes do and why.

## Coding Standards

### Bash Scripts

- Begin every script with `#!/bin/bash` and `set -e`.
- Source shared helpers from `scripts/_lib.sh` instead of duplicating logic.
- Use the output helpers: `print_info`, `print_success`, `print_warn`, `print_error`.
- Scripts must work on macOS, Linux, and Windows (Git Bash / WSL2).

### Docker Compose / YAML

- Follow existing formatting and indentation patterns.
- Every `image:` value must use a variable with a public default: `${RPSD_IMAGE_X:-public/image:tag}`.
- Host port mappings must follow the `19xxx` / `20xxx` schema documented in the README.

### General

- Keep changes focused — one logical change per pull request.
- Read `DECISIONS.md` before making changes that affect the platform structure.
- Add trailing newlines to all files.

## SPDX Headers

Every new source file (`.sh`, `.yml`, `.yaml`, `.sql`, `Dockerfile`, etc.) **must** include SPDX copyright and licence headers. Use the appropriate comment style for the file type:

```
# SPDX-FileCopyrightText: 2026 AGENZIA TPL BACINO CITTA' METROPOLITANA MILANO, MONZA E BRIANZA, LODI, PAVIA
# SPDX-License-Identifier: EUPL-1.2
```

For SQL files, use `--` comments instead of `#`.

## Contributor Licence Agreement

By submitting a pull request to this project, you certify that:

1. You have the right to submit the contribution under the project's licence (EUPL-1.2).
2. Your contribution is your original work, or you have the necessary rights to submit it.
3. You grant the project maintainer the right to redistribute your contributions under any OSI-approved open-source licence, including future versions of EUPL or compatible licences such as AGPL-3.0-or-later.

This lightweight CLA is accepted implicitly by opening a pull request. No separate signature is required.

## Licence

This project is licensed under the [European Union Public Licence v. 1.2](LICENSE).
