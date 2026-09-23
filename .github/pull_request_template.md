## What this changes

<!-- Describe the change and why it's needed. Link the related issue if there is one. -->

## How to test

<!-- Steps to verify the change works correctly. -->

## Checklist

- [ ] All tests pass (`⌘U` in Xcode)
- [ ] No new `Macwarden` or `macwarden` references introduced (legacy name — use `Prizm` / `prizm`)
- [ ] Follows the [AGENTS.md](../AGENTS.md) conventions (layer boundaries, design tokens, `L("key")` for user-facing strings)
- [ ] New crypto or security-critical code includes inline spec references and a security goal comment
- [ ] No secrets or credentials committed
