# Accessibility Stream Pipeline — BH Cleanup Spec

## Mental Model

The accessibility tree is a live signal. BH observes it through a pipeline with
two intensities:

**Passive pipe** — always running. Parses the visible tree on settle, updates the
internal world representation. Change detection, screen identity, semantic
hashing. One parse, no scrolling. The heartbeat.

**Active scan** — engaged on every `get_interface` and after every action. Scans
every scroll view end-to-end, parses at each viewport position, restores all
scroll positions when done. The agent gets the complete interface — every element
in every list — without knowing scrolling happened. The scan is the cost of
understanding. You pay it once per settled screen.

Both use the same primitive: `parse() → Screen → Screen.merging()`. The passive
pipe calls it once. The active scan calls it many times at different scroll
positions. The difference is how many times and whether we move the viewport.

### How the agent sees it

The agent doesn't know about scroll views. It sees lists with elements. BH scans
the scroll views internally and presents the complete list. When the agent targets
an off-screen element, BH scrolls to it, acts, and the agent never knows.

The scroll view is an implementation detail — like cell reuse or z-ordering. The
agent thinks in lists and elements, not viewports and content offsets.

### What's different from today

The pipeline architecture already exists. `startPassiveSemanticObservation()` is
the passive pipe. `exploreScreen()` / `scanPendingContainers()` is the active
scan. `Screen.merging()` is the merge primitive.

What's wrong is the active scan's internals. It grew a parallel merge
infrastructure (fingerprint overlap, page reconciliation, leading edge reset)
instead of reusing `Screen.merging()`. This cleanup strips the scan back to:
move viewport → parse → merge → repeat.

## What This Is

A cleanup of BH's scroll exploration. Not a new system. The same flow, simplified:

1. Drop fingerprint stitching and page reconciliation — `Screen.merging()` by
   HeistId already handles cross-parse identity
2. Add scroll inventory — ask `accessibilityElementCount` instead of guessing
3. Unify exploration and inflation into one scan primitive
4. Present scroll containers as lists to the agent, not as scrollable viewports

## Complexity Budget

### Removed (~400 lines)

**Fingerprint overlap detection** (`PageOverlap.swift`, ~80 lines) — O(n²)
sliding window comparing hashed element identity across pages. Fragile when
elements change identity between pages. Replaced by nothing — HeistId handles
identity.

**Content fingerprint hashing** (`SafeGeometryHashing.swift`,
`contentFingerprints()`) — hashes label + value + traits + geometry into integers
for overlap comparison. Only exists to feed `findOverlap()`. Replaced by nothing.

**Dual reconciliation strategies** (`reconcileContainerPageByContentOrigin`,
`reconcileContainerPageByOverlap`, ~100 lines) — two algorithms for stitching
pages, content-origin primary with overlap fallback. Replaced by
`Screen.merging()`, one line, already exists.

**Leading edge reset** (`moveToLeadingEdge()`, ~35 lines) — scrolls to the top
before scanning. Up to 50 swipe gestures for swipeable containers. Replaced by
bidirectional scan from current position.

**Swipeable exploration fallback** (gesture simulation + settle detection) —
synthesizes drag gestures for containers without a live `UIScrollView` ref. Slow,
flaky. Replaced by: skip these during exploration. `scrollDispatchView()` resolves
most cases. Swipe scrolling stays for user-initiated `scroll` commands.

**Page scan bookkeeping** (`ContainerScan`, `ContainerPage`,
`ContainerPageEntry`, `ContainerPageReconciliation`, `preparePageScan()`,
`reconcileVisiblePage()`) — types and methods for page-by-page accumulation with
overlap-aware ordering. Replaced by `SemanticExploration.absorb()` which calls
`Screen.merging()`.

**Separate inflation scroll path** (`ElementInflation+SemanticReveal.swift` scroll
logic) — computes target offset from stored `contentSpaceOrigin`, calls
`setContentOffset` without re-parsing to verify. Replaced by the scan primitive
with a target predicate.

