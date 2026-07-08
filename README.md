# code-review

A Claude Code plugin for multi-agent code review. It bundles three slash commands, six specialized reviewer subagents (plus a triage validator), and a single GitHub tooling script — so the same review workflow works across every repo instead of living in one project's `.claude/`.

## What's in it

**Commands**

| Command                 | What it does                                                                                                                                                  |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `/review-pr <n>`        | Reviews a GitHub PR with the reviewer subagents and posts inline + summary findings. Re-run it to re-validate and resolve threads as the author pushes fixes. |
| `/review-changes`       | Reviews your local staged/branch diff and prints a consolidated summary (no GitHub needed).                                                                   |
| `/triage-pr-review <n>` | Loads a bot review's findings, validates each with `issue-validator`, then auto-fixes the safe ones and resolves/escalates the rest.                          |

**Agents** — `security-code-reviewer`, `code-quality-reviewer`, `architecture-reviewer`, `performance-reviewer`, `test-coverage-reviewer`, `documentation-reviewer`, and `issue-validator` (used by triage). Each returns structured JSON findings and is tuned to minimize false positives.

**Script** — `scripts/gh-review.sh` wraps the GitHub GraphQL API (via `gh`) for creating reviews, managing inline threads, and gathering comment context. Run it with no args for the subcommand list.

## Requirements

- [Claude Code](https://claude.com/claude-code)
- `gh` (authenticated) and `jq` on `PATH` — for the GitHub-facing commands (`/review-changes` needs neither)

## Install

Add the marketplace, then install the plugin:

```
/plugin marketplace add adapt2move/claude-code-review
/plugin install code-review@adapt2move
```

Or point at a local checkout during development:

```
/plugin marketplace add /path/to/claude-code-review
```

## Configuration

The plugin ships with no project-specific defaults. `/triage-pr-review` reads three optional environment variables — set them in your CI job (or shell); it falls back to sensible defaults otherwise:

| Variable                | Default                         | Purpose                                             |
| ----------------------- | ------------------------------- | --------------------------------------------------- |
| `CODE_REVIEW_BOT_LOGIN` | current authenticated `gh` user | The account whose review findings triage acts on.   |
| `CODE_REVIEW_LANG`      | `English`                       | Language for PR replies, review-body edits, issues. |
| `CODE_REVIEW_LABEL`     | `review-finding`                | Label applied to out-of-scope issues triage files.  |

Example CI step:

```yaml
env:
  CODE_REVIEW_BOT_LOGIN: my-review-bot
  CODE_REVIEW_LANG: German
```

## How a PR review flows

1. `/review-pr 182` — orchestrator reads the diff, dispatches the reviewer subagents (architecture only when the change is large or cross-cutting), consolidates findings, and posts a `REQUEST_CHANGES` review with inline comments.
2. Author pushes fixes.
3. `/review-pr 182` again — re-validates each open thread, resolves fixed ones, and approves when everything is clean.
4. `/triage-pr-review 182` (optional, e.g. from CI) — validates the bot's findings, auto-applies the unambiguous fixes in one commit, files out-of-scope items as issues, and leaves genuinely complex ones for a human.

## Layout

```
.claude-plugin/plugin.json   # manifest
.claude-plugin/marketplace.json
commands/                    # review-pr, review-changes, triage-pr-review
agents/                      # 6 reviewers + issue-validator
scripts/gh-review.sh         # GitHub review tooling (gh + jq)
```

Commands reference the script via `${CLAUDE_PLUGIN_ROOT}`, so the plugin is location-independent.
