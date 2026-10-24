# App revamp plan (Friday, the Mac app)

Written 2026-10-24 by Claude. Public repo: nothing private belongs here.

## What Matthew decided (2026-10-24)

Scope, in his words: "revamp entirely" and "give your best effort to outschool" the competition. So this is a full redesign of every page, the
navigation and the shared pieces, not a re-colour. We beat anyone with a better product and true claims, never by running anyone down in
public (rule 1). Who he means is an open question on the board.

"Give the entire app a revamp", Claude and GPT together, and **GPT may make changes as long as Claude confirms them.** He had just
called the Meeting Room "scroll city"; the fix there (one screen at a time, tabs, categories, short lines that open on a tap) is the
model for the rest of the app.

## Design direction (Matthew, 2026-10-24)

"A little darker with a black accent, easily accessible everything, and room ready for expansion. It's time we put an effort into
our business, why not make it fun and do it with my friends."

- **Darker, black accent.** Deeper background, black buttons and selected states with a visible outline, one small warm colour kept
  for attention only. Claude's call (2026-10-24, reversible; Matthew said "revamp entirely", not a pick-a-colour job): **Midnight is the default theme and Pure black is a
  High contrast switch in Settings.** The look is one theme file, so changing it later is cheap.
- **Easily accessible everything:**
  - Text at least 4.5:1 against its background (the three looks measure 7.5 to 19.8:1); small grey text at least 7:1.
  - Click targets at least 44 pt (buttons 48 pt); icon-only buttons get an accessibility label and a tooltip.
  - Never colour alone: every status has a word or an icon as well.
  - Every page reachable by keyboard (Command-1 to Command-9 plus a way to reach the rest) with a visible focus ring.
  - Reduce Motion respected; a Text size setting (small, medium, large) that scales the type everywhere.
  - Anything he uses most is one click from Home; nothing important is hidden behind a scroll or a long press.
- **Room for expansion:** a new page is one file plus one line in a page list (name, icon, group, view), not edits across five files.
  The rail is grouped and can grow (a "More" place for the rest). Colours, spacing and type sizes live in one theme file
  (`HubTheme.swift`) so a re-colour is a one-file change. A **Team** place is left open for later.
- **Fun, with his friends.** Read first as the crew: Claude, GPT and Friday. Ideas that cost nothing: a face for each of us on our
  tab, a small celebration when something real happens (first client, first sale, a streak milestone), the board meeting you can
  hear. If he also means real people joining (sharing the app, roles, what they may see), that is a bigger step with privacy and
  key-handling questions: this repo is public and every key stays on his Mac. Nothing is shared with anyone until he says so.

## The working agreement

1. **GPT may change app files** (anything in `tools/game_companion/`) **on its own branch.** One branch per page or batch, named
   `gpt/revamp-<page>`.
2. **Nothing reaches `master` until Claude has confirmed it.** The Mac app rebuilds from `master`, so merging is the confirmation.
   Claude reads the diff, runs the data checks, runs the checklist below, and merges (or says what to fix, in the thread).
3. **GPT compiles on Matthew's Mac before asking.** Say exactly what ran and what it printed (errors and warning counts). Claude cannot
   compile the screens here; the Mac is the only real compiler.
4. **One owner per file.** Two AIs never edit the same file at once. The owner map below says who has what; ask before touching a
   file that isn't yours.
5. **Say it on the board.** One short line per change set (point in the first 140 characters), tagged `[GPT]`, with the branch name.
6. **Matthew rebuilds** with Update Friday.command and sends a screenshot when something looks off. His eyes are the last check.

## Not part of this permission (these stay as they are)

- Honesty (rule 1): every word of new text on screen must be true today. No invented numbers or claims.
- Secrets (rule 2): no keys, tokens or passwords in code, notes or logs. Key handling stays in Keychain.swift / SecretFile.swift.
- Friday's hands: the off-limits list, the Allow box and the spoken check do not get loosened. Changes there go to Matthew.
- Real money: nothing wires the app to Moomoo or any broker. Practice money only.
- Money mode: no paid services, subscriptions or new paid keys. No new network address without a board line saying what it is for.
- Matthew's saved data (settings, the Friday feed, Keychain items, app ID, file names) must keep working after an update.

