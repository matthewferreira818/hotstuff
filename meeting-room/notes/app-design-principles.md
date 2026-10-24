# Design principles for the revamp

Research by Claude, 2026-10-24, because Matthew asked (via GPT) to draw inspiration from well-designed sites: principles, not copying.
Nothing here uses any other product's pictures, logos or layouts. Public repo: nothing private.

## What we took, and from where

| Principle | Source | What we do with it |
|---|---|---|
| **Visual weight follows the task.** Navigation recedes so the work area stands out; the sidebar was dimmed so content wins. | [Linear, behind the latest design refresh](https://linear.app/blog/behind-the-latest-design-refresh) | The rail is quieter than the page. Selected state is clear but calm; content is the brightest thing on screen. |
| **Reduce noise, keep density.** Fewer borders and colours, higher information density without feeling overwhelming. | Same | Categories use a small coloured dot and a title, not coloured fills. One border weight everywhere. |
| **Actions in predictable places.** Linear fixed header actions that had stopped appearing in the same spot. | Same | One shared page header: title on the left, actions on the right in the same order (Refresh, then the page's own action). |
| **Sidebar: at most two levels, short group titles, never hidden by default, accent-coloured icons.** | [Apple Human Interface Guidelines, Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars) (summary of the guidance) | A labelled sidebar in groups of pages (below). Icon-only only in the compact window. |
| **Dark mode: a dedicated palette, layered surfaces instead of shadows, off-white rather than pure white on pure black, 4.5:1 for body text and 3:1 for large text and controls, and user control.** | [Dark mode best practices](https://www.onething.design/post/best-practices-for-dark-mode-ui-design) and WCAG (secondary sources; check numbers against the WCAG text) | Midnight is the default because it uses off-white text (#F2F2F5) on near-black. Pure black, with white outlines, is the High contrast switch for people who want the strongest contrast. Every text colour is measured against its background. |
| **Time cues in a conversation: date separators between days; "From" filter chips.** | [Stream Chat, DateSeparator](https://getstream.io/chat/docs/sdk/react/v13/components/utility-components/date-separator/), [Google Chat search chips](https://workspaceupdates.googleblog.com/2022/12/google-chat-search-chips.html) | The Thread tab groups by day and has chips for All, Claude, GPT, Friday and Matthew. |

Gap: the search found nothing usable on command palettes or progressive disclosure, so the "Jump to..." box below is Claude's own proposal, kept simple.

## Proposed sidebar (two levels: group, then page)

```
Friday            (the round logo; click = Home)
Jump to...  ⌘K    (type a page name, Enter)
Home
CREW
  Friday
  Helper
  Meeting Room
BUSINESS
  Stock bot
  Store
  ECS
  Systems
STREAM
  Stream
  Game
SETUP
  Launchpad
  Accounts
```

- Labels beside the icons at the normal size; icons only (with tooltips) in the compact window.
- Groups can be collapsed and the choice is remembered. Dragging to reorder pages stays, inside a group.
- A new page is one line in the page list (name, icon, group, view); a new group is one more heading.
- Every page also reachable with Command-1 to Command-9 and by Jump to...; focus ring visible.

## Meeting Room, by time and sender

- **You** stays first: what needs Matthew.
- **Thread**: day groups (Today, Yesterday, This week, Earlier) with a sticky day label; chips All, Claude, GPT, Friday, Matthew; a count of new messages since he last opened it; the board meeting card on top.
- **Board**: unchanged (one screen at a time, categories, short lines).
- Each message keeps the author, who it was for and how long ago; tap to open.

## Order of work

1. Theme file and page list (Claude).
2. Sidebar and shared page header (Claude).
3. Thread by day and sender (Claude, Meeting Room files).
4. Pages in batches (GPT and Claude, see app-revamp-plan.md).
