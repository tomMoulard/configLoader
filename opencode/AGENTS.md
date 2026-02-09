## Agent Workflow Overview

The agent system follows an enhanced iterative workflow to ensure high-quality, performant, well-tested code generation. The workflow adapts based on task complexity to balance thoroughness with efficiency.

### Workflow Steps

1. **Task Classification** - Determine task complexity to select appropriate workflow path
2. **Prompt Enhancement** (@prompt-engineer) - Transform requests into detailed prompts (for MODERATE/COMPLEX tasks)
3. **Execution** (main agent) - Implement the requested changes
4. **Smoke Test** - Quick automated verification (type check, lint, tests)
5. **Triple Code Review** (parallel, for MODERATE/COMPLEX tasks):
   - **5a. Quality Review** (@code-quality-reviewer) - Reviews code for quality, architecture, style, and best practices
   - **5b. Error Analysis** (@error-analyzer) - Reviews code for potential runtime errors, logic bugs, and error-prone patterns
   - **5c. Performance Analysis** (@performance-analyzer) - Reviews code for performance bottlenecks, scalability issues, and optimization opportunities
6. **Feedback Loop** (conditional) - If critical issues are found, re-invoke @prompt-engineer with combined feedback (max 3 iterations)
7. **Test Generation** (conditional) - For new features or significant logic changes, invoke @test-engineer
8. **Documentation Check** - Verify documentation is updated for public APIs and complex logic

### Agent Reference Syntax

Agents are invoked using the `@agent-name` syntax, which corresponds to files in the `agent/` directory:
- `@prompt-engineer` → `agent/prompt-engineer.md`
- `@code-quality-reviewer` → `agent/code-quality-reviewer.md`
- `@error-analyzer` → `agent/error-analyzer.md`
- `@performance-analyzer` → `agent/performance-analyzer.md`
- `@test-engineer` → `agent/test-engineer.md`
- `@documenter` → `agent/documenter.md`

---

## Task Classification (REQUIRED First Step)

Before any coding task, classify its complexity to determine the appropriate workflow path:

### TRIVIAL Tasks (Minimal Workflow)

Skip prompt enhancement and full review. Execute directly with smoke test only.

**Examples:**
- Single-line fixes (typos, simple corrections)
- Continuing previous work with clear, documented next steps
- Fixing specific, already-documented issues (e.g., "Fix CR-1 from TODO.md")
- Running tests, builds, or other commands
- Simple questions or information requests
- Adding simple comments or documentation updates
- Formatting-only changes

**Workflow:** Execute → Smoke Test → Done

### MODERATE Tasks (Standard Workflow)

Use lightweight prompt enhancement and targeted review.

**Examples:**
- Fixing 2-5 specific, well-defined issues
- Small feature additions (< 50 lines)
- Targeted refactoring within a single file
- Adding error handling to existing code
- Implementing a well-specified interface

**Workflow:** Prompt Enhancement (lightweight) → Execute → Smoke Test → Triple Review → Done

### COMPLEX Tasks (Full Workflow)

Use full prompt enhancement, comprehensive review, and potentially multiple iterations.

**Examples:**
- New feature implementations
- Large refactoring across multiple files
- Architectural changes
- Security-critical code (authentication, authorization, encryption)
- Database schema changes
- API design and implementation
- Performance-critical optimizations

**Workflow:** Prompt Enhancement (full) → Execute → Smoke Test → Triple Review → Iterate if needed → Test Generation → Documentation

### Classification Decision Tree

```
Is it a simple question or command?
  YES → TRIVIAL
  NO  ↓

Is it fixing already-documented issues (from TODO, code review, etc.)?
  YES → Use FIX VERIFICATION MODE (see below)
  NO  ↓

Does it involve < 20 lines of code changes?
  YES → TRIVIAL or MODERATE (use judgment)
  NO  ↓

Does it involve security, architecture, or new features?
  YES → COMPLEX
  NO  → MODERATE
```

---

## Fix Verification Mode