**Content-space origin infrastructure** — `contentSpaceOrigin` on
`SemanticScreen.Element`, `ScrollContentLocation`, `screenCoordinateOffsetsByPath`
in `ParseResult`, coordinate conversion math in screen building. Replaced by
scroll inventory — the scan primitive steps through viewport-sized batches, no
per-element coordinates needed.

### Added (~135 lines)

**Scroll inventory** (~30 lines in TheBurglar) — read
`accessibilityElementCount()` and `index(ofAccessibilityElement:)` on scroll views
during screen building. Two public API calls per scroll view. One call returns the
total count without parsing — no tree walk needed to know a list has 5000 items.

**`ScrollInventory` type** (~15 lines) — `totalElementCount: Int?` and
`visibleIndices: [Int]`.

**Unified scan primitive** (~60 lines) — `setContentOffset → yield 1–2 frames →
parse → merge → check condition`. Parameterized by steps and exit condition.
Replaces exploration loop and inflation scroll path.

**Container format changes** (~30 lines) — `──` separators, `⋮` omission
markers, metadata line, closing `── /name ──`.

### Net: ~135 lines replacing ~400 lines. New code is arithmetic and a for loop.
Removed code is hashing, sliding windows, dual-strategy reconciliation, gesture
simulation, and per-element coordinate tracking.

## Part 1: Scroll Inventory

### What changes

TheBurglar already builds `Screen` values from parse results. During
`buildScreen()`, it resolves live `UIScrollView` refs, captures container content
frames, and computes content-space origins. Add one step, remove one step:

**Add:** For each resolved scroll view, read:
1. `accessibilityElementCount()` — total elements. One call, no tree walking.
   A 5000-element table view returns 5000 instantly.
2. `index(ofAccessibilityElement:)` for each visible child — its position in the
   container.

**Remove:** Content-space origin computation. The scan primitive doesn't need
per-element coordinates.

Both API calls are public `UIAccessibility`. The accessibility system already
knows the total count and each element's index. We just ask.

### Where it's stored

On `SemanticScreen.Container` or `LiveCapture`:

```swift
struct ScrollInventory: Sendable, Equatable {
    let totalElementCount: Int?
    let visibleIndices: [Int]
}
```

Not on `AccessibilityContainer` — that's the parser's model type. Scroll inventory
is BH enrichment, same layer as container names, content frames, and live scroll
view refs.

### What it enables

**Scan planning.** The scan primitive knows up front how many steps it needs:
`ceil(totalElementCount / visibleCount)`. No blind scanning, no guessing when to
stop.

**Omission reporting.** When limits cut the scan short, the output shows
`⋮ N more` with an accurate count from the inventory — not a guess from content
size geometry.

**Parser bail avoidance.** The 5000-node parser bail exists to prevent pathological
tree walks. With inventory, we know the total without parsing it. A 5000-element
scroll view reports 5000 via one `accessibilityElementCount` call. The scan
primitive can cap at the configured limit and report the remainder, instead of
the parser bailing mid-walk with no count.

### SwiftUI limitation

`UpdateCoalescingCollectionView` returns `accessibilityElementCount = NSNotFound`.
For SwiftUI scroll views, `totalElementCount` will be nil, visible indices empty.
The scan primitive still works (scrolls and re-parses until no new elements
appear), but the omission count comes from step exhaustion rather than inventory.
The inventory is a bonus for UIKit scroll views.

## Part 2: Scan Primitive

### One primitive, three callers

Today BH has three scroll-and-parse paths. This cleanup unifies them:

| Caller | Steps | Exit condition |
|---|---|---|
| Passive pipe | 0 (no scrolling) | After one parse |
| Inflation (`scroll_to_visible`) | Toward target region | Target element resolves |
| Full scan (`get_interface`) | All positions | All steps exhausted or limit hit |

The inner loop is identical:

```
// 1. Initial parse: full tree
let baseline = parse(root: window)

// 2. For each scrollable container found in baseline:
save scrollView.contentOffset
for step in steps:
    scrollView.setContentOffset(step, animated: false)
    yield 1–2 frames for layout
    let subtree = parse(root: scrollView)        // scoped to scroll view only
    merged = merged.mergingSubtree(subtree, at: containerPath)
    if until(merged): break
restore saved contentOffset
yield 1–2 frames for layout
```

