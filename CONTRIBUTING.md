# Contributing to Crab

Thank you for helping make AI-tool storage safer on macOS.

## Before opening a pull request

1. Keep cleanup scope narrow and product-specific.
2. Add or update deterministic tests for every behavior change.
3. Run:

   ```bash
   swift run crab-core-tests
   swift build -c release
   bash scripts/check-dangerous-apis.sh
   ```

4. Never add a cache rule for chats, model weights, project contents, downloads,
   credentials, or an application's broad data directory.
5. Never add permanent deletion or arbitrary-path cleanup.

## Adding an application or cache rule

Rules must name an exact, regenerable cache leaf and include user-facing safety,
impact, and recovery text. Add fixtures and tests that prove path traversal and
symbolic links fail closed. A directory merely being large is not evidence that it
is safe to clean.

## Pull requests

Keep changes focused, explain the user-visible outcome, and call out any change to
the Trash, process-execution, update, or permission boundaries. By contributing,
you agree that your contribution is licensed under the MIT License.

The same release checks run automatically through
[`.github/workflows/ci.yml`](.github/workflows/ci.yml) on every pull request and
push to `main`.
