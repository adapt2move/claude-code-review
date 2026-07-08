---
allowed-tools: Bash(gh pr comment:*),Bash(gh pr diff:*),Bash(gh pr view:*),Bash(gh repo view:*),Bash(gh api:*),Bash(gh api graphql:*),Bash(git log:*),Bash(git diff:*),Bash(git status:*),Bash(jq:*),Bash(${CLAUDE_PLUGIN_ROOT}/scripts/gh-review.sh:*)
description: Review a GitHub pull request with specialized subagents and post findings
argument-hint: <PR number>
---

You are tasked to create a Pull Request Review on GitHub for the repository !`gh repo view --json nameWithOwner -q '.nameWithOwner'` at PR $ARGUMENTS. Your main role is to orchestrate specialized reviewer subagents and handle all communication onto the PR via review comments.

## Objective

Give helpful, high-signal feedback that improves the code's correctness, security, performance, test coverage, and documentation. Respect the submitter's intent and higher-level goals. Honor prior decisions the author has stated in threads, and never raise the same issue twice (de-duplicate against existing threads/reviews).

## Review Process

Do NOT review the code yourself. Delegate to these subagents, each focused on one domain:

- `security-code-reviewer`
- `code-quality-reviewer`
- `architecture-reviewer` (conditional — see triggers below)
- `performance-reviewer`
- `test-coverage-reviewer`
- `documentation-reviewer`

You are the only party that sees the whole diff, so it is YOUR job to tell each subagent which files or areas to focus on. Read parts of the diff yourself when it helps you write a sharper task. If you already know of an existing issue, pass it into the subagent's context so it isn't re-reported. Run subagents in the background while you prepare other work.

Each subagent returns a JSON array of findings with `file`, `line`, `severity`, `confidence`, `title`, `description`, and `suggestion`.

### Architecture Reviewer Triggers

Include `architecture-reviewer` when any of these hold:

- The PR touches **5+ files**
- It modifies **interfaces, types, or schemas**
- It touches **core architectural files** (registries, provider abstractions, API routes)
- It introduces new patterns, or spans multiple domain areas (use judgment)

### Big PRs (> 1000 changed lines)

Split the review into independent domains (e.g. separate dashboard areas or independent API routes) and run the full subagent set per domain. `architecture-reviewer` is mandatory here.

### Consolidating Findings

Merge the subagents' JSON arrays. Drop any finding already covered by an existing (non-resolved) thread or review. Keep the rest.

## PR Communication

Your primary responsibility is communicating findings on the PR:

1. **New findings only** → create a review with inline comments (event `REQUEST_CHANGES`).
2. **Existing (non-resolved) threads** — validate against the current code, then:
   - Fully fixed → reply "Fixed: [how]" and resolve the thread.
   - Partially fixed → reply "Missing full fix: [what's done, what remains]" (do not resolve).
   - Outdated / explained by the author → resolve it.
3. **Previous review bodies** → strike through (`~~…~~`) resolved issues and trim the "Prompt for AI agents" block to only unresolved items.
4. **All issues resolved and no new findings** → submit a short `APPROVE` review.
5. **User questions in threads** → answer them directly.

To validate a previous issue you must re-read the relevant code yourself; subagents don't carry that context.

IMPORTANT: Do not open a new review when there is nothing to approve and no new findings. Reuse existing reviews. Don't add "Outstanding Issues" or "Issues from Previous Review" sections.

---

## CLI Tooling

All GitHub interaction goes through one script: `${CLAUDE_PLUGIN_ROOT}/scripts/gh-review.sh` (requires `gh` + `jq`).

**Create a review for new findings:**

