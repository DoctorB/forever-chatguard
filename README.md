# Forever ChatGuard

Local, transparent and reversible noise control for **public chat** in
**WoW Forever**. It hides close repeats, optional bursts from one author and
literal terms that *you* choose, while keeping normal conversation, group
calls and legitimate trading visible.

**Version 1.0.0** for WoW Forever 1.60.1 (Interface 16001).

## What it does

- **Observe first.** On first start nothing is hidden: ChatGuard lists what
  it *would* have hidden so you can judge its rules.
- **Repeated text.** Same author, same channel, same text within 30 s
  (5–120 s). Exact match after harmless normalization: colours removed, spaces
  collapsed, A–Z lowercased. Prices, digits and item links are kept, so
  `10g` ≠ `100g` and two different items with the same name are different.
- **Bursts (off by default).** More than 5 messages from one author in one
  channel within 10 s (both adjustable).
- **Your terms (off by default).** Literal words or phrases, case-insensitive
  for A–Z. There is no built-in word list: words such as WTS, LFG or gold are
  never filtered unless you add them. A short term also matches inside longer
  words.
- **Allow and block lists** of authors (`Name-Realm`); the allow list wins.
- **Quarantine.** Hidden or would-be-hidden messages stay viewable for the
  session with time, channel, author and reason. Nothing is ever re-sent.
- **Only the channels you select** (none at first start). Whispers, party,
  raid, guild, system and combat messages are never filtered.

Nothing leaves your computer: no network, telemetry, shared blacklists,
automatic reports or messages. Chat text is never saved to disk.

## Installation

1. Download the ZIP and extract it into
   `World of Warcraft\_classic_beta_\Interface\AddOns\`, so that the folder
   `ForeverChatGuard\` sits directly inside `AddOns`.
2. Restart the game or `/reload`. Type `/fcg status`.
3. Open `/fcg config` and tick the channels to watch (or `/fcg channel add Trade`).
4. Check `/fcg quarantine` for a while, then switch to filtering with `/fcg filter`.

The `_classic_beta_` folder is where the WoW Forever beta client is installed
today; the folder for the live game may differ.

## Commands

| Command | Effect |
| --- | --- |
| `/fcg`, `/fcg help` | Short help |
| `/fcg status` | State, mode, compatibility, counters |
| `/fcg on` / `/fcg off` | Enable / disable immediately |
| `/fcg observe` / `/fcg filter` | Only watch, or actually hide |
| `/fcg config` | Open the panel |
| `/fcg quarantine` | Open the quarantine window (`/fcg quarantine list` prints it) |
| `/fcg show <n>` / `/fcg allowentry <n>` | Full text / allow that author |
| `/fcg clear` | Empty the quarantine |
| `/fcg channel list` / `add <n or name>` / `remove <n or name>` | Choose channels |
| `/fcg term add/remove/preview/on/off <text>` | Literal terms |
| `/fcg allow`, `block`, `unallow`, `unblock <Name>` | Author lists (`Name Surname` works; realm optional) |
| `/fcg dup on/off/<seconds>` | Repeated-text rule |
| `/fcg flood on/off` or `/fcg flood <seconds> <messages>` | Burst rule |
| `/fcg reset`, then `/fcg reset confirm` | Restore defaults |

## Settings and uninstall

Settings are account-wide in `ForeverChatGuardDB`, stored by the client in
`WTF\Account\<ACCOUNT>\SavedVariables\ForeverChatGuard.lua`. Only preferences
and your lists are saved.

To uninstall, delete `Interface\AddOns\ForeverChatGuard\` and, optionally,
that `ForeverChatGuard.lua` settings file.

## Limits

- WoW Forever restricts what addons can read in some situations. Where chat
  arguments are *secret* values, ChatGuard cannot read them and leaves those
  messages unchanged.
- Your own messages are never filtered.
- After three internal errors within 60 s, filtering is suspended for the
  session (`/fcg on` resumes). Errors never hide a message.

## Development

```
lua5.1 tests/runner.lua                         # Lua test suites
lua5.1 tests/bench.lua                          # engine benchmark (10,000 events)
python3 -m unittest discover -s tests -p "test_release.py"
python3 scripts/release.py package --out release/local
```

See [docs/releasing.md](docs/releasing.md), [docs/manual-tests.md](docs/manual-tests.md)
and [docs/repository-setup.md](docs/repository-setup.md).

## License

MIT, see [LICENSE](LICENSE).
