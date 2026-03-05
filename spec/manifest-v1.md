# Warrant Manifest Specification v1

**Schema identifier:** `warrant.manifest.v1`
**Status:** Public Beta — the core schema is stable, but fields and conventions may evolve based on feedback. [Open an issue](https://github.com/warrant-sh/registry/issues) or [join the discussion](https://github.com/warrant-sh/warrant-shell/discussions).
**Version:** 1.0.0-beta
**Last updated:** 2026-02-21

## Overview

A Warrant manifest is a declarative TOML document that describes the capabilities of a command-line tool. It maps a tool's subcommands and flags to named capabilities with typed scopes, enabling policy engines to make fine-grained access control decisions without cooperation from the tool author.

Manifests are **factual descriptions, not policy.** They declare what a tool *can* do, not what it *should* be allowed to do. Policy is defined separately in warrant drafts and compiled into signed warrants.

**Design principle:** Anyone can write a manifest for any tool. No helper libraries, no upstream changes, no cooperation required. A manifest is a static TOML file that can be reviewed, versioned, and shared.

## Design Rationale: The CLI Control Surface

The manifest schema is derived from a systematic analysis of how command-line tools are controlled. Every mechanism through which a user (or agent) influences a CLI tool's behaviour is a potential vector that a policy engine must understand.

### The CLI Control Taxonomy

CLI tools are controlled through five categories of interface:

| Category | Mechanisms | Manifest coverage |
|----------|-----------|-------------------|
| **Invocation syntax** | Command name, subcommands, positional arguments, options/flags (with and without values), option bundling, option terminator (`--`) | `[[commands]]` — `match`, `when_*_flags`, `args`, `options`, `flags`, `respect_option_terminator` |
| **External configuration** | Environment variables, config files, dotfiles | `[tool_policy].strip_env`, `[[commands]].env` |
| **Data streams** | stdin, stdout, stderr, pipes, redirection | Out of scope (shell-layer; handled by the policy engine's redirect checking) |
| **Interactive/runtime** | TTY prompts, REPL, signals | Out of scope (runtime behaviour; not declarable in a static manifest) |
| **Process integration** | Exit codes, IPC, daemon sockets | Out of scope (process-level; addressed by sandbox tools like warrant-box) |

### What the Manifest Captures

The manifest focuses on **invocation syntax** and **external configuration** — the two categories where a static document can fully describe the tool's interface:

1. **Command and subcommands** → `match` tokens identify which subcommand is being invoked (e.g. `["remote", "add"]` matches `git remote add`)
2. **Positional arguments** → `args` extracts named values by position (e.g. `remote = 1` captures the first argument as the remote name)
3. **Options and flags** → `when_any_flags`, `when_all_flags`, `when_no_flags` enable capability splitting based on flag presence. `options` declares flags that take values with their syntactic forms (separate, equals, attached).
4. **Option terminator** → `respect_option_terminator` controls whether flags after `--` are considered during matching
5. **Environment variables** → `strip_env` removes dangerous variables before execution; `env` captures environment values as scopes

### What the Manifest Deliberately Excludes

- **Stdin/pipes/redirection:** These are shell-layer constructs. The policy engine parses the full shell command and checks redirections separately — this doesn't belong in a per-tool manifest.
- **Interactive/TTY behaviour:** A tool's interactive prompts are runtime behaviour that can't be described in a static document. If a tool enters a REPL, control passes beyond what a manifest can declare.
- **IPC/daemon communication:** Tools that front-end daemons (docker, systemctl) are controlled at the CLI layer like any other tool — the manifest describes the CLI interface, not the daemon protocol.
- **Config files:** While tools read configuration from dotfiles, manifests don't attempt to describe config file schemas. Instead, `strip_env` blocks the environment variables that override config file locations (e.g. `GIT_CONFIG_GLOBAL`).

### Scope Extraction: From Syntax to Semantics

Raw CLI tokens are syntactic. Policy decisions are semantic. The manifest bridges this gap through **scope extraction** — transforms that convert positional arguments, flag values, and environment variables into typed scope values that policy engines can reason about:

```
git push origin main
      ↓           ↓
  args.remote=1   args.branch=2
      ↓           ↓
  scope: remote   scope: branch
      ↓           ↓
  transform:      transform:
  literal         literal
      ↓           ↓
  "origin"        "main"
```

The policy engine then checks: *"Is this agent allowed to push to remote `origin`, branch `main`?"* — a semantic question derived from syntactic tokens via the manifest's scope declarations.

This is the core contribution of the manifest format: it turns opaque CLI invocations into structured, auditable capability checks.

## Document Structure

A manifest TOML document contains four top-level sections:

```toml
[manifest]        # Required — metadata
[transforms]      # Optional — scope transform functions
[tool_policy]     # Optional — tool-level security policy
[[commands]]      # Required — one or more command capability declarations
```

---

## `[manifest]` — Metadata

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `schema` | string | ✅ | Must be `"warrant.manifest.v1"` |
| `id` | string | ✅ | Namespaced identifier (e.g. `"warrant-sh/git"`) |
| `tool` | string | ✅ | Binary name as invoked on the command line (e.g. `"git"`) |
| `tool_version` | string | ✅ | Semver constraint for applicable tool versions (e.g. `">=2.30"`, `"*"` for any) |
| `manifest_version` | string | ✅ | Semver version of this manifest document |
| `summary` | string | | Short description of the manifest |
| `license` | string | | SPDX license identifier for the manifest itself |
| `source` | string | | URL to the upstream tool's source or documentation |

### Namespace Conventions

The `id` field uses a namespace/name format:

- `warrant-sh/*` — maintained by the Warrant project
- `{org}/*` — maintained by a third-party organisation
- `{user}/*` — maintained by an individual contributor

```toml
[manifest]
schema = "warrant.manifest.v1"
id = "warrant-sh/git"
tool = "git"
tool_version = ">=2.30"
manifest_version = "1.0.0"
summary = "Git capability map"
license = "CC0-1.0"
source = "https://github.com/git/git"
```

---

## `[transforms]` — Scope Transforms

Declares which transform functions are used by scope definitions in this manifest.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `supported` | array of strings | ✅ | List of transform function names used in `[[commands]]` scope definitions |

### Built-in Transforms

| Transform | Input | Output | Example |
|-----------|-------|--------|---------|
| `literal` | raw argument | unchanged string | `"origin"` → `"origin"` |
| `path` | file path | canonicalised absolute path | `"./src"` → `"/home/user/project/src"` |
| `hostname` | URL or host string | extracted hostname | `"https://api.example.com/v1"` → `"api.example.com"` |
| `email_domain` | email address | domain part | `"user@example.com"` → `"example.com"` |
| `glob` | glob pattern | pattern string for matching | `"src/**/*.rs"` |
| `git_remote` | git remote URL | normalised remote identifier | `"git@github.com:org/repo.git"` → `"github.com:org/repo"` |

```toml
[transforms]
supported = ["literal", "path", "hostname", "git_remote"]
```

---

## `[tool_policy]` — Tool-Level Security Policy

Declares security-relevant policy that applies to all invocations of the tool, regardless of subcommand.

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `strip_env` | array of strings | | `[]` | Environment variables to remove before execution. Supports `*` glob suffix. |
| `paths` | array of strings | | `[]` | Allowed resolved binary paths (glob patterns). Empty means unrestricted. |
| `deny_flags` | array of strings | | `[]` | Flags that should always be denied regardless of capability decisions (e.g. `["--yolo", "--no-verify"]`). |
| `deny_flags_description` | string | | | Human-readable explanation of why these flags are denied. Shown in denial messages. |
| `allow_inline_execution` | bool | | `false` | Whether the tool is allowed to execute inline code via `-c`, `-e`, or similar flags. When `false` (default), commands like `python3 -c "import os; os.system('rm -rf /')"` are denied even if `python3` itself is allowed. Set to `true` only for interpreters that genuinely need inline execution. |
| `package_policy` | string | | `"open"` | Package security mode: `"open"`, `"denylist"`, or `"allowlist"` |
| `package_ecosystem` | string | | *(inferred)* | Package ecosystem for denylist checks: `"npm"`, `"pypi"`, or `"cargo"`. If omitted, inferred from the `tool` name. Required for tools with non-standard names. |
| `package_scope` | string | | `"packages"` | Which scope key in `[[commands]]` contains package names to check against the denylist. |

```toml
[tool_policy]
strip_env = [
  "GIT_SSH",
  "GIT_SSH_COMMAND",
  "GIT_CONFIG_GLOBAL",
  "GIT_CONFIG_KEY_*",
  "GIT_CONFIG_VALUE_*",
]
paths = []
deny_flags = ["--no-verify"]
deny_flags_description = "Block --no-verify which skips pre-commit hooks"
allow_inline_execution = false
package_policy = "denylist"
```

### Package Policy Modes

| Mode | Behaviour |
|------|-----------|
| `open` | No package-level checks |
| `denylist` | Block known-malicious packages (checked against a maintained denylist) |
| `allowlist` | Only permit explicitly approved packages |

---

## `[[commands]]` — Command Capability Declarations

Each `[[commands]]` entry maps a subcommand pattern to a named capability. A manifest may declare multiple entries — one per distinct capability the tool offers.

### Matching Fields

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `match` | array of strings | ✅ | | Subcommand token sequence to match (e.g. `["push"]`, `["remote", "add"]`) |
| `when_any_flags` | array of strings | | `[]` | Match only when at least one of these flags is present |
| `when_all_flags` | array of strings | | `[]` | Match only when all of these flags are present |
| `when_no_flags` | array of strings | | `[]` | Match only when none of these flags are present |
| `respect_option_terminator` | bool | | `false` | If true, flags after `--` are not considered for `when_*` matching |

**Flag-based specialisation:** Multiple `[[commands]]` entries can share the same `match` value but differ on flag conditions. This enables capability splitting — e.g. `git push` vs `git push --force`:

```toml
# Regular push
[[commands]]
match = ["push"]
when_no_flags = ["--force", "-f", "--force-with-lease"]
capability = "git.push"
risk = "moderate"
default = "allow"

# Force push — separate, higher-risk capability
[[commands]]
match = ["push"]
when_any_flags = ["--force", "-f", "--force-with-lease"]
capability = "git.push_force"
risk = "high"
default = "deny"
```

### Capability Fields

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `capability` | string | ✅ | | Dotted capability name (e.g. `"git.push"`, `"network.request"`) |
| `label` | string | | | Human-readable short name |
| `description` | string | | | Human-readable description of what this capability allows |
| `risk` | string | | | Risk level: `"low"`, `"moderate"`, `"high"`, `"critical"` |
| `default` | string | | | Suggested default decision: `"allow"` or `"deny"` |

### Scope Extraction

Scopes allow policy engines to make decisions not just on *what* command runs, but on *what it targets* — which remote, which file, which host.

| Field | Type | Description |
|-------|------|-------------|
| `scope` | object | Single scope extraction rule (shorthand for a one-element `scopes` array) |
| `scopes` | array of objects | Multiple scope extraction rules |
| `args` | map of string → integer | Named positional arguments (name → 1-based position index) |
| `flags` | map of string → string | Named flag values (name → flag string) |
| `options` | map of string → OptionSpec | Option specifications for flags that take values |
| `env` | map of string → string | Named environment variable captures |
| `scope_examples` | map of string → array of strings | Example values for each scope key (for documentation and draft generation) |
| `scope_defaults` | map of string → array of strings | Default allowed values for each scope key |
| `scope_descriptions` | map of string → string | Human-readable description of each scope key |

#### Scope Object

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `key` | string | ✅ | Scope variable name (e.g. `"remote"`, `"host"`, `"path"`) |
| `from` | string | ✅ | Source: `"arg"`, `"flag"`, `"env"`, `"option"` |
| `index` | integer | | For `from = "arg"`: 1-based positional argument index |
| `transform` | string | ✅ | Transform function to apply (must be listed in `[transforms].supported`) |
| `examples` | array of strings | | Example values |

```toml
[[commands]]
match = ["push"]
capability = "git.push"
risk = "moderate"
default = "allow"
when_no_flags = ["--force", "-f", "--force-with-lease"]
args = { remote = 1, branch = 2 }
scope_examples = { remote = ["origin", "upstream"], branch = ["main", "release/*"] }
scope_descriptions = { remote = "Which remote to push to", branch = "Which branches can be pushed" }
```

#### OptionSpec Object

For flags that take values (e.g. `-b main`, `--branch=main`):

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `names` | array of strings | ✅ | | Flag names including prefix (e.g. `["-b", "--branch"]`) |
| `forms` | array of strings | ✅ | | Accepted syntactic forms: `"separate"` (`-b main`), `"equals"` (`--branch=main`), `"attached"` (`-bmain`) |
| `allow_hyphen_values` | bool | | `false` | Whether the value may start with a hyphen |

```toml
options = { branch = { names = ["-b", "--branch"], forms = ["separate", "equals", "attached"] } }
```

---

## Registry Protocol

Manifests are distributed via a registry — a Git repository (or HTTP endpoint) containing manifest files and a discovery index.

### Registry Index (`registry.toml`)

```toml
[registry]
schema = "warrant.registry.v1"
updated = "2026-02-21T08:00:00Z"

[[manifests]]
id = "warrant-sh/git"
path = "warrant-sh/git/manifest.toml"
version = "1.0.0"
hash = "sha256:bc03ed42..."
```

| Field | Type | Description |
|-------|------|-------------|
| `schema` | string | Must be `"warrant.registry.v1"` |
| `updated` | string | ISO 8601 timestamp of last index update |
| `manifests[].id` | string | Namespaced manifest identifier |
| `manifests[].path` | string | Relative path to manifest file within the registry |
| `manifests[].version` | string | Manifest version |
| `manifests[].hash` | string | SHA-256 hash of the manifest file content, prefixed with `sha256:` |

### Fetch Protocol

1. Client fetches `{registry_url}/registry.toml`
2. Client compares `hash` values against locally cached manifests
3. Client downloads changed manifests from `{registry_url}/{path}`
4. Client validates each manifest against this specification
5. Client writes validated manifests to local cache

The registry URL defaults to `https://raw.githubusercontent.com/warrant-sh/registry/main` and is configurable via the `WSH_REGISTRY_URL` environment variable.

### Registry Directory Structure

```
registry/
├── registry.toml
├── warrant-sh/
│   ├── git/
│   │   └── manifest.toml
│   ├── cargo/
│   │   └── manifest.toml
│   └── ...
└── bundles/
    ├── coding-agent.toml
    └── ...
```

---

## Bundle Format

Bundles compose multiple manifests into a named setup profile.

```toml
[bundle]
name = "coding-agent"
description = "Coding agents (Codex, Claude Code, Aider, OpenCode, Cursor)"
version = "1.0.0"

[setup]
guard_all_sessions = false
shell_guard = true
prompt_lock = true

[[agents]]
name = "codex"
alias = "codex"

[[agents]]
name = "claude"
alias = "claude"

[manifests]
include = [
  "warrant-sh/coreutils",
  "warrant-sh/git",
  "warrant-sh/cargo",
  "warrant-sh/npm",
  "warrant-sh/pip",
  "warrant-sh/dangerous-patterns",
  "warrant-sh/sanitize-env",
]
```

| Section | Description |
|---------|-------------|
| `[bundle]` | Name, description, and version of the bundle |
| `[setup]` | Configuration flags for the setup recipe |
| `[[agents]]` | Agent definitions with shell alias mappings |
| `[manifests]` | List of manifest IDs to include |

---

## Validation Rules

A conforming implementation MUST:

1. Reject manifests where `schema` is not `"warrant.manifest.v1"`
2. Reject manifests with no `[[commands]]` entries
3. Reject `[[commands]]` entries where `capability` is empty
4. Reject `[[commands]]` entries where `match` is empty
5. Validate that all transforms referenced in scope definitions appear in `[transforms].supported`
6. Validate that `risk` values are one of: `"low"`, `"moderate"`, `"high"`, `"critical"` (if present)
7. Validate that `default` values are one of: `"allow"`, `"deny"` (if present)
8. Validate that `package_policy` values are one of: `"open"`, `"denylist"`, `"allowlist"` (if present)

---

## From Manifest to Policy

The manifest describes capabilities. Policy is defined separately:

```
manifest (factual)     →  draft (opinion)      →  warrant (signed policy)
"git push exists"         "allow push to origin"   cryptographically signed
```

1. `wsh pull git` — fetches the manifest from the registry
2. `wsh add git` — generates a draft from the manifest (every capability starts as `review`)
3. `wsh edit git` — operator sets each capability to `allow` or `deny`, optionally with scope constraints
4. `wsh lock` — compiles all drafts into a signed warrant (refuses if any capability is still `review`)

This separation ensures that capability *discovery* (the manifest) is decoupled from capability *authorisation* (the warrant). The same manifest can produce vastly different policies depending on the operator's requirements.

---

## Licence

This specification is released under [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/) — no rights reserved. Implement freely.

---

## Reference Implementation

- **Parser:** [`warrant-shell/src/manifest.rs`](https://github.com/warrant-sh/warrant-shell/blob/main/src/manifest.rs)
- **Registry:** [`warrant-sh/registry`](https://github.com/warrant-sh/registry)
- **Policy engine:** [`warrant-core`](https://github.com/warrant-sh/warrant-core)
