## Automatic Code Quality Review

After generating, modifying, or refactoring ANY code (except trivial changes), you MUST:

1. Immediately invoke the @code-quality-reviewer subagent to review the changes
2. Wait for the review results
3. If critical issues are found, fix them before presenting to the user
4. Present the final code along with a summary of the review

### When to Auto-Review:

- New feature implementations
- Bug fixes that change logic
- Refactoring operations
- Any code changes spanning 5+ lines

### When to Skip:

- Single-line typo fixes
- Adding simple comments
- Formatting-only changes
- Documentation updates