### Scoped re-parse

The initial parse walks the full tree — window, nav bar, tab bar, scroll views,
everything. But during the scan, only the scroll view's content changes between
steps. The nav bar, tab bar, and everything outside the scroll view is static.

So scan steps re-parse only the scroll view's subtree:
`parse(root: scrollView)`. The parser already takes a `root: UIView` — passing
the scroll view as root gives you just its children. The merge splices the subtree
into the full tree at the container's `TreePath`.

This makes scanning a 5000-element list cheap. Each step parses ~10 visible cells,
not the entire screen. A 70-step scan parses 700 nodes total instead of
70 × (10 cells + 30 other elements) = 2800 nodes. The cost scales with the scroll
view's visible window, not the screen's total element count.

For nested scroll views, the scoped parse uses the innermost scroll view as root.
The outer scroll view's content is already parsed from a prior step or the
baseline.

### No settle detection

`setContentOffset(_:animated: false)` is synchronous. The offset is at the new
value when the call returns. No animation, no momentum. The 1–2 frame yield is
for UIKit layout (cell reuse, `accessibilityElements` regeneration), not settle
detection. We own the scroll — there's nothing to wait for.

Settle detection is for when something else moved the viewport (user swipe,
animation, app-driven scroll). The scan primitive doesn't need it.

### Scan decision from inventory

After the initial full-tree parse, the inventory tells you the cost of scanning
each scroll view before you start. The decision is automatic:

| Inventory | Total | Decision |
|---|---|---|
| Available | ≤ limit (e.g., 300) | **Full scan.** Cost is known and acceptable. |
| Available | > limit | **Skip.** Report visible elements + `⋮ N more`. |
| Unavailable (`NSNotFound`) | — | **Heuristic.** Estimate from `contentSize / bounds`, scan up to limit. |

The limit is the existing `maxScrollsPerContainer` knob, translated to element
count: `limit = maxScrollsPerContainer × visibleCount`. The inventory lets you
make the skip/scan decision *before* starting instead of bailing mid-scan.

For containers that will be scanned, steps are computed from element count:

```swift
let visibleCount = inventory.visibleIndices.count  // e.g., 10
let stepsAbove = ceil(Double(aboveCount) / Double(visibleCount))
let stepsBelow = ceil(Double(belowCount) / Double(visibleCount))
```

Start from current position, scan forward, then backward:

```swift
let stepSize = visibleHeight * (1 - overlapFraction)
let forwardSteps  = stride(from: current.y, through: maxY, by: stepSize)
let backwardSteps = stride(from: current.y - stepSize, through: minY, by: -stepSize)
```

No leading edge reset. Minimizes total scroll distance.

### Merge strategy

`Screen.merging()` — last-write-wins by HeistId. Already exists. The latest parse
of an element replaces the earlier one. No fingerprints, no overlap detection, no
reconciliation.

### Nested scroll views

Process containers in tree order (depth-first). If the inner container's scroll
view isn't captured, scroll ancestors to reveal it using the same scan primitive.
Reuses existing `revealSemanticContainerForExploration` infrastructure. Restore
positions bottom-up.

### Safety limits

`maxScrollsPerContainer` and `maxScrollsPerDiscovery` — existing `ScreenManifest`
tracking. Step count is predictable from inventory, so the scan can skip
containers that would exceed limits before starting.

Current defaults allow 300 items per scroll container. In practice, this covers
every real list in the apps BH tests. The limits are guard rails, not normal
operating constraints.

### Cell materialization

`UITableView` / `UICollectionView` only instantiate cells that are visible.
`setContentOffset` before parsing ensures UIKit creates cells at the new offset.
The tree walker discovers them as normal subviews. Same mechanism BH already uses.

## Part 3: Interface Output Format

### Design principle

The agent doesn't know about scroll views. It sees lists with elements. Scroll
containers are presented as lists. BH handles the scrolling internally during the
scan — the agent never sees viewport mechanics.

