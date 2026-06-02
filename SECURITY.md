# Security Policy

Tacket handles saved local AI chats, code, images, and attachment references. Please do not publish vulnerability details in a public issue before maintainers have had a chance to investigate.

## Supported Versions

Tacket is pre-1.0. Security fixes target the current tagged release and the `main` branch.

## Dependency Alerts

GitHub Dependabot alerts and automated security fixes are enabled for the public repository. Dependabot version updates are configured for npm dependencies and GitHub Actions in `.github/dependabot.yml`.

## Reporting a Vulnerability

GitHub private vulnerability reporting is enabled for the repository. Use it for vulnerability reports instead of opening a public issue with exploit details. If private reporting is temporarily unavailable, open a minimal public issue asking for a maintainer security contact, without including exploit details, private chat text, tokens, screenshots, or proof-of-concept payloads.

Useful reports include:

- the affected Tacket version or commit
- macOS and Chrome versions
- whether the issue affects saving chats, the local Chrome app connection, local file writing, library indexing/search, transfer automation, or release packaging
- a minimal reproduction that does not include real private chat content or credentials

## Local Data Expectations

Tacket should not upload saved chat content, telemetry, analytics, crash reports, or model/API requests. Saved Tacket chat folders and the local library database are files controlled by the user and may contain sensitive data. Security fixes should preserve the product guarantee that library, search, and transfer paths do not summarize, redact, or remotely process conversation content.
