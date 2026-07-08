---
allowed-tools: Bash(git diff:*),Bash(git status:*),Bash(git log:*)
description: Review the current changes (staged or on the branch) with specialized subagents
argument-hint: [branch or staged]
---

## Review Process

Perform a comprehensive review of the current changes using the specialized subagents:

- `architecture-reviewer` (on bigger changes)
- `code-quality-reviewer`
- `performance-reviewer`
- `test-coverage-reviewer`
- `documentation-reviewer`
- `security-code-reviewer`

Instruct each to report only noteworthy, high-confidence findings. Consider code that is cross-impacted by the changes, not just the changed lines. Once the subagents finish, consolidate their output into a single concise summary that references files clearly.

```feedback-format
# [Short feedback title]

[Short summary of the most noteworthy feedback]

## Direct Issues

[Each issue directly caused by the changes. If none: "Approval, no issue found."]

### 1. [Short title]

[Concise but specific description of the misbehaving/impacted code, with clear file references. No priority or difficulty labels — the author should be able to understand and act on it.]

### 2. [Next issue …]

## Cross Impact Issues

[Issues the changes cause elsewhere in the codebase. Omit this section when none.]

### [Optional] General Observations

[Architectural concerns or unclear requirements worth discussing, not tied to a specific line.]

### [Optional] Missing Details

[Related files that were missed — e.g. missing docs or missing test cases.]

## References

[Important file references or research links.]
```

Keep feedback concise and precise. Stick to the format above.

---

Git status:

!`git status`

Focus the review on the changes in $ARGUMENTS.
