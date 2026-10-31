# Oso Party Buffs

WoW Classic (Era) addon that shows party members' buffs, from any source, on their party frames.

- `Core.lua`: buff scanning, allow/deny filtering, icon layout, events, `/opb` slash commands
- `Options.lua`: settings panel (Settings canvas, falls back to the old Interface Options)
- `OsoPartyBuffs.toc`: addon manifest. Any new `.lua`/`.xml` file must be listed here

## Saved settings

Settings are saved per character in `OsoPartyBuffsDB` (`## SavedVariablesPerCharacter` in the `.toc`).
Never rename that variable, the addon folder or the `.toc`: players would lose their settings.
New options only need a default in `ns.DEFAULTS`; changing what an existing setting means needs a migration.

## Workflow

After changing any addon file, deploy it to the game:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\deploy.ps1
```

This replaces `D:\ProgramFiles\World of Warcraft\_classic_era_\Interface\AddOns\OsoPartyBuffs` with a fresh copy
of the `.toc` and the files it lists. Don't link the repo into AddOns; the game didn't load it through a link.
After deploying, `/reload` in game, or restart WoW if the `.toc` changed or files were added.

Commit to `main` and push to `origin` (github.com/stamarty/OsoPartyBuffs) when a change is done.