When fixing **already-identified issues** (from TODO.md, code review findings, or previous analysis), use this streamlined workflow:

### When to Use

- Fixing issues documented in TODO.md (e.g., "Fix CR-1", "Address performance issue in X")
- Fixing issues from a previous code review session
- Applying suggested fixes from @code-quality-reviewer, @error-analyzer, or @performance-analyzer
- Fixing linter or type checker errors

### Workflow

1. **Skip prompt enhancement** - The issue is already well-defined
2. **Apply the fix directly** - Use the documented solution or apply best judgment
3. **Run targeted verification**:
   - Type check: `tsc --noEmit` or equivalent
   - Lint: `eslint .` or equivalent  
   - Run relevant tests (not full suite if targeted tests exist)
   - Verify the specific issue is resolved
4. **Skip full triple review** - The issue was already analyzed

### When to Escalate to Full Review

Invoke full triple review ONLY if:
- Fix required significant code changes (>20 lines)
- Fix touched security-critical code
- Fix had unexpected side effects (tests failing, type errors)
- User explicitly requests review

### Batch Fix Pattern

When fixing multiple similar issues:

1. **Group similar fixes** by pattern, file type, or category
2. **Apply all fixes in one pass** before any verification
3. **Run single verification** after all fixes are applied
4. **Report batch results** with summary

**Example:**
```
Fixing callback dependency issues (CR-4a, CR-4b, CR-4c):
- All three use the same pattern: functional state update
- Applied all fixes to PersonContext.tsx
- Verification: Type check passed, tests passed
- Result: All 3 issues resolved
```

---

## Smoke Test (REQUIRED After Code Generation)

Before invoking the triple code review, run quick automated checks to catch obvious issues early:

### Smoke Test Steps

1. **Type Check** (if TypeScript/typed language):
   ```bash
   tsc --noEmit  # TypeScript
   mypy .        # Python
   go build ./...  # Go
   ```

2. **Lint**:
   ```bash
   eslint .      # JavaScript/TypeScript
   ruff check .  # Python
   golangci-lint run  # Go
   ```

3. **Run Tests** (fast subset or affected tests):
   ```bash
   npm test              # Full suite if fast
   npm test -- --changed # Or just changed files
   pytest -x --ff        # Python: fail fast, failed first
   ```

### Smoke Test Decision Logic

**If smoke test FAILS:**
- Fix the obvious issues directly (type errors, lint errors, test failures)
- Re-run smoke test
- Only proceed to triple review after smoke test passes
- Do NOT invoke triple review on broken code

**If smoke test PASSES:**
- Proceed to triple review for deeper analysis (MODERATE/COMPLEX tasks)
- Or mark task complete (TRIVIAL tasks)

### Smoke Test Skip Conditions

Skip smoke test only for:
- Pure documentation changes
- Configuration file changes (unless they affect build)
- Non-code file changes (images, assets)

---

## Context Management

### Critical Context Requirements

Subagents operate in isolated sessions and DO NOT have access to:
- The main conversation history
- Files you've previously read
- Code you've just generated
- User context from earlier messages
- Your internal reasoning or memory

### Context Provision Protocol

**First invocation** in a session - Provide complete context:
1. **The full code** being reviewed (not just file paths - include the actual code)
2. **All relevant file contents** that the subagent needs to analyze
3. **User's original request** for context on intent
4. **Any constraints or requirements** from the project
5. **Previous iteration feedback** if re-invoking after iteration
6. **Explicit instructions** on what to analyze or generate

**Subsequent invocations** (same task, same session) - Provide delta context:
```
Previous analysis: [1-2 sentence summary of findings]
Changes since then: [specific changes made]
Focus area: [what specifically needs review now]
New constraints: [any new requirements]
```

### Context Examples

**Good context provision:**
```
Review the following authentication implementation:

[Full code here - 50 lines]

User request: "Add authentication to my API"
Project context: Express.js API, using MongoDB, existing users table
Requirements: JWT-based auth, secure token storage, rate limiting
```

