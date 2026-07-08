# Tasks: Sidebar & Scroll Refinement

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | ~55 (15 surgical edits) |
| 400-line budget risk | Low |
| Chained PRs recommended | Yes |
| Suggested split | PR 1 (State & Cache) → PR 2 (UI & Scroll) |
| Delivery strategy | force-chained |
| Chain strategy | feature-branch-chain |

Decision needed before apply: No
Chained PRs recommended: Yes
Chain strategy: feature-branch-chain
400-line budget risk: Low

### Suggested Work Units

| Unit | Goal | Likely PR | Notes |
|------|------|-----------|-------|
| 1 | State & height cache infrastructure | PR 1 | Establishes per-branch caches, sidebar_visible state, persistence, gate simplification |
| 2 | UI & scroll visual refinements | PR 2 | Depends on PR 1 — scrollbar, border, measured heights, toggle/show-manifest cleanup |

---

## PR 1: State & Height Cache Infrastructure

**Target**: feature/sidebar-scroll-behavior (tracker branch)
**PR 1 base**: feature/sidebar-scroll-behavior
**Est. lines**: ~30 changed, 9 edits

### 1.1 Split `last_content_h` into per-branch caches

- [x] **File**: `gui/main_window.lua`, line 32  
- [x] **Change**: Replace `last_content_h = nil` → `last_content_h_with_sb = nil, last_content_h_no_sb = nil`  
- [x] **Verify**: `grep` shows both cache fields in state init, no remaining single `last_content_h`

### 1.2 Add `sidebar_visible = true` to state init

- [x] **File**: `gui/main_window.lua`, line ~32 (after caches)  
- [x] **Change**: Add `sidebar_visible = true` to state table  
- [x] **Verify**: Default is `true` (sidebar visible on first launch)

### 1.3 Persist `sidebar_visible` in `save_prefs`

- [x] **File**: `gui/main_window.lua`, after line 56  
- [x] **Change**: Add `reaper.SetExtState(S, "sidebar_visible", state.sidebar_visible and "1" or "0", true)`  
- [x] **Verify**: Toggle sidebar, restart script — state persists

### 1.4 Restore `sidebar_visible` in `load_prefs`

- [x] **File**: `gui/main_window.lua`, after line 79  
- [x] **Change**: Add `local sv = reaper.GetExtState(S, "sidebar_visible"); if sv ~= "" then state.sidebar_visible = sv == "1" end`  
- [x] **Verify**: First launch defaults to `true`; subsequent launches restore saved state

### 1.5 Simplify `show_sidebar` gate

- [x] **File**: `gui/main_window.lua`, line 1062  
- [x] **Change**: Replace compound expression → `local show_sidebar = state.sidebar_visible`  
- [x] **Verify**: Toggle ◀ hides sidebar immediately regardless of stems/manifest state

### 1.6 Branch-aware height constraint block

- [x] **File**: `gui/main_window.lua`, lines 1069-1080  
- [x] **Change**: Replace single-cache lock with `cache_key`-based branch: use `last_content_h_with_sb` or `last_content_h_no_sb` based on `show_sidebar`; set `max_w = 9999` unconditionally (WIDTH-FREE)  
- [x] **Verify**: Toggle sidebar — window height stays stable (no flicker), width resizable

### 1.7 Toggle button — remove nil, add `save_prefs()`

- [x] **File**: `gui/main_window.lua`, lines 1141-1143  
- [x] **Change**: Remove `state.last_content_h = nil`; keep `state.sidebar_visible = not state.sidebar_visible`; add `save_prefs()`  
- [x] **Verify**: One click toggles sidebar, state persists after restart

### 1.8 Browse + `scan_folder` nil both caches

- [x] **Files**: `gui/main_window.lua`, line 1124 (Browse) and line 587 (scan_folder)  
- [x] **Change**: Replace `state.last_content_h = nil` → nil BOTH `last_content_h_with_sb` and `last_content_h_no_sb`  
- [x] **Verify**: After scan/new folder, window resizes freely to accommodate new content

