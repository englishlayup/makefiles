# Agent Notes

## Documentation

- Be concise.
- Keep comments minimal. Code should be self-documenting and easy to read. Make an exception if a code block handles complex logic; focus on the why instead of the how. Also points out common gotchas.
- Keep the READMEs up-to-date when making changes.

## Decision Making

- Function and variable name must be precise.
- Each new line of code is a liability. Consider how a functionality can be split into testable units before implementation.
- Keep the user in the loop for major changes. Don't assume the user understood your recap after. Instead, quiz them on your plan to make sure there are no gaps.
- Fail fast. Don't be afraid to crash the app if something unexpected happens. Add assertions/ checks to confirm invariants.

## DevX

- Keep `gitignore` up-to-date so that `git add .` only add necessary files.
- Use the `Makefile` targets as much as possible. If there is a command that you use a lot, add it to the Makefile.
- Keep the git history bisect-able. Every commit must pass `make test/full`. This is enforced in `.githooks/pre-commit`.
