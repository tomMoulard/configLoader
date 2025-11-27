## Agent Workflow Overview

The agent system follows an iterative workflow to ensure high-quality code generation:

1. **Prompt Enhancement** (@prompt-engineer) - Transforms user requests into detailed, comprehensive prompts with best practices
2. **Execution** (main agent) - Executes the enhanced prompt to implement the requested changes
3. **Dual Code Review** (parallel execution):
   - **3a. Quality Review** (@code-quality-reviewer) - Reviews code for quality, architecture, style, and best practices
   - **3b. Error Analysis** (@error-analyzer) - Reviews code for potential runtime errors, logic bugs, and error-prone patterns
4. **Feedback Loop** (conditional) - If critical issues are found by either reviewer, re-invoke @prompt-engineer with combined feedback and repeat the cycle (max 3 iterations)

### Agent Reference Syntax

Agents are invoked using the `@agent-name` syntax, which corresponds to files in the `agent/` directory:
- `@prompt-engineer` → `agent/prompt-engineer.md`
- `@code-quality-reviewer` → `agent/code-quality-reviewer.md`
- `@error-analyzer` → `agent/error-analyzer.md`

### Critical Context Management

**IMPORTANT**: Subagents operate in isolated sessions and DO NOT have access to:
- The main conversation history
- Files you've previously read
- Code you've just generated
- User context from earlier messages
- Your internal reasoning or memory

**When invoking any subagent, you MUST provide complete, self-contained context including**:
1. **The full code** being reviewed (not just file paths - include the actual code)
2. **All relevant file contents** that the subagent needs to analyze
3. **User's original request** for context on intent
4. **Any constraints or requirements** from the project
5. **Previous iteration feedback** if re-invoking after iteration
6. **Explicit instructions** on what to analyze or generate

**Performance Optimization**:
- Provide all necessary context in the FIRST invocation to avoid back-and-forth
- Include code snippets directly in prompts rather than expecting subagents to read files
- For code review: Pass the complete code being reviewed, not just references
- For prompt engineering: Include user request + any relevant project context
- For error analysis: Include full error messages, stack traces, and relevant code

**Example of GOOD context provision**:
```
Review the following authentication implementation:

[Full code here - 50 lines]

User request: "Add authentication to my API"
Project context: Express.js API, using MongoDB, existing users table
Requirements: JWT-based auth, secure token storage, rate limiting
```

**Example of BAD context provision** (DO NOT DO THIS):
```
Review the authentication code in src/auth.js
```

---

## Automatic Prompt Enhancement for ALL User Requests

At the START of EVERY user request (before performing any other actions), you MUST:

1. Immediately invoke the @prompt-engineer subagent with complete context:
   - The user's original request (full message)
   - Any code snippets the user provided
   - Relevant project context you've gathered
   - Files or codebase information if applicable
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

## Automatic Dual Code Review

After generating, modifying, or refactoring ANY code (except trivial changes), you MUST:

1. **Invoke BOTH review agents IN PARALLEL** (single message with two Task tool calls):
   - @code-quality-reviewer - Reviews quality, architecture, style, best practices
   - @error-analyzer - Reviews for runtime errors, logic bugs, error-prone patterns
   
   **CRITICAL**: Provide complete context to BOTH agents including:
   - The full code you just generated (include the entire implementation)
   - The user's original request
   - Any relevant project context, constraints, or patterns
   - File paths and names for reference
   
2. Wait for BOTH review results to complete
3. **Aggregate findings** from both agents:
   - Collect all CRITICAL issues from both reviewers
   - Collect all IMPORTANT issues from both reviewers
   - Deduplicate any overlapping issues (present as single issue with combined context)
4. **Evaluate severity** of aggregated issues (see Severity Classification below)
5. **If CRITICAL issues found BY EITHER AGENT AND iteration limit not reached**: Re-invoke @prompt-engineer with combined feedback from both agents and repeat the workflow
6. **If no critical issues OR max iterations reached**: Present the final code along with a summary of both reviews

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

## Iterative Feedback Loop Workflow

When the @code-quality-reviewer identifies critical issues, the system automatically enters a feedback loop to improve the code quality.

### Severity Classification System

**CRITICAL Issues** (triggers re-engineering):

*From @code-quality-reviewer:*
- Security vulnerabilities (SQL injection, XSS, authentication bypass, etc.)
- Data loss risks or data corruption possibilities
- Breaking changes to public APIs without proper versioning
- Violations of project architecture that would cause integration failures