### 1.9 Branch-aware post-sidebar height caching + remove `cached_main_h`

- [x] **File**: `gui/main_window.lua`, lines 1533-1538  
- [x] **Change**: Replace entire block — if `show_sidebar`, save to `last_content_h_with_sb`; else save to `last_content_h_no_sb`. Remove `cached_main_h` variable  
- [x] **Verify**: Toggle sidebar — correct cache is updated each frame

---

## PR 2: UI & Scroll Visual Refinements

**Target**: feature/sidebar-scroll-behavior (tracker branch)
**PR 2 base**: PR 1 branch (child targets previous PR)
**Est. lines**: ~20 changed, 6 edits

### 2.1 Remove `NoScrollbar` from sidebar

**File**: `gui/main_window.lua`, line 1328  
**Change**: Remove `ImGui.ImGui_WindowFlags_NoScrollbar()` flag from `BeginChild("##sidebar", ...)`  
**Verify**: Manifest with 30+ items shows scrollbar and all items reachable

### 2.2 Replace manifest height with measured split

**File**: `gui/main_window.lua`, line 1335  
**Change**: Replace `math.max(60, math.floor(sb_full_h / 2) - 28)` → measure header + separator + padding, then proportional 40/60 split  
**Verify**: Manifest takes ~40% of available height, stems ~60% with visible separator

### 2.3 Add conditional border to stems child

**File**: `gui/main_window.lua`, line 1416  
**Change**: Add `stems_flags` variable — set `ChildFlags_Borders` when `not show_sidebar and not state.show_manifest`; pass to `BeginChild("##stems", ..., stems_flags)`  
**Verify**: Sidebar hidden + manifest off → stems child has visible bottom border

### 2.4 Remove `last_content_h = nil` from Show Manifest button

**File**: `gui/main_window.lua`, line 1182  
**Change**: Remove `state.last_content_h = nil` line (both caches are already invalidated by PR 1's toggle logic if needed)  
**Verify**: Toggling Show Manifest does not trigger height flicker

### 2.5 Add `NoScrollbar` removal test with Deep Scan

**File**: `gui/main_window.lua`, testing sidebar  
**Change**: Already covered by 2.1 — verify many stems fill the stems child, scrollbar appears, all items reachable  
**Verify**: Sidebar scrolls with 50+ stems, no content clipped

### 2.6 Keep Show Manifest auto-show sidebar

**File**: `gui/main_window.lua`, line 1181  
**Change**: No change needed — `if state.show_manifest then state.sidebar_visible = true end` is intentional UX  
**Verify**: Show Manifest checked while sidebar hidden reveals sidebar automatically

---

## Manual Verification Steps (both PRs)

| Scenario | Steps | Expected |
|----------|-------|----------|
| 1-click toggle | Click ◀ → click ▶ | Sidebar hides/shows each click, no double-click needed |
| No flicker | Toggle ◀/▶ rapidly 5x | Window height stable, no visible resize jump |
| Persistence | Hide sidebar → restart script | Sidebar stays hidden, ▶ shown |
| First launch | Delete ExtState → restart | Sidebar visible, ◀ shown |
| Scroll works | Scan 50+ stems, open manifest | All items reachable via scroll, scrollbar visible |
| Width resize locked | Toggle sidebar → drag edge | Width changes, height unchanged |
| Stems border | Hide sidebar + uncheck Show Manifest | Stems child has visible bottom border |
| No double-border | Show sidebar + Show Manifest | Stems has no border, separator between sections |

---

## Implementation Order

**PR 1 first** — establishes the per-branch cache and `sidebar_visible` state that all downstream changes depend on. Without this, PR 2's cleanup of `cached_main_h` and `last_content_h = nil` references would conflict.

**PR 2 second** — builds on PR 1's state model. The scroll, border, and measured height changes are mechanically independent of the cache, but they share the same file region and removing old `last_content_h` references requires the new cache names from PR 1.
