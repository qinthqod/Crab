# Security Policy

## Supported versions

Security fixes are provided for the latest published Crab release.

## Reporting a vulnerability

Please do not open a public issue for a vulnerability that could cause data loss,
path traversal, unsafe command execution, or disclosure of local user data. Use
GitHub's private vulnerability reporting feature for this repository instead.

Include the affected version, macOS version, reproduction steps, and the expected
versus observed safety boundary. Do not include real private files, access tokens,
conversation content, or other personal data.

## Safety model

- Crab scans file metadata and reviewed local databases; it does not upload user data.
- Cache cleanup accepts only exact reviewed cache leaves.
- Project cleanup accepts only automatically associated project roots explicitly
  selected by the user.
- Cleanup plans expire and targets are revalidated before execution.
- Cleanup moves items to the macOS Trash. Crab has no permanent-delete operation.
- Symbolic-link path chains and changed file identities fail closed.

See [safe-scan.md](docs/specs/safe-scan.md) and
[archive-trash-execution.md](docs/specs/archive-trash-execution.md) for the detailed
contracts.
