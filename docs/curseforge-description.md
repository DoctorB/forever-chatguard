# Forever ChatGuard

**Keep public chat readable — without losing a single real conversation.**

Forever ChatGuard quietly cleans up the noise in public channels on **WoW Forever**: the same advert pasted every few seconds, one player flooding a channel, or words you simply never want to see again. Group calls, questions and genuine trading stay exactly where they are.

Everything happens on your computer, follows rules you can read, and can be undone with one command.

---

## Why ChatGuard

- **You stay in control.** No hidden word lists, no automatic judgements about other players. ChatGuard only acts on rules you can see and change.
- **Nothing is lost.** Every hidden message goes into a temporary quarantine with the reason it was hidden. Read it, or allow its author, in one click.
- **Try before you trust.** On first start ChatGuard only *observes*: it shows what it would hide while your chat stays untouched. Switch to filtering when you are happy with the results.

## Features

### 🔁 Repeated messages
Hides the same text from the same player in the same channel within 30 seconds (adjustable from 5 to 120). Matching is exact and smart: colours and extra spaces are ignored, but prices and item links are not. "WTS bag 10g" and "WTS bag 100g" are different messages, and so are two different items with the same name.

### 🌊 Burst limit *(optional)*
Hides messages from a player who sends more than 5 messages in 10 seconds in one channel. Both numbers are adjustable.

### ✏️ Your own terms *(optional)*
Add words or phrases you never want to see. They are matched literally and ignore upper/lower case. A preview shows what a term would catch before you turn it on.
ChatGuard ships with **no built-in list**: words like WTS, LFG or gold are never filtered unless you add them yourself.

### 👥 Allow and block lists
Always show a friend, or always hide a specific player, in the channels you choose. If a name is on both lists, the allow list wins.

### 📥 Quarantine
See every hidden (or "would hide") message with time, channel, author and reason. Show the full text or allow the author straight from the list. Quarantined messages are never sent back to chat.

### 🎯 Only where you want it
You pick the channels ChatGuard watches: Trade, General, Looking for Group, custom channels, Say or Yell. **Whispers, party, raid, guild, system and combat messages are never touched.**

### 🌍 English and Italian
The interface follows your game language, with English as the fallback.

## Privacy and safety

- No internet connection, no telemetry, no shared blacklists.
- Never sends messages, reports, invites or changes your in-game ignore list.
- Chat text is **never saved to disk**: only your settings and lists are stored.
- If anything goes wrong inside the addon, messages are simply shown as usual.

## Getting started

1. Install and log in. ChatGuard starts in **observe** mode.
2. Type `/fcg channel list`, then `/fcg channel add <number>` for the channels to watch.
3. Chat as usual, then open `/fcg quarantine` to see what would have been hidden.
4. Happy with it? Type `/fcg filter` to start hiding. `/fcg off` turns everything off instantly.

## Commands

| Command | What it does |
| --- | --- |
| `/fcg` | Help |
| `/fcg status` | Current mode, channels and counters |
| `/fcg on` · `/fcg off` | Turn ChatGuard on or off |
| `/fcg observe` · `/fcg filter` | Only watch, or actually hide |
| `/fcg config` | Open the settings panel |
| `/fcg quarantine` | List hidden messages |
| `/fcg show <n>` · `/fcg allowentry <n>` | Full text of an entry · allow its author |
| `/fcg clear` | Empty the quarantine |
| `/fcg channel list` · `add <n>` · `remove <n>` | Choose channels |
| `/fcg term add <text>` · `remove` · `preview` · `on` · `off` | Manage your terms |
| `/fcg allow <Name-Realm>` · `/fcg block <Name-Realm>` | Author lists (`unallow` / `unblock` to remove) |
| `/fcg dup on` · `off` · `<seconds>` | Repeated-message rule |
| `/fcg flood on` · `off` · `<seconds> <messages>` | Burst rule |
| `/fcg reset` | Restore defaults (asks for confirmation) |

## Good to know

- Some messages in restricted game situations cannot be read by addons. ChatGuard leaves those exactly as they are.
- Settings are shared by all characters on your account.
- To uninstall, delete the `ForeverChatGuard` folder from `Interface\AddOns`.

## Feedback

Found a bug or have an idea? Open an issue on GitHub:
https://github.com/DoctorB/forever-chatguard/issues
