# GoldGoal

A World of Warcraft (retail, Midnight 12.1) addon that treats a big gold
target, the 5,000,000g Sporebearer Fungal Strider, say, like a savings
plan: set the tiers (at least the mount, then its vendors, then a buffer)
and a deadline, and it pools every character's gold with the
Warband Bank, works out how much you need per day and per week, shows
today's progress on a small bar, and projects the date you will get there
at your current pace.

Where other gold addons tell you what you have, this one tells you how
much you need today.

## What it does

- **Warband-wide wealth.** Every character you log in is recorded, along
  with the Warband Bank's gold (read whenever the game allows, at the
  latest when you open a bank). With Syndicator (Baganator's tracking)
  loaded, characters you have not logged in since installing are filled
  in from what it remembers, until they log in and report live. With
  CraftSimPL, your crafting stock counts at cost too (see below).
- **A daily quota that adjusts itself.** What is left to save, divided by
  the days left to the deadline. Today's quota is fixed when the day
  starts so the bar holds still while you fill it; the sum is done again
  every day on what is left, so a big farm day lowers tomorrow's quota and
  an idle week raises it. The Goal page shows both: today's quota and what
  tomorrow's will be at this pace.
- **A weekly quota** for people who play on reset night or at the
  weekend: the daily quota times the days of the week that are left.
- **The bar.** A slim on-screen bar, `Today  +8,450g / 14,000g  60%`,
  that follows the daily quest reset. Click it to open the window,
  right-click to switch it to the week, drag it anywhere (lock it in
  Settings; Shift-drag still moves it). Hovering shows the whole picture.
  The tiers sit on it too: a mark where each still needs the day (or the
  week) to be, and the same colours as the goal bar, red to green up to
  what the mount needs, blue into the accent past it; once the mount is
  banked its mark is gone and the bar starts in the blues.
  Past 100% it keeps counting: 105%, 240%, with a brighter lap running
  over the full bar and a mark at its end; Settings can make it show the
  week instead once today is met. Either way tomorrow's quota comes down
  by what you went over.
  It hides in combat by default, and its instance rule (*Smart*) hides it
  where it cannot be used: Mythic+ runs, raids while in combat (between
  pulls it stays, the AH mount is a click away), battlegrounds and arenas.
  Normal and heroic dungeons, old content, delves and world quests keep it,
  grouped or not. Settings also has *Grouped* (any instance while in a
  group), *Show* and *Hide*.
- **The gold splash.** A combat-text style pop in the middle of the screen
  whenever the total grows by more than a threshold (500g by default):
  `+12,345g` with a coin, white for the small ones and gold from level 2,
  bigger and louder the more it is.
  Up to ten levels, edited as rows like the goals: each has the gold it
  starts at, what it says, its text size, how long it holds, its sound
  (none, coin, epic or legendary toast), its colour, whether it glows,
  and which frame it lights around the screen: liquid gold flowing
  clockwise along the edges while the splash is up, as *Ripple* (thin,
  slow, quiet), *Liquid gold* (the full flow) or *Torrent* (wide, bright
  and fast, with a second finer current running the other way), or none.
  The frames only brighten, never darken. Shipped, seven levels: 500g,
  1k, 5k, 10k, 25k "Nice!" with the ripple, 50k "Jackpot!" with liquid
  gold, 100k "Legendary!" with the torrent; all gold, the coin clink up to
  5k and the epic toast from 10k, the glow from 5k. Add a level and it
  starts at twice the top one, a step bigger.
  Big spends can show too, in red, and the splash can follow the bar's
  hide rules. Gains that arrive
  within the merge window (2 seconds) are one event, and while the mailbox
  is open nothing shows until it closes, so a run through fifty sale mails
  is one big number. The amount is the net change in what the addon
  counts, so with CraftSimPL a sale shows its profit and a reagent buy
  shows nothing. A line under the amount says what it moved: "+23% of
  today's quota (81%)" for everyday amounts, "+1.2% of Goal (64.3%)" once
  it is a real share of the tier. Percent marks of the goal get a note of
  their own ("64%  of Goal"), even when a copper crossed one, as often as
  you like (every 1, 2, 5, 10, 20 or 25 percent) with a bigger one every
  10, 20, 25, 50 or 100; meeting the day's quota or banking a goal gets the
  top splash, each switchable. The mailbox hold can be turned off to see
  gains as they merge. Preview the levels in Settings or with `/gg splash 2m`.
- **A data bar text.** GoldGoal is a LibDataBroker source. EllesmereUI's
  data bars show it as a *Broker Plugin* block; any broker display works.
  It shows today's, the week's, or the total progress; right-click cycles.
- **Pace and projection.** 7-day and 30-day moving averages of your net
  earnings and the average since the goal started, with the date each
  pace reaches the target and a plain verdict: on pace (and by how many
  days), behind (and what you need per day against what you do), reached.
- **History.** Every day (or week) since the goal started against its
  quota, with a mark on the ones you met.

## How earnings are counted

The total is the sum of every counted character's gold plus the Warband
Bank. Earnings are changes in that total, with one rule that keeps them
honest: **only gold that changes while you play counts.** A character seen
for the first time, a figure taken from Syndicator, a character you untick
or forget, and the first reading of the Warband Bank all move the total
but shift the day's and the week's starting point by the same amount, so
they never show up as income. Moving gold between a character and the
Warband Bank nets to nothing, since both sides are in the total.

A day runs from one daily reset to the next; a week from one weekly reset
to the next, using the game's own reset times. Days you do not log in
earned nothing, which is what the averages should say.

Gold you spend counts against the day (it shows in red). Buying the mount
itself will look like a very bad day: use *Start a new goal* in Settings
when you set the next target.

## Crafting stock (CraftSimPL)

If you make your gold by crafting, liquid gold alone tells the wrong story: a
big reagent buy looks like a loss and the sales come back as windfalls. With
CraftSimPL loaded (and its working-capital API, `CraftSimPL.API:GetWorkingCapital`,
see `docs/specs/2026-09-05-goldgoal-working-capital-api.md` in that repo),
GoldGoal counts your crafting position **at cost** as part of your wealth:
reagents bought and not yet crafted, at their weighted-average cost, and unsold
crafts at their batch unit cost. Buying reagents then moves gold into stock
(no change), and a sale drops stock by its cost while gold rises by the net
price, so the day's earnings are the profit. A lost deposit or a write-off in
CraftSimPL lands as a loss on the day it happens.

- One row per connected realm on the Characters tab, with the breakdown in
  its tooltip; the Goal page's target bar gets a dimmed segment for the
  stock, since the mount is paid in gold, and the status line says how much
  stock still has to sell once the target is reached at cost.
- CraftSimPL's projections (listed, awaiting gold, unlisted at the last
  posted price) are shown as "~X if it sells" and never counted.