**Bad context provision (DO NOT DO THIS):**
```
Review the authentication code in src/auth.js
```

**Good delta context (subsequent invocation):**
```
Previous analysis: Found XSS vulnerability in token storage, suggested httpOnly cookies
Changes made: Switched from localStorage to httpOnly cookies, added CSRF protection
Focus area: Verify the security fix is correct and complete
```

---

## Prompt Enhancement (MODERATE/COMPLEX Tasks Only)

At the START of MODERATE or COMPLEX tasks (before performing any other actions), invoke @prompt-engineer:

1. Invoke @prompt-engineer with complete context:
   - The user's original request (full message)
   - Any code snippets the user provided
   - Relevant project context you've gathered
   - Task classification (MODERATE or COMPLEX)
2. Wait for the enhanced, optimized prompt
3. Use the enhanced prompt as your actual instructions
4. Execute the task based on the enhanced prompt

### When to Skip Prompt Enhancement

- **TRIVIAL tasks** - Execute directly
- **Fix Verification Mode** - Issue already well-defined
- **Continuation requests** - "Continue", "Keep going", "What's next?"
- **Requests with extremely detailed specifications** - Already comprehensive

### Prompt Enhancement Levels

**Lightweight (MODERATE tasks):**
- Focus on immediate requirements
- Infer coding style from existing code
- Add basic error handling requirements
- Skip extensive edge case enumeration

**Full (COMPLEX tasks):**
- Comprehensive requirements analysis
- Security and performance considerations
- Edge case enumeration
- Integration requirements
- Testing considerations

---

## Triple Code Review (MODERATE/COMPLEX Tasks)

After code generation passes smoke test, invoke all three review agents IN PARALLEL:

### Invocation

Send a single message with three Task tool calls:
- @code-quality-reviewer - Quality, architecture, style, best practices
- @error-analyzer - Runtime errors, logic bugs, error-prone patterns
- @performance-analyzer - Performance bottlenecks, scalability, optimization

### Required Context for All Agents

Include in EACH agent invocation:
- The full code you just generated (complete implementation)
- The user's original request
- Any relevant project context, constraints, or patterns
- File paths and names for reference

### Incremental Review Mode

When reviewing code after modifications (not new code):

1. **Identify changed lines/functions** using git diff or description
2. **Instruct reviewers to focus on changes**:
   ```
   Focus your review on the following changes:
   - Modified: src/auth.js lines 42-67 (token validation logic)
   - Added: src/middleware/csrf.js (new file)
   
   Previously reviewed and unchanged:
   - src/auth.js lines 1-41 (already passed review)
   ```
3. **Carry forward previous analysis** for context
4. **Skip re-reviewing unchanged code** that passed previous review

### Review Aggregation

After receiving all three reports:

1. **Aggregate findings**:
   - Collect all CRITICAL issues from all reviewers
   - Collect all IMPORTANT issues from all reviewers
   - Deduplicate overlapping issues (present once with combined context)

2. **Evaluate severity** using the classification below

3. **Make decision**:
   - No CRITICAL issues → Accept code, fix IMPORTANT issues if quick
   - CRITICAL issues found AND iterations < 3 → Enter feedback loop
   - CRITICAL issues found AND iterations = 3 → Fix directly, present with limitations

---

## Severity Classification System

### CRITICAL Issues (Triggers Re-engineering)

*From @code-quality-reviewer:*
- Security vulnerabilities (SQL injection, XSS, authentication bypass, etc.)
- Data loss risks or data corruption possibilities
- Breaking changes to public APIs without proper versioning
- Violations of project architecture that would cause integration failures

*From @error-analyzer:*
- Logic errors that break core functionality
- Unhandled exceptions that could crash the application
- Race conditions or concurrency issues
- Memory leaks or resource exhaustion
- Null pointer dereference risks
- Type safety violations causing runtime errors
- Off-by-one errors or boundary condition failures
- Infinite loops or non-terminating recursion

