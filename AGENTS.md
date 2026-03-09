# Writing Warrant Manifests — Agent Guide

You're a coding agent tasked with creating a Warrant manifest for a CLI tool. This guide explains what manifests are, how they work, and how to write one from scratch.

## What is a Manifest?

A manifest is a TOML file that describes what a CLI tool can do. It maps commands, subcommands, and flags to named **capabilities** — things like "push code to a remote" or "delete a branch."

Manifests are **factual, not policy.** They describe what a tool *can* do, not what it *should* be allowed to do. Policy (allow/deny decisions) is defined separately.

Think of it like a building's floor plan versus its security access rules. The manifest is the floor plan.

## Where Manifests Live

```
registry/
├── registry.toml          # Index of all manifests
├── warrant-sh/
│   ├── git/
│   │   └── manifest.toml  # One manifest per tool
│   ├── cargo/
│   │   └── manifest.toml
│   └── ...
└── bundles/
    └── ...
```

Each manifest lives at `warrant-sh/<tool>/manifest.toml`.

## Manifest Structure

Every manifest has four sections:

```toml
[manifest]        # Metadata — who, what, which version
[transforms]      # Which scope transforms this manifest uses
[tool_policy]     # Tool-wide security policy (env stripping, deny_flags)
[[commands]]      # One entry per capability the tool offers
```

### 1. `[manifest]` — Metadata

```toml
[manifest]
schema = "warrant.manifest.v1"       # Always this value
id = "warrant-sh/mytool"             # Namespace/name
tool = "mytool"                      # Binary name as typed on the command line
tool_version = ">=1.0"               # Semver constraint, or "*" for any
manifest_version = "1.0.0"           # Version of this manifest
summary = "Short description"
license = "CC0-1.0"
source = "https://github.com/..."    # Link to the tool's source/docs
```

#### Writing Good Summaries

The `summary` field helps agents and users understand what a manifest covers at a glance. Include the tool's domain and key capabilities, not just the tool name.

```toml
# ✅ Good — describes domain and scope
summary = "Git version control — clone, push, pull, branching, history, remotes. Force-push and remote-add split as high-risk."
summary = "GitHub CLI — PRs, issues, releases, Actions, API. Repo create/delete and auth changes denied."
summary = "Python package installer — install, uninstall, freeze. Denylist-checked against known malicious packages."

# ❌ Bad — just restates the tool name
summary = "Git capability map"
summary = "npm manifest"
summary = "Docker"
```

### 2. `[transforms]` — Scope Transforms

Declare which transform functions you use in scope definitions:

```toml
[transforms]
supported = ["literal", "path", "hostname"]
```

Available transforms:

| Transform | What it does | Example |
|-----------|-------------|---------|
| `literal` | Pass through unchanged | `"origin"` → `"origin"` |
| `path` | Canonicalise to absolute path | `"./src"` → `"/home/user/project/src"` |
| `hostname` | Extract hostname from URL | `"https://api.example.com/v1"` → `"api.example.com"` |
| `email_domain` | Extract domain from email | `"user@example.com"` → `"example.com"` |
| `glob` | Pattern for matching | `"src/**/*.rs"` |
| `git_remote` | Normalise git remote URL | `"git@github.com:org/repo.git"` → `"github.com:org/repo"` |

If your manifest doesn't use scopes, just use `supported = ["literal"]`.

### 3. `[tool_policy]` — Tool-Wide Policy

Optional. Use for:

- **`strip_env`** — Environment variables to remove before execution (prevents config hijacking)
- **`deny_flags`** — Flags that should always be blocked (e.g. `--yolo`, `--no-verify`)
- **`deny_flags_description`** — Human-readable reason shown in denial messages
- **`paths`** — Restrict which binary paths are allowed
- **`allow_inline_execution`** — Whether the tool can execute inline code via `-c`/`-e` flags. Defaults to `false`. Only set `true` for interpreters that genuinely need it (python, node, ruby). When `false`, commands like `python3 -c "os.system('rm -rf /')"` are denied even if python3 is on the allowlist.
- **`package_policy`** — Package security: `"open"`, `"denylist"`, or `"allowlist"`
- **`package_ecosystem`** — Which ecosystem's denylist to check: `"npm"`, `"pypi"`, or `"cargo"`. If omitted, inferred from the tool name (works for well-known tools like pip, npm, cargo, uv, pnpm, yarn, poetry, bun). **Required** for custom/unknown tool names.

```toml
[tool_policy]
strip_env = ["MYTOOL_CONFIG_OVERRIDE", "MYTOOL_UNSAFE_*"]
deny_flags = ["--unsafe-mode"]
deny_flags_description = "Block --unsafe-mode which disables all safety checks"
allow_inline_execution = false
```