- The first reading for a realm and a CraftSimPL data reset shift the day's
  starting point instead of counting as earnings, like a new character.
- Settings > *Count crafting stock at cost* turns it off; the figure then
  shows for information only.

## Setting the goal

The goal editor sits on the Goal page of the EllesmereUI panel and in the
window's Settings tab, and reads top to bottom:

- **Goals**: a row per goal with its name and its gold, cheapest first
  (they sort themselves). Edit a box and press Enter, *+ Add a goal* for
  another (up to four), the minus takes one away. The *Mount*, *+ Vendors*
  and *Ladder* presets fill in 5,000,000g, then 7,000,000g for the vendors,
  then a 10,000,000g buffer so there is gold left after buying. Each row
  says where it stands: *banked*, *quota aims here*, and *must be met* on
  the cheapest, the one that goes away. Also `/gg target mount|set|ladder`
  and `/gg tiers 5m Mount, 7m Mount + vendors, 10m Buffer`.
- **The daily quota aims at** one goal, the first by default. Once a goal
  is banked the quota moves up to the next one by itself; pick a higher
  one here (or click it on the dashboard, or `/gg tier <n>`) to aim there
  sooner. The dashboard shows every goal with what it still needs per day
  and the date the 7-day pace reaches it. The bar runs to the aimed goal
  (100%) with a mark at every goal below it, and its colour says how safe
  the mount is: red through yellow to green on the way to the cheapest
  goal, then blue into your EllesmereUI accent from there to the end.
