# App audit, Claude's side (phase 1 of the revamp)

Written 2026-10-24 from reading the code (`Hub.swift`, `StreamManager.swift`, `Helper.swift`). Not yet seen on screen, so heights are estimates.
One line per problem, one-line fix. GPT's list goes next to this one; Claude merges both into the priority order.

## Every page (the shell)

- Two refreshes on most pages: the top bar's Refresh (Command-R, refreshes everything) and each page's own Refresh button. Keep the top bar one; make the page ones small icons.
- The round "M" in the top bar is decoration and does nothing. Remove it or make it open Accounts.
- Loading, offline and empty states are copy-pasted on every page (`hubOffline`, `ProgressView`). One shared state view.
- Every page is a ScrollView of full-width cards. The Meeting Room fix (tabs, categories, short lines) is the model.

## Page by page (worst first)

| Page | Problem | Fix |
|---|---|---|
| Stream | About 12 cards stacked in one scroll: header, OBS, Video lab, status, editor, chat helper, actions, checklist, clips, past streams, autopilot, voice-over. The worst "scroll city" left. | Tabs: **Go live** (status, title, checklist, actions), **Clips** (clips, past streams, autopilot), **Tools** (OBS, Video lab, voice-over, chat helper). |
| Accounts | 11 rows at about 80 px each. Five are read-only rows that need no action. | Put the ones that need action first (Not connected), and fold the read-only ones into one collapsed "Nothing to set up (5)" group. |
| Launchpad | Agent cards at 210 px minimum height plus several groups of link tiles. | Tabs per link group; agents become a slim strip, like the Meeting Room crew. |
| Systems | One row per automation (12 or more) under two cards. | Failing and running first; collapse the ones that are fine to "All 11 ran fine" with Show all. |
| Home | Opens on a tall "Friday is ready" hero (a Talk to Friday button, which the rail already has), then a glance list of up to nine bullets, then seven tiles. About 2.5 screens, and what needs Matthew is not on it. | Lead with a compact **Needs you** card (reuse `MeetingData.needs`, plus failed automations); slim the hero to one row; cap the glance list at four with Show more. |
| Store | Sales block, three stat tiles, a channel bar chart, the catalog card and a long footer paragraph. About 2 screens. | Tabs **Sales / Visitors / Catalog**; the footer paragraph becomes a help line. |
| ECS | Three stats, an "honest wording" card, and the feed cards in one HStack that squeezes in a narrow window. | Feed cards in a horizontal scroll or a 2-column grid. |
| Stock bot | Picker has only Dip and Momentum; the bot also runs **Hot hands** (since 2026-10-08), so the page is missing a robot. Latest activity list is uncapped. | Add the third robot (needs the snapshot reader to know it); cap activity at 5 with Show all. |
| Game | Overlaps Friday (what she sees) and Stream (clips). | Fold "what she sees" into the Friday page and the clip card into Stream; retire or rename the page. |
| Helper | Two cards, one ScrollView; not read in detail yet. | Check at compact size. |
| Friday | The orb stage fits one screen. Settings is a separate panel. | Leave; check at 440 x 400. |
| Meeting Room | Done on 2026-10-24 (six tabs). | Header Refresh duplicates the top bar's. |

## Navigation

- The rail is a flat, draggable list of 12 icons. Keep the dragging, add thin dividers by group: Home | Friday, Stream, Helper | Stock bot, Store, ECS, Systems, Launchpad | Game, Accounts, Meeting Room.

## Where the code is

- `Hub.swift` holds Home, Stock bot, Store, ECS, Systems, Launchpad, Game and Accounts in one 1,348-line file, which is why two people cannot work on pages at once. Phase 0 splits it by page with no change in behaviour.