### Full scan (normal case)

Limits are set high (300 per container). The scan completes. The agent gets
everything:

```
── list "main_list" 50 elements ──
  390×700 view, 390×4200 content (6 pages), vertical
  [1] "First Item" staticText
  [2] "Second Item" staticText
  ...
  [50] "Last Item" staticText
── /main_list ──
```

No omission markers. The agent sees the complete list and can target any element.
BH scrolls to off-screen targets internally before acting.

### Partial scan (limits hit)

When the scan hits limits (large lists, knobs turned down):

```
── list "main_list" 5000 elements, showing 300 ──
  390×700 view, 390×50000 content (70 pages), vertical
  [1] "First Item" staticText
  ...
  [300] "Three Hundredth Item" staticText
  ⋮ 4700 more
── /main_list ──
```

`⋮ 4700 more` is accurate — from `accessibilityElementCount`, not guessed from
content size. The agent knows the picture is incomplete and how much was skipped.

### Non-scrollable containers

```
── list "settings_section" ──
  [1] "Notifications" staticText | button
  [2] "Privacy" staticText | button
  [3] "About" staticText | button
── /settings_section ──
```

### Nested containers

```
── list "main_list" 50 elements ──
  390×700 view, 390×4200 content (6 pages), vertical
  [1] "Section Header" header
  ── list "carousel" 8 elements ──
    390×200 view, 1200×200 content (3 pages), horizontal
    [2] "Item A" image
    [3] "Item B" image
    ...
    [9] "Item H" image
  ── /carousel ──
  [10] "Another Row" staticText
  ...
  [50] "Last Item" staticText
── /main_list ──
```

### Containers with modal boundary

```
── group "Alert" modal ──
  [1] "Delete this item?" staticText
  [2] "Cancel" button
  [3] "Delete" button | .destructive
── /Alert ──
```

### Metadata line

Scrollable containers get one metadata line after the header:

```
390×700 view, 390×4200 content (6 pages), vertical
```

View size, content size, page count (human-readable cost estimate), axis. Natural
language, not key=value. Non-scrollable containers skip this line.

### Format rules

- `──` separator lines open and close every container
- Closing line echoes the container name: `── /name ──`
- Header: container type, name, element count
  - Full scan: `N elements`
  - Partial scan: `N elements, showing M`
- Scrollable containers get a metadata line with view/content/pages/axis
- `⋮ N more` only appears when limits prevented full scan
- Element indices reflect actual position in the container (1-based)
- Children indented 2 spaces
- Elements use the existing compact element line format
- Only visible elements rendered after a partial scan; all elements rendered
  after a full scan
- Container type in output is `list`, `group`, `table`, `tab_bar`, `landmark` —
  never `scrollable`. Scrollability is an attribute (the metadata line), not a
  container type

### Implementation

Format changes happen in `TheFence+Formatting+Compact+Interface.swift`:
- `compactContainerLine()` emits `──` header with name and count
- `compactTreeLines()` emits metadata line, elements, closing `── /name ──`
- `⋮ N more` emitted when `ScrollInventory.totalElementCount` exceeds
  discovered element count
- Container type mapped: `.scrollable` → `list` (or whatever the wrapped
  container type is)

## Implementation Location

All in BH (`TheInsideJob`):

### New files

- `TheInsideJob/TheBrains/Navigation+Scan.swift` — unified scan primitive, step
  computation from scroll inventory

### Modified files

- `TheInsideJob/TheBurglar/TheBurglar+ScreenBuilding.swift` — capture scroll
  inventory, remove content-space origin computation
- `TheInsideJob/TheStash/SemanticScreen.swift` — add `ScrollInventory` to
  `Container`, remove `ScrollContentLocation` from `Element` and `Container`
- `TheInsideJob/TheBrains/Navigation+Explore.swift` — `exploreScreen()` uses
  scan primitive instead of `scanPendingContainers()`
- `TheInsideJob/TheBrains/ElementInflation+SemanticReveal.swift` — delegates
  scrolling to scan primitive
