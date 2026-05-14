# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| Latest  | Yes       |

## Scope

Crossbeam provides reusable GitHub Actions workflows. Security concerns include:

- SHA-pinned action references bypassed or replaced with tag-pinned ones
- Workflow inputs that allow injection via untrusted user input
- Secrets exposed in workflow logs
- Supply chain attacks via compromised upstream actions

## Reporting a Vulnerability

If you discover a security vulnerability, please report it responsibly:

1. **Do not** open a public issue
2. Use GitHub's [private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability)
3. Include steps to reproduce and affected workflow/version
4. Allow reasonable time for a fix before public disclosure

## Security Measures

This project uses:
- SHA-pinned GitHub Actions to prevent supply chain attacks
- [Gitleaks](https://github.com/gitleaks/gitleaks) for secret scanning
- [OpenSSF Scorecard](https://securityscorecards.dev/) for supply chain security
- Minimal `permissions` blocks on all workflows