## Design rules (from the Meeting Room trim)

- **One screen at a time.** If a page scrolls more than about one and a half screens when it opens, it needs tabs or a Show all.
- **Categories, not piles.** Group by what it is (In progress, Waiting, Done...), with a small coloured title and a count.
- **Short lines that open on a tap.** About 140 characters shown, the rest on a tap.
- **What needs Matthew comes first.** Home leads with it.
- **Same look everywhere.** The noir glass cards, crimson accent, rounded type; shared pieces live in one place (phase 2).
- **Compact window works.** The app can shrink to 440 x 400; check it there.
- **Honest labels.** Say what a button does. Never imply a live call, a human, or a result that has not happened.

## Phases

0. **Prep (Claude).** Ship the voice and board-meeting work. Split `Hub.swift` (1,348 lines, the home of most pages) into one file
   per page with no change in behaviour, so pages can have single owners. Add the new files to `rebuild.sh`. GPT compile-checks.
1. **Audit (GPT and Claude, read-only).** For each page: what is cluttered, too long, inconsistent or broken, with a one-line fix.
   Post it in the thread or in `meeting-room/notes/`. Claude merges the two lists into a priority order and confirms the plan.
2. **Design kit (Claude).** The theme file (`HubTheme.swift`: colours, spacing, type sizes, the Text size setting), the page list
   (name, icon, group, view in one place), and one small file of shared pieces (page header, category card with count,
   tap-to-open line, stat tile, tab bar), written down in `meeting-room/notes/`.
3. **Pages in batches.** Each batch is one branch, one owner, a few pages. Each page ends as tabs or categories with short lines.
4. **Home and navigation.** Home leads with what needs Matthew; the rail gets grouped (for example Business, Stream, Friday).
5. **Polish.** Compact window, Reduce Motion, keyboard shortcuts, empty and offline states.
6. **Fun.** The crew's faces, small celebrations for real events, sounds that can be switched off. After the basics land.

## Pages and proposed owners

The app has 12 pages: Home, Friday, Stock bot, Store, ECS, Systems, Launchpad, Game, Accounts, Meeting Room, Stream, Helper.
Proposed (GPT can counter-propose in the thread):

| Owner | Pages and files |
|---|---|
| Claude | Meeting Room (done), Home, Friday and everything that touches her hands, voice or Live (`Live.swift`, `FridayHands.swift`, `Companion*.swift`), the shared kit, `rebuild.sh` |
| GPT | Stock bot, Store, ECS, Systems, Launchpad, Game, Accounts (the page views, after the Hub.swift split) |
| Either, one at a time | Stream, Helper (ask on the board first) |

Until the split lands (phase 0), nobody edits `Hub.swift`.

## Claude's confirm checklist

- [ ] Builds on Matthew's Mac (GPT's report names the command and result), or Matthew's own rebuild succeeded.
- [ ] `checks/DataChecks.swift` still prints "All data checks passed." (Claude runs it here).
- [ ] No new secret handling, network address or paid thing; no change to Friday's hands rules or the Allow box.
- [ ] Every new word on screen is true today (rule 1).
- [ ] Opens within about one and a half screens; works at 440 x 400.
- [ ] Only the owner's files changed; any new `.swift` file is in `rebuild.sh` and `make_gpt_bundle.py`.
- [ ] One board line says what changed.
- [ ] Saved settings and data still load.
- [ ] Accessibility: contrast, 44 pt targets, labels on icon-only buttons, status never by colour alone, keyboard reachable.

## Cost

Big multi-agent runs burn Matthew's usage (two review workflows hit his monthly limit on 2026-10-14). Keep reviews small: no more
than about 10 agents or a million tokens without asking him first.
