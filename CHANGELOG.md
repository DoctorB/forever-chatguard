# Changelog

All notable changes to Forever ChatGuard. Versions follow `MAJOR.MINOR.PATCH`;
pre-releases carry an explicit `-alpha.N` / `-beta.N` suffix.

## 1.0.0 - 2026-10-14

**First release for WoW Forever.** Keep public chat readable without losing a
single real conversation.

### New

- **Observe first:** on first start nothing is hidden. ChatGuard lists what it
  would hide, so you can judge it before turning filtering on.
- **Repeated messages:** the same text from the same player in the same channel
  within 30 seconds (5–120) is hidden. Prices and item links count, so
  "10g" and "100g" are different messages.
- **Burst limit** (off by default): more than 5 messages in 10 seconds from one
  player in one channel.
- **Your own terms** (off by default): literal words or phrases, with a preview.
  No built-in word list.
- **Allow and block lists** for authors, including names with a surname.
- **Quarantine:** every hidden message stays viewable for the session with time,
  channel, author and reason; show the full text or allow the author in one click.
- **Channel choice** in the settings panel: Trade, General, custom channels,
  Say and Yell. Whispers, party, raid, guild and system messages are never touched.
- **One decision per message**, however many chat windows show it.
- English and Italian interface.

### Safety

- No network, telemetry, automatic messages or reports; chat text is never
  saved to disk.
- If anything goes wrong inside the addon, messages are shown as usual.
  After repeated internal errors filtering pauses until `/fcg on`.

### Compatibility

WoW Forever 1.60.1 (Interface 16001).

Author: DoctorB
