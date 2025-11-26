## Agent Workflow Overview

The agent system follows a three-stage workflow to ensure high-quality code generation:

1. **Prompt Enhancement** (@prompt-engineer) - Transforms user requests into detailed, comprehensive prompts with best practices
2. **Execution** (main agent) - Executes the enhanced prompt to implement the requested changes
3. **Quality Review** (@code-quality-reviewer) - Reviews the generated code for quality, consistency, and adherence to standards

### Agent Reference Syntax

Agents are invoked using the `@agent-name` syntax, which corresponds to files in the `agent/` directory:
- `@prompt-engineer` → `agent/prompt-engineer.md`
- `@code-quality-reviewer` → `agent/code-quality-reviewer.md`

---

## Automatic Prompt Enhancement for ALL User Requests

At the START of EVERY user request (before performing any other actions), you MUST:

1. Immediately invoke the @prompt-engineer subagent with the user's original request
2. Wait for the enhanced, optimized prompt
3. Use the enhanced prompt as your actual instructions for completing the task
4. Execute the task based on the enhanced prompt (do NOT show the enhanced prompt to the user unless they explicitly request it)

The @prompt-engineer will transform vague or ambiguous requests into comprehensive, structured instructions that ensure:
- Best practices are applied (SOLID, DRY, KISS)
- Code style consistency is maintained
- Error handling is comprehensive
- Security and performance are considered
- Edge cases are handled
- All necessary context is inferred from the codebase

### When to Auto-Enhance Prompts:

- ALL code addition requests
- ALL code modification requests
- ALL refactoring requests
- ALL bug fix requests
- ALL feature implementation requests
- ANY request that involves writing or modifying code

### When to Skip:

- Simple informational questions (e.g., "What does this function do?")
- File reading requests without modification (e.g., "Show me the config file")
- Conversational or clarification requests
- Requests that are already extremely detailed and comprehensive

### Example Usage Pattern:

**User**: "Add authentication to my API"
**You**:
1. [Silently invoke @prompt-engineer with: "Add authentication to my API"]
2. [Receive enhanced prompt with detailed requirements: infer auth type, add error handling, follow project patterns, implement rate limiting, add logging, etc.]
3. [Execute the task using the enhanced prompt as your instructions]
4. [Present the completed implementation to the user]

**User**: "Refactor this code"
**You**:
1. [Silently invoke @prompt-engineer with: "Refactor this code"]
2. [Receive enhanced prompt specifying: apply SOLID principles, extract duplicated code, improve naming, add error handling, optimize performance, etc.]
3. [Execute the refactoring using the enhanced prompt]
4. [Present the refactored code to the user]

---

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

---

IMPORTANT NOTE: Take a Deep Breath, read the instructions again, read the
inputs again. Each instruction is crucial and must be executed with utmost care
and attention to detail.

Do not forget that MCP servers exist, use them if available/possible.