*From @performance-analyzer:*
- O(n²) or worse algorithmic complexity in critical paths
- N+1 query problems
- Blocking operations that prevent scaling
- Memory growth patterns causing OOM errors
- Database queries without indexes on frequently queried columns

### IMPORTANT Issues (Fix if Quick, Don't Iterate)

- Performance bottlenecks in hot paths
- Missing edge case handling
- Incomplete error messages or logging
- Code duplication (DRY violations)
- Overly complex logic (KISS violations)
- Missing documentation for complex logic
- Style inconsistencies with project standards

### MINOR Issues (Note Only)

- Minor style inconsistencies
- Optimization opportunities
- Refactoring suggestions for readability
- Additional test coverage suggestions

---

## Iterative Feedback Loop (Max 3 Iterations)

### Iteration Tracking

Track iteration count throughout the request:
- **Iteration 1**: First code generation attempt
- **Iteration 2**: First refinement after reviewer feedback
- **Iteration 3**: Final refinement (max)

If state is lost, default to assuming iteration 3 to prevent infinite loops.

### Iteration Strategy

- **Iterations 1-2**: Address ALL critical issues aggressively
- **Iteration 3**: Focus on the MOST IMPACTFUL remaining critical issues
- **Same issues persist 2 consecutive iterations**: Break loop, escalate to user

### Feedback Loop Decision Logic

```
IF no CRITICAL issues from ANY agent:
  → Accept code
  → Fix IMPORTANT issues directly if < 5 lines each
  → Present final code with review summary

IF CRITICAL issues found AND iteration < 3:
  → Re-invoke @prompt-engineer with Review Delta Format
  → Execute NEW enhanced prompt
  → Increment iteration counter
  → Re-run smoke test
  → Re-invoke triple review (parallel)
  → Return to decision logic

IF CRITICAL issues found AND iteration = 3:
  → Attempt to fix critical issues directly
  → Prioritize error-analyzer issues (runtime safety > style)
  → Present code with honest assessment
  → Communicate remaining limitations
  → Suggest next steps or manual review
```

### Review Delta Format (For Re-invocation)

When re-invoking @prompt-engineer due to critical issues, use this structured format:

```
ITERATION: [N] of 3
TASK: [One-line summary of original request]

RESOLVED SINCE LAST ITERATION:
- [Issue that was fixed]
- [Another fixed issue]

STILL CRITICAL (must address):
- [Remaining issue 1]: [Location] - [Brief description]
- [Remaining issue 2]: [Location] - [Brief description]

NEW ISSUES INTRODUCED:
- [Any new issues from last attempt]

TECHNICAL CONSTRAINTS:
- [Specific technical requirement from reviewers]
- [Another constraint]

PREVIOUS CODE:
[Include relevant code sections, not entire files if large]

FOCUS FOR THIS ITERATION:
[Specific guidance on what to prioritize]
```

### Loop Termination Safeguards

- **Identical output**: If @prompt-engineer produces substantially identical output → Break loop, present best attempt
- **Inconsistent feedback**: Prioritize latest feedback, continue if iterations remain
- **Identical critical issues 2+ times**: Break loop, escalate to user with explanation
- **Agent failure/timeout**: Continue with remaining agents' feedback

---

## Test Integration

### Pre-Coding Test Check

Before implementing new features:
1. Check if relevant tests exist for the area being modified
2. Note any existing test patterns to follow
3. Plan what tests will be needed

### Post-Coding Test Execution

After code generation (part of smoke test):
1. Run affected tests immediately
2. If tests fail, fix before proceeding to review
3. Note any tests that need updating due to intentional behavior changes

### Test Generation Triggers

Invoke @test-engineer ONLY when:
- New code has no existing tests
- Coverage dropped below project threshold
- New edge cases identified during review
- User explicitly requests tests
- Security-critical code added (always test auth, encryption, etc.)

### Test Generation Skip Conditions

Skip @test-engineer for:
- Code already well-tested (passing existing tests)
- Trivial changes (formatting, comments, simple fixes)
- Non-testable changes (documentation, configuration)

