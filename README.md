# FastCat SSH

Local-first Flutter SSH/SFTP workspace for macOS, Windows, Android, and iOS.

## Run

```sh
flutter pub get
flutter run -d macos
```

Requires Flutter/Dart compatible with `pubspec.yaml`; iOS 14+, macOS supported by
Flutter and bundled plugins. Android builds require JDK 17 (this machine also has
JDK 26; use a per-command JAVA_HOME).

## Features

- Password or PEM private-key SSH, explicit first-use and changed-host-key trust.
- Windows PowerShell/CMD and Linux shell connections through a configured SSH server.
- Multiple terminal tabs, two-session split, adjustable desktop panes, layout presets.
- Responsive phone navigation and server search/groups.
- SFTP directory browsing, **global directory history**, **global directory favorites**.
- Upload progress/cancellation/retry, temporary upload publication, download,
  rename/delete, mkdir, UTF-8 text editing with modification conflict check.
- Saved commands with OS labels and `${parameter}` substitutions, execution preview.
- One-hop jump hosts and loopback SOCKS5 forwarding (lifetime bound to session).
- Portable authenticated encrypted `.fastcatbackup` import/export, optional secrets,
  merge/replace preview, and a locally secured recovery point.
- System document picker for manual iCloud Drive backup on Apple clients; Windows can
  save to an installed iCloud Drive folder; Android uses portable file transfer.

## Backup details

PBKDF2-HMAC-SHA256 (600,000 iterations, random 16-byte salt), AES-256-GCM
(random nonce, version-bound authenticated data). Password length minimum 10.
Encryption runs in a worker isolate. Password is not recoverable. Host trust is
stored in system secure storage and deliberately not imported: new devices verify
hosts themselves. Device metadata lives locally; passwords/keys live in OS secure
storage. macOS uses legacy Keychain without cross-app sharing to allow local builds
without provisioning. Release distribution still needs proper signing.

Merge keeps existing local records/credentials on ID collisions. Import recovery
is for completed/interrupted ordinary operations, not a transactional guarantee
against OS crashes during secure-store writes. Backups exclude remote file contents,
terminal logs, and host fingerprint trust. Keep a separate server backup.

## Verify

```sh
flutter analyze
flutter test
python3 -m venv /tmp/fastcat-qa
/tmp/fastcat-qa/bin/pip install -r tool/requirements-qa.txt
/tmp/fastcat-qa/bin/python tool/ssh_fixture.py
# In another terminal:
flutter test --dart-define=SSH_INTEGRATION=true
```

Fixture binds only 127.0.0.1:22345, uses throwaway host key and disposable SFTP root,
no real OS shell. Test credentials in fixture are public test values, not secrets.
Stop with Ctrl-C. CI runs this fixture and builds all four clients.

See [acceptance report](docs/ACCEPTANCE.md) for verified scope and remaining gates.

## Current limits

Manual iCloud only (as agreed); no cloud account or team service. SSH is command-line
control, not RDP. Real Windows/Linux server interoperability and physical mobile
validation still need suitable environments. Two-session horizontal split rather
than arbitrary docking. No automatic session restoration after network loss; explicit
reconnect creates a new shell. Background suspension can disconnect mobile sessions.
Downloads are buffered with a 100 MB size limit, text editing 1 MB. Uploads currently
also limited to 100 MB but streamed. Cancelled uploads normally remove temporary
files; connection loss may leave `.part` files. Replacement depends on server rename
support; existing destination is never deleted as a fallback. Shell path auto-follow,
bulk execution and automatic resumable downloads are future enhancements.

## 0.2.0 usage

Open **外观与终端** in the sidebar to select system/light/dark theme, terminal
foreground accent and a local background image. Background images stay on the device;
appearance preferences and command categories travel with encrypted backups.

In **命令库**, create categories and use the gear beside a command to preview,
edit or delete it. **命令编辑** includes a name, category and direct-send option.
**发送全部窗口** always previews connected targets before sending. Direct-send only
skips the single-session confirmation when explicitly enabled.

Terminal copy/paste is available in the toolbar and right-click menu. On macOS use
Cmd+C/V; on Windows use Ctrl+Shift+C and Ctrl+V to preserve Ctrl+C as interrupt.
Passwords remain hidden by default and can be revealed with the eye button.

## 0.2.1 inputs

Unified theme-aware inputs with persistent labels, clear actions, inline validation,
technical-text keyboard settings, and multiline file editing. Host save failures keep
form contents; password whitespace is preserved. Backup passwords validate length and
confirmation before closing. Single-line dialogs submit with Enter; multiline dialogs
use Ctrl/Cmd+Enter. Click Cancel to intentionally discard dialog input.

## 0.3.0 appearance and groups

Directory favorites are now global, with automatic deduplication of older per-host
favorites. In **外观与终端**, choose one of five app accents and one of three code/ANSI
palettes. Command and file editors colour common shell/PowerShell keywords, config
assignments, strings, numbers, variables and comments. This is lexical colouring, not
a full language parser; files over 200,000 characters render as plain text for speed.
Terminal palettes remap ANSI colours; syntax colour in ordinary terminal output still
comes from the remote program.

