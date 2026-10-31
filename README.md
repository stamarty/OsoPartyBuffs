# Oso Party Buffs

A World of Warcraft Classic addon that shows buffs on your party frames, so you can see at a glance
whether a party member already has a buff, such as Rejuvenation, from any caster.

## Features

- Buff icons on each party member's frame, from **any source**, with a cooldown swipe and time remaining.
- **Allow list**: these buffs always show first, in list order, so a buff like Rejuvenation always sits in the same spot.
  An optional mode shows *only* allow-list buffs.
- **Deny list**: these buffs are never shown.
- List entries match a buff **name**, which covers every rank, or a specific **spell ID**.
- Adjustable icon size, icons per row, max icons, spacing, position (right of or below the frame) and X/Y offset.
- Optional green border on buffs *you* cast.
- Works with the default party frames and with raid-style party frames.
- Optional icons on your own player frame, handy for testing while solo.
- Option to hide Blizzard's buff pop-up that appears when hovering a party frame.
- All settings, including both lists, are saved **per character**.

## Install

Copy (or symlink) this folder into your AddOns directory so the path looks like:

```
World of Warcraft\_classic_era_\Interface\AddOns\OsoPartyBuffs\OsoPartyBuffs.toc
```

For other Classic flavors use `_classic_` instead of `_classic_era_`.

When working from this repo, `deploy.ps1` copies the addon files there for you. Pass `-AddOnsPath` if
your WoW install is somewhere else:

```
powershell -NoProfile -ExecutionPolicy Bypass -File .\deploy.ps1 -AddOnsPath "C:\...\_classic_era_\Interface\AddOns"
```

If the addon shows as "out of date", either tick **Load out of date AddOns** on the character-select AddOns screen, or
update `## Interface:` in `OsoPartyBuffs.toc` to the number printed by:

```
/dump select(4, GetBuildInfo())
```

## Usage

Open the options with `/opb`, or from the game's Options > AddOns panel.

| Command | Effect |
| --- | --- |
| `/opb` | Open options |
| `/opb allow <name or ID>` | Add to the allow list |
| `/opb deny <name or ID>` | Add to the deny list |
| `/opb remove <name or ID>` | Remove from both lists |
| `/opb list` | Print both lists |
| `/opb reset` | Restore defaults |