#### Package Policy for Package Managers

If your tool installs packages (like pip, npm, cargo, or any custom tool), you need to connect it to the denylist system. Two things are required:

1. **Declare the ecosystem and scope key** in `[tool_policy]`:

```toml
[tool_policy]
package_policy = "denylist"
package_ecosystem = "pypi"    # Which denylist to check against
package_scope = "deps"        # Which scope key holds the package names (default: "packages")
```

2. **Extract the package name** using a scope with a matching key in the install command:

```toml
[[commands]]
match = ["fire"]                  # Whatever the install subcommand is
capability = "bloop.fire"
description = "Install a package"
risk = "moderate"
default = "allow"
scope = { key = "deps", from = "arg_rest", transform = "literal" }
scope_descriptions = { deps = "Package names to install" }
```

The scope key must match what you set in `package_scope`. If you omit `package_scope`, it defaults to `"packages"`.

**How it works end-to-end:**
```
bloop fire evil-package
  → match = ["fire"] matches
  → scope extracts "evil-package" into "deps" (the package_scope key)
  → package_ecosystem = "pypi" tells wsh to check the PyPI denylist
  → "evil-package" found in Datadog's malicious packages dataset
  → DENIED
```

Known tool names that auto-resolve (no `package_ecosystem` needed):
- **npm ecosystem:** npm, pnpm, yarn, bun
- **pypi ecosystem:** pip, pip3, uv, poetry, pdm, pipx
- **cargo ecosystem:** cargo

### 4. `[[commands]]` — Capabilities

This is the core of the manifest. Each `[[commands]]` entry maps a command pattern to a capability.

#### Basic example

```toml
[[commands]]
match = ["push"]              # Matches: mytool push ...
capability = "mytool.push"    # Capability name (dotted)
description = "Push changes to remote"
risk = "moderate"             # low | moderate | high | critical
default = "allow"             # Suggested default: allow | deny
```

#### The `match` field

`match` is an array of subcommand tokens to match against:

- `["push"]` matches `mytool push ...`
- `["remote", "add"]` matches `mytool remote add ...`
- `[]` (empty) matches the bare command `mytool` with no subcommand

#### Flag-based splitting

You can create different capabilities for the same command depending on flags:

```toml
# Normal push
[[commands]]
match = ["push"]
when_no_flags = ["--force", "-f"]
capability = "mytool.push"
risk = "moderate"
default = "allow"

# Force push — different, higher-risk capability
[[commands]]
match = ["push"]
when_any_flags = ["--force", "-f"]
capability = "mytool.push_force"
risk = "high"
default = "deny"
```

Flag conditions:
- `when_any_flags` — match if ANY of these flags are present
- `when_all_flags` — match if ALL of these flags are present
- `when_no_flags` — match only if NONE of these flags are present

#### Scopes — what the command targets

Scopes extract semantic values from commands so policy can reason about *what* is being acted on, not just *which* command:

```toml
[[commands]]
match = ["push"]
capability = "mytool.push"
risk = "moderate"
default = "allow"
args = { remote = 1, branch = 2 }    # Positional: 1st arg = remote, 2nd = branch
scope_examples = { remote = ["origin"], branch = ["main", "release/*"] }
scope_descriptions = { remote = "Target remote", branch = "Target branch" }
```

For flags that take values, use `options`:

```toml
options = { branch = { names = ["-b", "--branch"], forms = ["separate", "equals"] } }
```

Forms: `"separate"` = `-b main`, `"equals"` = `--branch=main`, `"attached"` = `-bmain`

**Always include `scope_descriptions` and `scope_examples`** when adding scopes. They make `wsh explain` output useful and help agents understand what they're being asked to scope. Omitting them is a common oversight.

#### The Catch-All — CRITICAL

**Every manifest that uses subcommand matching MUST have a catch-all entry as the last `[[commands]]` entry.** Without it, any subcommand not explicitly listed will be denied with "no manifest command mapping matched" — even safe, read-only commands.

The catch-all matches anything not caught by a more specific entry above it:

```toml
# This MUST be the last [[commands]] entry in the file
[[commands]]
match = []
capability = "mytool.other"
description = "Any other mytool subcommand not explicitly listed"
risk = "low"
default = "allow"
```

**Why this matters:** If a manifest exists for a tool but doesn't match the specific subcommand, wsh denies the command. Having a partial manifest is *worse* than having no manifest at all. The catch-all prevents this.

**The pattern is:**
1. Explicitly list high-risk commands with `deny` or scoped controls
2. Explicitly list commonly-used commands for documentation and granularity
3. Catch everything else with a `match = []` entry at the bottom