- **Deadline**: *End of Midnight* (the default: the mount is sold until
  then), *End of Season 2*, *A date* or *Days from now*; the box for a
  typed date (`YYYY-MM-DD`) or a day count appears only for those two, and
  a line under it says the date and the days left. The two named ones are
  guesses (`EXPANSION_END_GUESS` and `SEASON_END_GUESS` in `Goal.lua`) that
  a deadline set from them follows when they are updated; pick a date once
  either is announced. Also `/gg deadline 2027-08-01`, `/gg deadline 45d`,
  `/gg deadline season`, `/gg deadline expansion`.
- The deadline is the end of the game day that falls on that date, so
  "Aug 1" gives you all of Aug 1 up to the next daily reset.

### How long you have (as of September 2026)

The Sporebearer Fungal Strider arrives in patch 12.1.5 for 5,000,000g
(mailbox and repair vendor included) with another 2,000,000g of optional
vendors, and is sold **until the end of the Midnight expansion**; the
vendor add-ons stay purchasable afterwards. So the deadline is The Last
Titan's pre-patch, not the end of Season 2.

What is known: Midnight launched March 2, 2026; Season 1 ran March 17 to
August 11; patches have landed every eight weeks (12.0.5 April 21, 12.0.7
June 16, 12.1 August 11), so 12.1.5 is due around early October, 12.1.7
around December, and 12.2 with Season 3 around late January 2027. The Last
Titan has no date; Blizzard has said 2027 at the earliest, and one January
2026 developer remark called it "several years away".

The estimate: The War Within to Midnight was 18 months, the fastest gap
yet. If Midnight matches it, The Last Titan launches around September 2027
and its pre-patch, the mount's last day, lands around **August 2027**,
which is the shipped guess. A third season starting in late January would
then run about six months, like The War Within's did. If the gap stretches
to 21 months (Dragonflight to The War Within), the pre-patch is around
November 2027; if the "several years" remark holds, 2028 and a fourth
season. Plan for August 2027 and treat anything later as slack. BlizzCon
(September 12 and 13, 2026) is the first place a firmer window is likely.

## The window

`/gg` opens it. Three tabs hang under it, Settings is the cog in the title
bar; drag the title bar to move it, Escape closes it.

- **Goal**: the paced tier with the ladder bar (a mark per tier, a dimmed
  segment for crafting stock), a row per tier with its per-day need and
  projected date, today and this week against their quotas with the reset
  countdowns, and the pace grid.
- **Characters**: the Warband Bank and every character, richest first
  (click a column to sort). Untick a character to leave it out of the
  total (a bank alt whose gold is spoken for, say); right-click one to
  forget it. Characters filled in from Syndicator say so until they log in.
- **History**: days or weeks against their quotas, today at the top, and
  how many quotas you met.
- **Settings**: target tiers and the paced tier, deadline, the bar (show, lock, hide in combat, today or week,
  scale, width, reset position), the gold splash (on, sound, threshold, merge window, scale,
  height, previews), the data bar text, window scale, *Start
  a new goal* (clears the history; target, deadline and characters stay),
  *Forget all characters*, *Re-read Syndicator*.

## Look and feel

Built to match EllesmereUI. When it is installed, GoldGoal registers with
its public skinning API (`EllesmereUI.RegisterSkin`) and EllesmereUI paints
the window and the bar itself: window style, accent colour, font and
control look follow the user's settings, live. Users can turn this off per
addon under *Blizz UI Enhanced > Blizzard Window Skins > Third-Party
Addons*. Without EllesmereUI, or with that toggle off, `Style.lua` paints
the same flat look with fixed colours.

## In EllesmereUI's options panel

With EllesmereUI loaded, GoldGoal lives in EllesmereUI's own options
panel, under a **Sagerobot's Addons** group at the bottom of the sidebar,
and `/gg` (and the bar, and the broker text) opens it there. Six pages:

- **Goal**: the dashboard from the window (the ladder bar, the goals, today
  and this week, the pace), then the goal editor (goals, what the quota
  aims at, the deadline).
- **Characters**: the window's list, with the sources under it: the
  crafting toggle, *Re-read Syndicator* and *Forget all characters* (asks
  first).