---

## Documentation Check

### Automatic Documentation Requirements

After code passes review, check documentation needs:

**Always update docs for:**
- New public APIs (functions, classes, endpoints)
- Changed behavior of existing public APIs
- New configuration options
- Breaking changes

**Add inline comments for:**
- Complex algorithms or logic
- Non-obvious code decisions
- Workarounds or hacks (with explanation)
- Performance-critical sections

### Documentation Workflow

1. **Check if docs needed**: Did we add/modify public API? Add complex logic?
2. **For simple docs**: Add inline comments or JSDoc directly
3. **For complex docs**: Invoke @documenter only for:
   - New public APIs requiring usage examples
   - Architecture documentation
   - Migration guides
   - Complex feature documentation

### Documentation Skip Conditions

Skip documentation updates for:
- Internal/private functions
- Self-explanatory code
- Test files
- Already well-documented code

---

## User Communication

### During Execution

**Default behavior**: Work silently without showing intermediate steps

**Communicate when**:
- Task will take significant time (>30 seconds estimated)
- Clarification needed before proceeding
- Unexpected issues discovered
- Max iterations reached

### After Completion

**After 1 iteration (passed first try):**
```
[Present implementation normally]
Review summary: [Brief summary of review findings, if any important/minor issues noted]
```

**After 2 iterations:**
```
Implemented [feature] with one refinement cycle to address [brief issue].
[Present implementation]
Review summary: [Summary of final review]
```

**After 3 iterations:**
```
Implemented [feature] through 3 refinement cycles.
[Present implementation]
Note: [Honest assessment of any remaining limitations]
Recommendation: [Suggested next steps if applicable]
```

**After max iterations with remaining issues:**
```
Implemented [feature] through 3 refinement cycles.
[Present implementation]

Remaining considerations:
- [Honest description of limitation 1]
- [Honest description of limitation 2]

Recommendation: [Manual review needed / Additional testing suggested / etc.]
```

---

## Quick Reference

### Workflow by Task Type

| Task Type | Prompt Eng | Execute | Smoke Test | Triple Review | Iterate | Tests | Docs |
|-----------|------------|---------|------------|---------------|---------|-------|------|
| TRIVIAL | Skip | Yes | Yes | Skip | No | Skip | If needed |
| FIX MODE | Skip | Yes | Yes | Skip* | No | Skip | Skip |
| MODERATE | Lightweight | Yes | Yes | Yes | If critical | If gaps | If API |
| COMPLEX | Full | Yes | Yes | Yes | Up to 3x | Yes | Yes |

*Escalate to full review if fix is large or touches security code

### Decision Flowchart

```
User Request
    │
    ▼
Task Classification
    │
    ├─ TRIVIAL ────────────────────────────────────┐
    │                                               │
    ├─ FIX MODE (documented issues) ───────────────┤
    │                                               │
    ├─ MODERATE ──┬─ Prompt Eng (light) ──┐        │
    │             │                        │        │
    └─ COMPLEX ───┴─ Prompt Eng (full) ───┤        │
                                           │        │
                                           ▼        │
                                       Execute      │
                                           │        │
                                           ▼        ▼
                                      Smoke Test ◄──┘
                                           │
                            ┌──────────────┼──────────────┐
                            │              │              │
                         TRIVIAL     MODERATE/COMPLEX  FIX MODE
                            │              │              │
                            ▼              ▼              ▼
                          Done      Triple Review    Verify Fix
                                          │              │
                                          ▼              ▼
                                    Critical?         Done
                                     │    │
                                    YES   NO
                                     │    │
                                     ▼    ▼
                              Iterate  Accept
                              (max 3)    │
                                         ▼
                                   Tests/Docs
                                         │
                                         ▼
                                       Done
```

---

IMPORTANT NOTE: Take a Deep Breath, read the instructions again, read the inputs again. Each instruction is crucial and must be executed with utmost care and attention to detail.

Do not forget that MCP servers exist, use them if available/possible.