```toml
# ❌ Bad — missing catch-all. "mytool stats" will be denied even though it's harmless.
[[commands]]
match = ["push"]
capability = "mytool.push"
risk = "moderate"
default = "allow"

[[commands]]
match = ["delete"]
capability = "mytool.delete"
risk = "high"
default = "deny"

# ✅ Good — catch-all at the bottom. "mytool stats" falls through and is allowed.
[[commands]]
match = ["push"]
capability = "mytool.push"
risk = "moderate"
default = "allow"

[[commands]]
match = ["delete"]
capability = "mytool.delete"
risk = "high"
default = "deny"

[[commands]]
match = []
capability = "mytool.other"
description = "Any other mytool subcommand not explicitly listed"
risk = "low"
default = "allow"
```

## Step-by-Step: Writing a Manifest

### 1. Understand the CLI

Run `mytool --help` and `mytool <subcommand> --help`. List every subcommand and its purpose. Note which flags are dangerous or security-relevant.

### 2. Create the file

```bash
mkdir -p warrant-sh/mytool
touch warrant-sh/mytool/manifest.toml
```

### 3. Write the metadata

```toml
[manifest]
schema = "warrant.manifest.v1"
id = "warrant-sh/mytool"
tool = "mytool"
tool_version = "*"
manifest_version = "1.0.0"
summary = "MyTool — brief description of domain and key capabilities"
license = "CC0-1.0"
source = "https://github.com/example/mytool"

[transforms]
supported = ["literal"]
```

### 4. Map each subcommand to a capability

For each subcommand, ask:

1. **What does it do?** → description
2. **How risky is it?** → risk level
3. **Should it be allowed by default?** → default

Risk guidelines:
- **low** — Read-only, informational, local-only (e.g. `status`, `list`, `help`)
- **moderate** — Writes local state, reversible (e.g. `commit`, `push`, `build`)
- **high** — Destructive, affects remote state, hard to reverse (e.g. `force-push`, `delete`, `reset --hard`)
- **critical** — System-level, irreversible, security-sensitive (e.g. `rm -rf /`, key deletion)

### 5. Identify flag-based splits

If a flag significantly changes the risk profile, create separate capabilities:

- `push` vs `push --force`
- `delete --dry-run` vs `delete`
- `deploy --production` vs `deploy --staging`

### 6. Add scopes where useful

If policy might need to restrict *what* a command targets (which remote, which file, which host), add scope extraction. Always include `scope_descriptions` and `scope_examples`.

Don't over-scope — only add scopes where policy will realistically need to filter by target. Not every argument needs a scope.

### 7. Add the catch-all