- `TheFence+Formatting+Compact+Interface.swift` — container format with `──`
  separators, metadata line, closing `── /name ──`, `⋮` omission markers

### Dead code after migration

Page reconciliation:
- `PageOverlap.swift`
- `ContentOriginOrdering.swift` (check for other callers first)
- `SafeGeometryHashing.swift` (check for other callers first)
- `reconcileContainerPage*` in `Navigation+ExplorationScanning.swift`
- `moveToLeadingEdge()` in `Navigation+ExplorationScanning.swift`
- `scanForwardPages()` in `Navigation+ExplorationScanning.swift`
- `preparePageScan()` in `Navigation+ExplorationScanning.swift`
- `contentFingerprints()` and `reconcileVisiblePage()`
- `ContainerScan`, `ContainerPage`, `ContainerPageEntry`,
  `ContainerPageReconciliation` types
- Swipeable exploration fallback path

Content-space origin:
- `contentSpaceOrigin` on `SemanticScreen.Element`
- `ScrollContentLocation` on `SemanticScreen.Element` and
  `SemanticScreen.Container`
- `screenCoordinateOffsetsByPath` in `TheBurglar.ParseResult`
- Content-space origin computation in `TheBurglar+ScreenBuilding.swift`
- `containerScrollContentLocationsByPath` in `LiveCapture`
- `SemanticReveal` scroll offset computation (activation point placement stays)

### Parked PRs

- **PR #344** (container index API fallback in the parser) — parked. This spec
  moves index API usage to BH's screen building layer. The parser stays a pure
  tree walker.

### Preserved infrastructure

- `AccessibilityHierarchyParser` — unchanged, pure single-frame tree walker
- `TheBurglar.parse()` — unchanged, calls parser and builds Screen
- `Screen.merging()` — the merge primitive, unchanged
- `SemanticExploration.absorb()` — unchanged
- `ScreenManifest` — scroll counting and limits
- Viewport restoration (`restoreVisualOrigin`)
- `ElementInflation` — live target resolution and activation point placement
- `ScrollableTarget` resolution for user-initiated scroll commands
- `scrollOnePageAndSettle()` for user-initiated `scroll` commands

## Decisions Made

- **No settle detection in the scan primitive.** We own the scroll —
  `setContentOffset(_:animated: false)` is synchronous. Yield 1–2 frames for
  layout only.

- **Eliminate `contentSpaceOrigin`.** Scroll inventory replaces it. The scan steps
  through viewport-sized batches based on element count, not per-element
  coordinates.

- **PR #344 parked.** Index API usage moves to BH's screen building layer.

- **Full scan is the default.** Limits are set high (300 per container). The scan
  completes for every real-world list. Omission markers are a safety valve, not
  the normal case.

- **Scroll views are invisible to the agent.** Presented as lists. BH handles
  scrolling internally. The agent targets elements by label/index, BH scrolls to
  make them actionable.

- **Container type is semantic, not mechanical.** Output says `list`, not
  `scrollable`. Scrollability is shown in the metadata line, not the type.

## Open Questions

1. **`contentFingerprints` and `findOverlap` callers.** Check whether settle
   detection or scroll proof use these before removing.

2. **SwiftUI element count.** `UpdateCoalescingCollectionView` returns
   `NSNotFound`. Is there another way to get the count for SwiftUI lists?

3. **Index contiguity.** Store raw `visibleIndices: [Int]` rather than
   `Range<Int>` to handle collection views with non-linear layouts.

4. **2D scroll views.** Does BH encounter 2D scrollable containers? If rare,
   defer and scan dominant axis only.

5. **Container format migration.** The `──` separator style is a visual change
   for all containers. Existing tests and agent prompts that parse the interface
   output will need updating. Consider shipping the format change separately
   from the scroll inventory to isolate regressions.

6. **Container type mapping.** When a `UITableView` has
   `accessibilityContainerType = .list`, the output type is `list`. When it's
   `.none` (the default for UITableView), what should the output type be? `list`
   by inference (it's a table view), or `group`? The semantic type should come
   from the accessibility container type, not the UIKit class.