- **History**: the window's list, with *Start a new goal* (asks first) and
  its undo, since that is what it clears.
- **Bar**: the show rules and the look (height, font size, width, scale,
  opacity, label, percent, goal colours), *Show me the bar* (brings it up
  for a few seconds whatever the rules say) and the data bar text.
- **Splash**: what shows, the level editor (every level's gold, saying,
  size, hold, sound, colour, glow and frame), the celebrations and percent
  marks, timing and place, a preview per level.
- **Colours**: the four colour stops of the goal bars (the end of the run
  is always the EllesmereUI accent), and the window's scale.

The window is the fallback and keeps everything: `/gg window` opens it,
and it opens by itself when EllesmereUI is not loaded or does not take the
page. EllesmereUI keeps its module registration for its own folders (it
reads the caller's folder off the stack), so GoldGoal registers through
`pcall`, whose C frame carries no folder. That is a gap in a guard rather
than a supported API: if an EllesmereUI update closes it, `/gg` notices
the page never built and uses the window for the session.

## Commands

```
/gg                    open GoldGoal (in EllesmereUI's panel when it is there)
/gg window             the GoldGoal window itself
/gg bar                show or hide the bar
/gg lock               lock or unlock the bar
/gg splash [gold]      preview the gold splash (at that amount)
/gg target <n|mount|set|ladder>   one amount, or a preset ladder of tiers
/gg tiers 5m Mount, 7m Mount + vendors, 10m Buffer   your own tiers (up to four)
/gg tier <n>           pace towards tier n
/gg deadline <YYYY-MM-DD | <n>d | season | expansion>
/gg options            open settings
/gg eui                open the GoldGoal page in EllesmereUI's options
/gg status             print what the addon knows
/gg reset goal|chars|all
/gg debug              toggle debug output
```

## Install

Run `install.ps1` to create a junction from the WoW AddOns folder to
`GoldGoal/` in this repo, or copy the `GoldGoal` folder into
`World of Warcraft\_retail_\Interface\AddOns\`. After editing files, `/reload`.

## Tests

`tests/harness.lua` stubs the WoW API, with a fake clock whose daily and
weekly resets can be rolled forward, and runs the real addon files under
Lua 5.1 (the game's Lua version):

```
lua tests/harness.lua
```

## Files

| File | Purpose |
| --- | --- |
| `Core.lua` | Namespace, saved variables, events, shared helpers, slash commands, `/gg status` |
| `Style.lua` | Widget painting: EllesmereUI skin registration with a flat fallback |
| `Money.lua` | Gold formatting and parsing; reading this character's gold, the Warband Bank and Syndicator |
| `Ledger.lua` | The character pool, day and week ids, the earnings rule, history and averages |
| `Crafting.lua` | The crafting position at cost from CraftSimPL's working-capital API, per realm |
| `Goal.lua` | Target, deadline, quotas, projection, status text and the pace tooltip |
| `Widgets.lua` | Buttons, tabs, the dropdown, column headers, list panels, progress bars, stat cells, pooled rows |
| `GoalEditor.lua` | The goal editor: goal rows, presets, what the quota aims at, the deadline |
| `Bar.lua` | The on-screen bar |
| `Splash.lua` | The gold splash: merged gains, levels, animation, sound |
| `Broker.lua` | The LibDataBroker data object |
| `Tabs.lua` | The Goal, Characters and History tabs |
| `Settings.lua` | The Settings page and the Settings > AddOns entry |
| `Window.lua` | The window shell, title bar, tab row, page switching, position |
| `EUIOptions.lua` | The page in EllesmereUI's options panel |
| `Libs/` | LibStub, CallbackHandler-1.0, LibDataBroker-1.1 |
| `media/coin.png`, `coin64.png` | The coin: rendered at 1024 pixels and downsampled, so it stays sharp at any splash size; the 64 is the addon's icon and the broker's |
| `media/liquid.png` | The liquid-gold frame's tile: 256 wide along the edge (seamless), 64 from the edge inwards (fading) |

Saved variables live in `GoldGoalDB` (account-wide): the tiers and the
paced one, the deadline, the characters, the Warband Bank figure, the day and week records (90 days and
26 weeks are kept), and the bar and window settings.