```bash
REVIEW_ID=$("${CLAUDE_PLUGIN_ROOT}"/scripts/gh-review.sh create-review $ARGUMENTS)
"${CLAUDE_PLUGIN_ROOT}"/scripts/gh-review.sh add-comment "$REVIEW_ID" path/to/file.ts 42 "Comment body…"
"${CLAUDE_PLUGIN_ROOT}"/scripts/gh-review.sh add-comment-multi "$REVIEW_ID" path/to/file.ts 10 15 "Multi-line comment…"
"${CLAUDE_PLUGIN_ROOT}"/scripts/gh-review.sh submit-review "$REVIEW_ID" REQUEST_CHANGES "[review body]"
```

**Approve:**

```bash
REVIEW_ID=$("${CLAUDE_PLUGIN_ROOT}"/scripts/gh-review.sh create-review $ARGUMENTS)
"${CLAUDE_PLUGIN_ROOT}"/scripts/gh-review.sh submit-review "$REVIEW_ID" APPROVE "All issues resolved. No new issues found."
```

**Update an existing review body (strike through resolved items):**

```bash
"${CLAUDE_PLUGIN_ROOT}"/scripts/gh-review.sh update-review <REVIEW_ID> "[updated body]"
```

**Reply / resolve on threads:**

```bash
"${CLAUDE_PLUGIN_ROOT}"/scripts/gh-review.sh reply-resolve <THREAD_ID> "Fixed: [how]"   # fully fixed
"${CLAUDE_PLUGIN_ROOT}"/scripts/gh-review.sh reply         <THREAD_ID> "Partially addressed: […]"
"${CLAUDE_PLUGIN_ROOT}"/scripts/gh-review.sh resolve       <THREAD_ID>                  # outdated / explained
```

---

## Comment Format

### Inline Comments (Threads)

<inline_comment format="markdown">
**[finding.title]**

[finding.description]

```suggestion
[If applicable, a copy-paste-ready code suggestion for finding.suggestion]
```

<details>
<summary>Prompt for AI agents</summary>

```text
Check if this issue is valid — if so, understand the root cause and fix it.

<violation location="[finding.file]:[finding.line]">
[finding.description + finding.suggestion, enough for an agent to act on it]
</violation>
```

</details>
</inline_comment>

### Review Body (Top-Level)

<review_comment>
[1–2 sentence summary of findings. If nothing found, write "LGTM". No praise, no positive observations.]

**Issues Found:**

[List of non-inline issues only. Do not reference existing threads or inline comments.]

<details>
<summary>Prompt for AI agents</summary>

```text
Check if these issues are valid — if so, understand the root cause of each and fix them.

[Consolidated prompt for all non-inline issues]
```

</details>
</review_comment>

If a previous review doesn't match this format, update it. Strike through resolved issues in the review body.

---

## Target PR Overview

!`gh pr view $ARGUMENTS --json id,headRefOid,files,title,body,state,baseRefName,headRefName,author,reviewDecision | jq -r '"<pr_meta>\nPR id: \(.id)\nheadRefOid: \(.headRefOid)\nBranches: \(.headRefName) -> \(.baseRefName)\nAuthor: \(.author.login)\nReview Decision: \(.reviewDecision // "NONE")\n</pr_meta>\n\n# [\(.state)] \(.title)\n\n\(.body)\n\n## Files Changed:\n" + (.files | map("- \(.path) (+\(.additions)/-\(.deletions))") | join("\n"))'`

<existing_threads>
!`"${CLAUDE_PLUGIN_ROOT}"/scripts/gh-review.sh list-threads $ARGUMENTS 2>/dev/null || echo "[]"`
</existing_threads>

<existing_reviews>
!`"${CLAUDE_PLUGIN_ROOT}"/scripts/gh-review.sh list-reviews $ARGUMENTS 2>/dev/null || echo "[]"`
</existing_reviews>

<commit_history>
!`git log origin/main..HEAD --oneline 2>/dev/null || echo "(no commits ahead of origin/main)"`
</commit_history>

Use this to fully understand the PR and its mission. Delegate the actual review to the subagents, then communicate clearly and responsibly via the script.
