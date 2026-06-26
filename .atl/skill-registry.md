# Skill Registry

Generated: 2026-06-25
Scope: user (system) — ~/.config/opencode/skills/

## Rules

- **Excluded from index**: `sdd-*`, `_shared`, `skill-registry` (infrastructure skills)
- **Deduplication**: project-level skills preferred over user-level (none found at project level)
- **Index format**: name, trigger description, path, scope

---

## User Skills

| Name | Trigger | Path | Scope |
|------|---------|------|-------|
| branch-pr | Create Gentle AI pull requests with issue-first checks. Trigger: creating, opening, or preparing PRs for review. | `~/.config/opencode/skills/branch-pr/SKILL.md` | user |
| chained-pr | Trigger: PRs over 400 lines, stacked PRs, review slices. Split oversized changes into chained PRs that protect review focus. | `~/.config/opencode/skills/chained-pr/SKILL.md` | user |
| cognitive-doc-design | Design docs that reduce cognitive load. Trigger: writing guides, READMEs, RFCs, onboarding, architecture, or review-facing docs. | `~/.config/opencode/skills/cognitive-doc-design/SKILL.md` | user |
| comment-writer | Write warm, direct collaboration comments. Trigger: PR feedback, issue replies, reviews, Slack messages, or GitHub comments. | `~/.config/opencode/skills/comment-writer/SKILL.md` | user |
| customize-opencode | Use ONLY when the user is editing or creating opencode's own configuration: opencode.json, opencode.jsonc, files under .opencode/, or files under ~/.config/opencode/. Also use when creating or fixing opencode agents, subagents, skills, plugins, MCP servers, or permission rules. Do not use for the user's own application code, or for any project that is not configuring opencode itself. | `~/.config/opencode/skills/customize-opencode/SKILL.md` | user |
| go-testing | Trigger: Go tests, go test coverage, Bubbletea teatest, golden files. Apply focused Go testing patterns. | `~/.config/opencode/skills/go-testing/SKILL.md` | user |
| issue-creation | Create Gentle AI issues with issue-first checks. Trigger: creating GitHub issues, bug reports, or feature requests. | `~/.config/opencode/skills/issue-creation/SKILL.md` | user |
| judgment-day | Trigger: judgment day, dual review, adversarial review, juzgar. Run blind dual review, fix confirmed issues, then re-judge. | `~/.config/opencode/skills/judgment-day/SKILL.md` | user |
| skill-creator | Trigger: new skills, agent instructions, documenting AI usage patterns. Create LLM-first skills with valid frontmatter. | `~/.config/opencode/skills/skill-creator/SKILL.md` | user |
| skill-improver | Trigger: improve skills, audit skills, refactor skills, skill quality. Audit and upgrade existing LLM-first skills. | `~/.config/opencode/skills/skill-improver/SKILL.md` | user |
| work-unit-commits | Plan commits as reviewable work units. Trigger: implementation, commit splitting, chained PRs, or keeping tests and docs with code. | `~/.config/opencode/skills/work-unit-commits/SKILL.md` | user |

## Infrastructure Skills (excluded from index)

| Name | Reason |
|------|--------|
| sdd-init | SDD lifecycle skill |
| sdd-propose | SDD lifecycle skill |
| sdd-spec | SDD lifecycle skill |
| sdd-design | SDD lifecycle skill |
| sdd-tasks | SDD lifecycle skill |
| sdd-apply | SDD lifecycle skill |
| sdd-verify | SDD lifecycle skill |
| sdd-archive | SDD lifecycle skill |
| sdd-explore | SDD lifecycle skill |
| sdd-onboard | SDD lifecycle skill |
| _shared | Shared SDD references — not invokable |
| skill-registry | Registry maintenance skill — not invokable directly |

## Project Skills

None detected. No skills found under project-level directories (skills/, .opencode/skills/, .claude/skills/, .gemini/skills/, .cursor/skills/, .github/skills/, .codex/skills/, .qwen/skills/, .kiro/skills/, .openclaw/skills/, .pi/skills/, .agent/skills/, .agents/skills/, .atl/skills/).

## Project Convention Files

| Type | Path | Found |
|------|------|-------|
| AGENTS.md | `{project}/AGENTS.md` | ❌ |
| CLAUDE.md | `{project}/CLAUDE.md` | ❌ |
| .cursorrules | `{project}/.cursorrules` | ❌ |
| GEMINI.md | `{project}/GEMINI.md` | ❌ |
| copilot-instructions.md | `{project}/copilot-instructions.md` | ❌ |

---

## Usage

Sub-agents: load a skill by reading the SKILL.md path directly. Do not rely on this registry as a summary — always read the source of truth.
