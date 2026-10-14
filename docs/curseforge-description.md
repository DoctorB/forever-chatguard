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
Add words or phrases you never want to see. They are matched literally and ignore upper/lower case. A preview checks a term against the messages already in your quarantine before you turn it on.
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
2. Type `/fcg config` and tick the channels to watch, for example Trade and General.
3. Play as usual, then open `/fcg quarantine` to see what would have been hidden and why.
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
| `/fcg channel list` · `add <n or name>` · `remove <n or name>` | Choose channels |
| `/fcg term add <text>` · `remove` · `preview` · `on` · `off` | Manage your terms |
| `/fcg allow <Name>` · `/fcg block <Name>` | Author lists, e.g. `/fcg block Mira Stonefist` (`unallow` / `unblock` to remove) |
| `/fcg dup on` · `off` · `<seconds>` | Repeated-message rule |
| `/fcg flood on` · `off` · `<seconds> <messages>` | Burst rule |
| `/fcg reset` | Restore defaults (asks for confirmation) |

## FAQ

**I installed it and nothing is hidden. Is it working?**
Yes. ChatGuard starts in *observe* mode and watches no channel until you pick one. Open `/fcg config`, tick Trade or General, and after a while `/fcg quarantine` shows what it *would* have hidden. When you agree with what you see, type `/fcg filter`.

**What exactly counts as a repeated message?**
The same player, in the same channel, posting the same text within 30 seconds.
Example: a player posts `WTS [Copper Bar] x20, 5g each` at 12:00:00 and again at 12:00:10 and 12:00:20. You see the first one; the next two are hidden. At 12:00:30 the window has passed, so the next copy is shown once more and a new 30-second window starts. Hidden copies never extend the window, so a player who keeps advertising is still seen about twice a minute, not never.

**Will it hide a normal "LFG Deadmines" from two different players?**
No. Repeats are counted per player: two people asking the same thing are two different messages. The same text in Trade and in General is also treated separately.

**The same advert, but with a different price?**
Shown. `WTS bag 10g` and `WTS bag 100g` are different messages. Different items with the same name are different too, because ChatGuard compares the item link, not just its visible name. Only colours, extra spaces and upper/lower case are ignored.

**What does the burst limit do?**
It catches a player who floods one channel with many *different* messages. With the default (more than 5 messages in 10 seconds), the 6th message inside those 10 seconds is hidden. It is off by default; enable it in the panel or with `/fcg flood on`.

**I added the term "gold" and now "golden" is hidden too. Why?**
Terms match anywhere in the message, also inside longer words, so "gold" also matches "golden" and "marigold". Use a longer phrase, for example `cheap gold`, and check it with `/fcg term preview cheap gold`, which tests it against the messages in your quarantine.

**Does ChatGuard hide words like WTS, LFG or boost by itself?**
Never. There is no built-in word list. It only filters what you add.

**I missed something important. Can I get it back?**
Yes. Open `/fcg quarantine`: every hidden message of the current session is there with time, channel, author and reason. *Show text* displays the full message. *Allow author* means that player is always shown from now on.

**Does it ever touch whispers, party, raid or guild chat?**
No. Only the public channels you tick (Trade, General, custom channels, Say, Yell). Your own messages are never filtered either.

**A friend keeps getting caught. What do I do?**
Add them to the allow list: `/fcg allow Mira Stonefist`, or *Allow author* in the quarantine. The allow list always wins, even over the block list.

**Does it report or ignore players in the game?**
No. ChatGuard never sends messages, reports, invites, and it never changes your in-game ignore list. Everything stays local.

**Some messages are never analysed. Why?**
In some situations the game does not let addons read chat messages. ChatGuard then simply leaves those messages as they are.

**How do I switch it off quickly?**
`/fcg off`. Every new message passes immediately. `/fcg on` brings it back with your settings.

**Will it slow my game down?**
ChatGuard does a small amount of work only when a chat message arrives, and keeps limited data in memory. Message history is cleared at every reload or logout.

## Good to know

- Some messages in restricted game situations cannot be read by addons. ChatGuard leaves those exactly as they are.
- Settings are shared by all characters on your account.
- To uninstall, delete the `ForeverChatGuard` folder from `Interface\AddOns`.

## Feedback

Found a bug or have an idea? Open an issue on GitHub:
https://github.com/DoctorB/forever-chatguard/issues