*From @error-analyzer:*
- Logic errors that break core functionality (incorrect conditionals, flawed algorithms, wrong calculations)
- Unhandled exceptions that could crash the application (missing try-catch, no null checks)
- Race conditions or concurrency issues (unsynchronized access, deadlock potential)
- Memory leaks or resource exhaustion (unclosed connections, unbounded loops)
- Null pointer dereference risks (accessing properties on potentially undefined/null values)
- Type safety violations that cause runtime errors (type mismatches, invalid casts)
- Off-by-one errors or boundary condition failures (array index errors, loop bounds)
- Infinite loops or non-terminating recursion

*Common to both:*
- Missing essential error handling that could crash the application

**IMPORTANT Issues** (fix if possible, but don't trigger iteration):
- Performance bottlenecks in hot paths
- Missing edge case handling
- Incomplete error messages or logging
- Code duplication (DRY violations)
- Overly complex logic (KISS violations)
- Missing documentation for complex logic
- Style inconsistencies with project standards

**MINOR Issues** (suggestions only):
- Minor style inconsistencies
- Optimization opportunities
- Refactoring suggestions for readability
- Additional test coverage suggestions
- Documentation improvements for simple code

### Iteration Decision Logic

After receiving reports from BOTH @code-quality-reviewer and @error-analyzer, you MUST follow this decision tree:

1. **Count current iteration** (track this throughout the request)
   - Iteration 1: First code generation attempt
   - Iteration 2: First refinement after reviewer feedback
   - Iteration 3: Second refinement after reviewer feedback
   - Maximum: 3 iterations total

   **Implementation**: Track iteration count by:
   - Maintaining a counter variable in your internal reasoning for this user request
   - Including iteration number in all feedback to @prompt-engineer
   - Verifying iteration count before each @code-quality-reviewer invocation
   - If state is lost, default to assuming iteration 3 (max) to prevent loops

2. **Evaluate severity of issues found**:
   - **If NO CRITICAL issues found BY EITHER AGENT**:
     - Accept the code
     - Fix any IMPORTANT issues directly if quick and straightforward (from either agent)
     - Present final code to user with combined review summary

   - **If CRITICAL issues found BY EITHER AGENT AND iteration count < 3**:
     - Re-invoke @prompt-engineer with enhanced feedback from BOTH agents (see Information Passing Protocol below)
     - Execute the NEW enhanced prompt to generate revised code implementation
     - Increment iteration counter
     - Re-invoke BOTH @code-quality-reviewer AND @error-analyzer on the newly generated code (parallel invocation)
     - Return to step 2 of this decision logic to evaluate the new reviews

   - **If CRITICAL issues found BY EITHER AGENT AND iteration count = 3**:
     - Attempt to fix critical issues directly using best judgment
     - Prioritize error-analyzer critical issues first (runtime safety > style issues)
     - Present code to user with honest assessment
     - Clearly communicate remaining limitations or risks
     - Suggest next steps or manual review needs

3. **Loop termination safeguards**:
   - If @prompt-engineer produces substantially identical output on re-invocation: Break loop, present best attempt with explanation
   - If reviewer feedback is inconsistent across iterations: Prioritize latest feedback, continue if iterations remain
   - If identical critical issues appear in 2+ consecutive iterations from EITHER agent: Break loop, escalate to user with detailed explanation
   - If one agent consistently fails or times out: Continue with single agent feedback, log the failure

### Information Passing Protocol

When re-invoking @prompt-engineer due to critical issues, you MUST provide:

1. **The original user request** (preserve user intent)
2. **BOTH reviewers' complete feedback** (especially CRITICAL issues sections)
3. **Code that was generated** (show what didn't work)
4. **Iteration context**: "This is iteration N of 3. Previous attempt had these critical issues: [list from both agents]. Please generate an enhanced prompt that specifically addresses these problems."
5. **Specific constraints from BOTH reviewers**: Extract and emphasize the specific technical requirements that were violated

**Format for re-invocation:**
```
Original user request: [original request - include full user message]

Iteration: [N] of 3

Previous code generated had these CRITICAL issues identified by dual code review:

CODE QUALITY ISSUES (@code-quality-reviewer):
- [Critical issue 1 with details]
- [Critical issue 2 with details]

ERROR ANALYSIS ISSUES (@error-analyzer):
- [Critical issue 1 with details]
- [Critical issue 2 with details]

Code that was reviewed:
[previous code - INCLUDE THE FULL CODE, not just references]

Code Quality Reviewer's complete feedback:
[full code-quality-reviewer output]

Error Analyzer's complete feedback:
[full error-analyzer output]

Project context:
[Any relevant project information, framework, language, existing patterns]

Please generate an enhanced prompt that specifically addresses these critical issues from BOTH perspectives (code quality AND error prevention) while maintaining all other quality requirements. Focus on: [extract key technical requirements from both reviewers' feedback].
```

**Remember**: The @prompt-engineer subagent cannot access the code you generated or reviewer feedback unless you explicitly include it in your prompt. Provide complete, self-contained context for optimal results.

### Mapping Reviewer Output to Severity

When evaluating output from BOTH agents:

**@code-quality-reviewer output:**
- "CRITICAL ISSUES" section → CRITICAL severity (triggers iteration)
- "IMPORTANT IMPROVEMENTS" section → IMPORTANT severity (fix directly if simple)
- "MINOR SUGGESTIONS" section → MINOR severity (note but don't fix)

**@error-analyzer output:**
- Issues marked "High Likelihood" with runtime/logic errors → CRITICAL severity (triggers iteration)
- Issues marked "Medium Likelihood" or missing error handling → IMPORTANT severity
- Issues marked "Low Likelihood" or potential edge cases → MINOR severity

**Conflict resolution:**
- If error-analyzer marks something CRITICAL but code-quality-reviewer marks it MINOR: Treat as CRITICAL (fail-safe approach)
- If same issue reported by both agents: Deduplicate, present once with combined context
- Prioritize runtime safety issues over style issues when both are CRITICAL

If either reviewer uses different terminology, prioritize issues that involve:
security, data loss, crashes, logic errors, or breaking functionality → treat as CRITICAL

**Criteria for fixing IMPORTANT issues directly**:
- The fix requires changes to 5 or fewer lines of code
- The fix involves adding missing error handling or logging (not refactoring core logic)
- The fix is a style/documentation issue
- The fix can be completed in a single file without affecting public APIs

If uncertain whether an IMPORTANT issue can be fixed quickly, present code as-is with reviewer feedback noting the issues.

### Example Iteration Workflow

**Scenario: Adding user authentication with security flaw**

**Iteration 1:**
1. User requests: "Add authentication to my API"
2. @prompt-engineer generates detailed prompt
3. Main agent implements authentication with JWT
4. @code-quality-reviewer identifies: **CRITICAL - JWT tokens stored in localStorage vulnerable to XSS attacks**
5. Iteration count = 1, CRITICAL issue found → Re-invoke @prompt-engineer

**Iteration 2:**
1. @prompt-engineer receives feedback about XSS vulnerability
2. Generates enhanced prompt emphasizing httpOnly cookies and CSRF protection
3. Main agent implements authentication with secure cookie storage
4. @code-quality-reviewer identifies: **IMPORTANT - Missing rate limiting** (not critical)
5. No CRITICAL issues → Accept code, add rate limiting directly, present to user

**Result:** High-quality, secure authentication implementation achieved through iterative refinement.

---

**Scenario: Maximum iterations reached**

**Iteration 1:**
1. User requests: "Implement payment processing"
2. Implementation has critical security flaw
3. Re-invoke @prompt-engineer

**Iteration 2:**
1. New implementation has different critical flaw (data validation missing)
2. Re-invoke @prompt-engineer

**Iteration 3:**
1. New implementation still has critical issue (race condition in transaction)
2. Iteration limit reached (3 of 3)
3. Main agent fixes race condition directly using best judgment
4. Present to user with message: "Implemented payment processing. Note: This is a security-critical feature that went through 3 refinement cycles. Final implementation includes transaction locking to prevent race conditions. Recommend thorough security audit before production deployment."

**Result:** Best-effort implementation with transparent communication about limitations.

### User Communication During Iterations

**Default behavior**: Iterations happen silently without showing intermediate attempts to the user

**When to communicate iteration progress**:
- After max iterations are reached (explain the refinement process)
- If asked by user for status during long operations
- If the iteration reveals fundamental architectural issues that need user input

**How to present final results**:
```
[After 1 iteration]: Present normally with review summary
[After 2-3 iterations]: "I've implemented [feature] with [N] refinement cycles to ensure quality. The implementation [brief description]. Code quality review: [summary of final review]."
[After max iterations with remaining issues]: "I've implemented [feature] through 3 refinement cycles. The implementation [description]. Note: [honest assessment of any remaining limitations]. Recommendation: [suggested next steps]."
```

---

IMPORTANT NOTE: Take a Deep Breath, read the instructions again, read the
inputs again. Each instruction is crucial and must be executed with utmost care
and attention to detail.

Do not forget that MCP servers exist, use them if available/possible.
