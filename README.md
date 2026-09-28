# myles.clock

A calendar clock for the Omarchy bar, with merged world-clock places, holiday markers, and a customisable time format.

> **Derived work.** Forked from Omarchy's built-in `omarchy.clock` and substantially modified.
> See [Credits](#credits) for licensing.

A calendar clock with a details panel, extended with **merged world-clock places**, holiday
markers, and a customisable time format.

## What it does

- **Bar:** time (or any custom format) with a calendar popup.
- **World clock:** several places in one list, each with its own time, offset, and day/night state.
- **Calendar:** month grid with holiday day-dots, plus an upcoming-events list.
- **Settings sheet:** per-widget time format, week start, and world-clock place list.
- **Summonable:** `omarchy-shell shell summon myles.clock '{}'` opens the panel from a shortcut.

## Repository layout

| Path | Purpose |
| --- | --- |
| `BarWidget.qml` | Manifest entry point; bar button, loads and drives the panel |
| `Panel.qml` | Calendar, world clock, settings sheet |
| `Model.js` | Time formatting, week maths, world-clock and holiday logic |
| `countries.js`, `holidays.js` | Generated data tables (checked in, no network needed at runtime) |
| `tools/generate-*.py` | Regenerate the data tables |
| `tests/test-core.js` | Unit tests for the formatting logic |

## Development

```bash
node tests/test-core.js                       # run the unit tests
python tools/generate-holidays.py             # refresh the holiday table
python tools/generate-countries.py            # refresh the country list
omarchy-shell shell rescanPlugins             # force rediscovery after edits
qs log -p "$OMARCHY_PATH/shell" --tail 100    # read QML errors
```

## Network calls

- **Runtime:** none. Weather links for a world-clock place are plain clickable
  `wttr.in` URLs, not automatic fetches.
- **Build-time only:** `tools/generate-*.py` read `raw.githubusercontent.com` once when you
  regenerate the data tables.

## Install

```bash
omarchy plugin add https://github.com/Omarchy-plugin/myles-clock.git --enable --yes
```

That clones, validates, installs to `~/.config/omarchy/plugins/myles.clock/`, and places it on your bar.

The stock `omarchy.clock` widget does the same job and will fight with this one. Turn it off:

```bash
omarchy plugin disable omarchy.clock
```

## Update

```bash
omarchy plugin update myles.clock --yes
```

Or update every git-managed plugin at once:

```bash
omarchy plugin update --yes
```

## Uninstall

omarchy plugin enable omarchy.clock   # if you want the built-in back

omarchy plugin remove myles.clock --yes

## Installing the whole suite

Every plugin in the suite installs with one command, and updates itself
automatically:

```bash
git clone https://github.com/Omarchy-plugin/myles-omarchy-plugins.git
cd myles-omarchy-plugins && ./install.sh
```

See [myles-omarchy-plugins](../myles-omarchy-plugins) for the update mechanism.

## Credits

- Omarchy — <https://omarchy.org> — MIT, © David Heinemeier Hansson. `omarchy.clock` is the base this is forked from.
- Mylesoft — <https://github.com/Omarchy-plugin> — modifications.

Plugins run unsandboxed inside the long-lived `omarchy-shell` process with your user
permissions. Review the source before enabling anything you did not write.
