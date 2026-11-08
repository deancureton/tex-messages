# Parity with Messages.app

Build: `./scripts/build.sh`, then open `build/TeX Messages.app`.
Grant Full Disk Access in System Settings. Automation and Contacts prompt on first use.
`scripts/build.sh` signs with the "LaTeXMessages Local Signing" keychain identity when present, so grants survive rebuilds. Without it, builds are ad-hoc and Full Disk Access must be re-added after each one.

## Done

- Conversation list from `chat.db`, merged across SMS/iMessage/handles by contact
- Previews with rendered math, relative times, unread dots, dock badge
- Search over names, handles, and message bodies
- Blue, green, and gray bubbles; tails on the last bubble of a run; timestamps
- Group senders and avatars, group events, tapbacks, replies
- Edited, unsent, Delivered/Read, Not Delivered
- Images, video posters, stickers, files, audio chips, jumbo emoji
- Link detection, text selection, copying math as its LaTeX source
- Live receive through FSEvents, older-message paging
- Sending text and files through Messages.app, new conversations, drafts
- Pinned conversations from `com.apple.messages.pinning`, group photos, and rich link cards
- Incoming bubbles slide out from behind the previous message, matched against a recording of Messages
- All twelve send effects on arrival, including invisible ink; click the "Sent with" note to replay. Built natively without a reference recording of the real effects
- Context menus on bubbles, photos, link cards, conversations, pins, the header, the composer, and empty areas
- Group reply threads with the original sender's avatar, a straight connector, and successive replies stacked under one quote
- Reply quotes and reply counts, animated sidebar reordering, attachment thumbnails in the message bar, and a live LaTeX preview while typing
- Send morph and transcript slide, matched against a 60 fps recording of Messages; receipt fade built from the same recording
- Inline `$...$` and `\(...\)`, display `$$...$$` and `\[...\]`, through MathJax, with currency guards and raw-text fallback
- Pasting images and files into the message bar
- Inline voice message playback with a waveform and seeking
- Context menu icons
- Pinned unread preview bubbles, matched against Messages focused and unfocused, with sizing and placement matched for one, two, and three unread pins in a row
- Group icons with member circles and the most recent sender largest, with layouts matched for two through seven members

## Not done yet

- Pinned unread bubbles are opaque; the real one tints slightly over the avatar
- Light mode has not been compared against Messages
- Pin, Mark as Unread, and Hide Alerts apply only inside this app
- Tapback landing animation (no reference recording yet)
- Emoji-only send animation is a best guess without a reference recording
- Bold, italic, and text effects from `attributedBody`
- Audio files that are not voice messages, and other attachments, open in their default app
- Pinned group chats are untested; only 1:1 pins have been seen in real data
- Which member gets each smaller group icon circle follows an unknown rule in Messages; groups of five or more can differ
- Business logos and verified badges
- Audio recording; the composer waveform is a disabled placeholder

## Not possible with public APIs

- Sending with an effect
- Sending tapbacks, replies, edits, or unsends: AppleScript can only send text and files
- Marking messages read on the server: read state here is local to this app
- Typing indicators: they never reach `chat.db`

## Testing

Reading, receiving, and the UI have been compared against a real `chat.db` and Messages.app.
Automated checks use a synthetic `chat.db` and never send.
Column names come from known macOS schemas and missing columns are tolerated.