**Do not skip this step.** Add a `match = []` entry as the last `[[commands]]` in the file. See the [catch-all section](#the-catch-all--critical) above.

### 8. Add tool_policy if needed

If the tool has:
- Environment variables that can hijack behaviour → `strip_env`
- Flags that should always be blocked → `deny_flags`
- Inline code execution via `-c`/`-e` → set `allow_inline_execution` appropriately
- Package installation → configure `package_policy` and `package_ecosystem`

### 9. Validate the manifest

Before committing, check for common errors:

```bash
# Verify TOML is valid
python3 -c "import tomllib; tomllib.load(open('warrant-sh/mytool/manifest.toml', 'rb')); print('✓ valid TOML')"

# Check required fields
python3 -c "
import tomllib
m = tomllib.load(open('warrant-sh/mytool/manifest.toml', 'rb'))
assert m['manifest']['schema'] == 'warrant.manifest.v1', 'bad schema'
assert m['manifest']['id'], 'missing id'
assert m['manifest']['tool'], 'missing tool'
cmds = [c for c in m.get('commands', []) if isinstance(c, dict)]
# Verify catch-all exists (last command has empty match)
assert any(c.get('match') == [] for c in cmds), 'MISSING CATCH-ALL — add a match=[] entry at the end'
print('✓ manifest looks good')
"
```

### 10. Update the registry index

Add your manifest to `registry.toml`:

```toml
[[manifests]]
id = "warrant-sh/mytool"
path = "warrant-sh/mytool/manifest.toml"
version = "1.0.0"
hash = "sha256:..."
```

Generate the hash:

```bash
sha256sum warrant-sh/mytool/manifest.toml | awk '{print "sha256:" $1}'
```

Then re-sign:

```bash
./sign-registry-dev.sh
```

### 11. Test it

Run through this checklist:

- [ ] **Every subcommand covered** — run `mytool --help` and verify each subcommand either has an explicit entry or falls through to the catch-all
- [ ] **Flag-based splits work** — test that dangerous flags (e.g. `--force`) trigger the high-risk capability, not the normal one
- [ ] **Deny_flags actually block** — if you set `deny_flags`, verify they cause a denial
- [ ] **Scope extraction works** — run `wsh explain` on a scoped command and verify the scope values are extracted correctly
- [ ] **Catch-all handles unlisted commands** — try a subcommand you didn't explicitly list and verify it's allowed (not denied with "no manifest command mapping matched")
- [ ] **Risk levels make sense** — read-only commands are `low`, destructive commands are `high` or `critical`

```bash
# Pull and install
wsh pull mytool
wsh add mytool

# Edit the draft
wsh edit mytool

# Lock
sudo wsh lock

# Test commands
wsh check mytool status        # Should pass (low risk, allow)
wsh check mytool delete        # Should fail (high risk, deny)
wsh check mytool push --force  # Should fail (if force-push is deny)
wsh check mytool some-random   # Should pass (catch-all)
```

## Patterns to Follow

### Standard CLI tool (like git, cargo, docker)

Map each subcommand. Split on dangerous flags. Add scopes for remote/target arguments. Include a catch-all.

See `warrant-sh/git/manifest.toml` for a comprehensive example.

### Programs allowlist (like coreutils)

Use `match = []` with `capability = "policy.commands_allow"` and `scope_defaults` containing a list of allowed program names. See `warrant-sh/coreutils` for the pattern.

### Dangerous patterns blocklist

Use `match = []` with `capability = "policy.commands_block"` and `scope_defaults` containing glob patterns to block. See `warrant-sh/dangerous-patterns`.

### Environment sanitization

Use `match = []` with `capability = "policy.environment_strip"` and `scope_defaults` containing env var patterns to strip. See `warrant-sh/sanitize-env`.

### Agent wrapper (like codex, claude)

Map the agent's subcommands. Use `deny_flags` to block unsafe modes (e.g. `--yolo`). See `warrant-sh/codex`.

### Policy inspection tool (like wsh)

Allow read-only informational commands (`check`, `explain`, `status`). Deny admin commands (`lock`, `setup`, `pull`). Deny the catch-all too — unknown wsh subcommands shouldn't be allowed by default. See `warrant-sh/wsh`.

## Common Mistakes

### 1. Missing catch-all

The most common and most damaging mistake. Without it, any unlisted subcommand is silently denied. Always add `match = []` as the last entry.

```toml
# ❌ "mytool info" will be denied — no entry matches it
[[commands]]
match = ["push"]
capability = "mytool.push"
default = "allow"

# ✅ "mytool info" falls through to the catch-all
[[commands]]
match = ["push"]
capability = "mytool.push"
default = "allow"

[[commands]]
match = []
capability = "mytool.other"
default = "allow"
```

### 2. Inventing capabilities that don't exist

Only map real subcommands and flags. The manifest is factual.

### 3. Setting everything to deny

Defaults should reflect reasonable security posture. Read-only commands are `allow`. Only destructive, irreversible, or security-sensitive commands are `deny`.

### 4. Forgetting strip_env

Many tools honour environment variables that override config. Check the tool's docs for `*_CONFIG`, `*_OPTS`, `*_PATH` variables. If they can redirect execution or change configuration, strip them.

### 5. Skipping flag-based splits

`git push` and `git push --force` are fundamentally different risk levels. Treat them as different capabilities.

### 6. Over-scoping

Only add scopes where policy will realistically need to filter by target. Not every argument needs a scope.

### 7. Missing scope_descriptions

When you add scopes, always include `scope_descriptions` and `scope_examples`. Without them, `wsh explain` output is opaque and agents can't understand what they're being asked to allow.

```toml
# ❌ Scope with no context
args = { remote = 1, branch = 2 }

# ✅ Scope with descriptions and examples
args = { remote = 1, branch = 2 }
scope_descriptions = { remote = "Which remote to push to", branch = "Which branches can be pushed" }
scope_examples = { remote = ["origin", "upstream"], branch = ["main", "release/*"] }
```

### 8. Catch-all not last

The catch-all must be the final `[[commands]]` entry. Entries are matched in order — if the catch-all comes first, specific entries below it will never match.

## Reference

- **Full specification:** `spec/manifest-v1.md` in this repo
- **Example manifests:** `warrant-sh/git/`, `warrant-sh/cargo/`, `warrant-sh/gh/`, `warrant-sh/wsh/`
- **Policy engine:** [warrant-core](https://github.com/warrant-sh/warrant-core)
- **CLI:** [warrant-shell](https://github.com/warrant-sh/warrant-shell)