The sidebar's top plus creates a group. Each group has collapse and add-server buttons;
empty groups and collapsed states persist, and servers created from a group preselect
that group. Theme choices, global favorites and group configuration travel in backups.

## 0.3.1 backup diagnostics

Import now displays the selected file's name, size and SHA-256 fingerprint, and
keeps the password/file available after authentication failure. New exports use a
full timestamp and include an optional SHA-256 envelope checksum for accidental
corruption detection. AES-GCM authentication remains mandatory and legacy v1
backups remain readable. A matching file fingerprint does not prove a password is
correct; authentication failures cannot by themselves distinguish a wrong password
from damaged encrypted content in older files.

## 0.4.0 connected workspace

Connected terminals show a hardware/network strip with details: OS/CPU, logical cores,
CPU usage, memory, system disk, uptime, NIC traffic and SSH sampling round-trip time
(including remote processing). Sampling is read-only every five seconds, using Linux
/proc and Windows PowerShell/CIM. It never requires sudo, and unsupported commands or
permissions leave the terminal usable. Network rates need two samples; virtual NICs
can double-count traffic. Windows collectors still require validation on a real Windows host.

Files now use a directory tree on the left and current-directory files on the right.
Group titles toggle collapse as well as the chevron button.

In the command library, **新建命令** lives inside the selected folder. Clicking a name
sends directly; its gear toggles an inline bottom preview with edit/send/broadcast.
Create/edit share a dialog with **末尾添加回车符**. Turning it off sends only the text;
existing newlines in the command itself are retained. Old commands keep auto-Enter for
compatibility. Multi-session sends retain target confirmation.

**自定义命令** is now just an editor and current/all-session send buttons. Shell text
such as `${HOME}` is forwarded literally; saved library snippets continue supporting
interactive template parameters.

## 0.5.0 unified command editor and appearance

The command library now includes its editor: right on desktop, compact below the
library on mobile. New drafts can send without a name; saving requires a name and
body. Selecting a command's gear loads the same editable controls with category,
save, append-Enter, current-session send and confirmed broadcast. Switching drafts
asks before discarding unsaved edits. Command names still send directly.

Theme accents now colour all application/input/editor surfaces, including the open
appearance dialog. Separate editor palettes and terminal foreground controls were
removed; syntax and ANSI colours use the classic light/dark defaults. Legacy backup
fields remain readable but no longer override those defaults.

File editors include logical line numbers, current line/total and **跳转到行**.
Wrapped rows keep their original file line number; contents and CRLF are preserved.
The terminal toolbar can persistently show/hide its hardware/network strip. Mobile
navigation now sits outside the content area so notices do not cover navigation.

## 0.5.1 command feedback and terminal layout

Both library-name clicks and editor sends show inline status with target names and
whether Return was appended. Missing connections, failures and cancelled sends are
reported in the same area; successful delivery means written to the SSH channel,
not a remote exit-code confirmation. No command content is included in feedback.
Group names show the total host count, including when collapsed or searching.
Terminal actions occupy their own top row; session tabs wrap below them. Hardware
and network information wraps below the terminal. Excessively tall tab/metric lists
can scroll vertically to preserve terminal space.

## 0.5.2 mobile send navigation

Successful library or editor sends return mobile users to the terminal and dismiss
the editor keyboard. Cancelled or failed sends stay in the command library; desktop
layout is unchanged. The parent-directory control uses a corner arrow and now sits
immediately before Refresh in the file action row.


## GitHub builds

The **Build four clients** Actions workflow runs on pushes to `main`, pull requests,
and manual dispatch. Flutter is pinned to 3.44.7. Download each platform from the
workflow run's **Artifacts** section (retained for 14 days).

| Artifact | Contents and signing |
| --- | --- |
| FastCat-SSH-Windows-x64 | Release EXE plus required DLLs/data in a ZIP; not code signed |
| FastCat-SSH-macOS | Application ZIP, ad hoc signed; not notarized |
| FastCat-SSH-Android-test-key | Release APK signed with a generated debug/test key, not a production release key |
| FastCat-SSH-iOS-unsigned | Unsigned device IPA; requires Apple signing/provisioning before installation |
| FastCat-SSH-iOS-simulator | Simulator application ZIP; not an iPhone installation package |

No Apple certificates, provisioning profiles, production Android keys or user backup
files are included in the repository or needed for these builds. Android test keys
may differ between cloud runs, so those APKs are not guaranteed to upgrade each other.
Signed store distribution can be configured separately with repository secrets.

## 0.5.4 command folder management

Each command folder now has a vertical three-dot menu with Edit and Delete.
Renaming updates saved command membership and the current editor's category without
rewriting command content. Empty folders delete immediately; populated folders ask
before deleting the folder and its commands. Explicitly deleted folders stay deleted
after reload, including the last folder; create a folder before saving new commands.
Unsaved editor changes are retained as a draft when their folder is deleted.
The command editor's Save button sits directly to the right of the red Delete icon.
