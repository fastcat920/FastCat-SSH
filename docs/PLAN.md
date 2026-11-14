# FastCat SSH delivery

Stages: technical validation → local client → encrypted backups → enhancements.

Architecture: Flutter responsive workspace; dartssh2 SSH/SFTP; xterm terminal;
secure storage credentials; local JSON metadata; authenticated encrypted portable backup.
No account required. SSH host fingerprints require explicit trust before authentication.

Desktop: server sidebar, terminal sessions above files/commands, draggable dividers.
Phone: servers/terminal/tools navigation. Layout values persist per device.

Backup: versioned .fastcatbackup envelope, PBKDF2-HMAC-SHA256 with random salt,
AES-256-GCM with fresh nonce; password never stored in backup. Preview before import,
merge or replace with recovery snapshot. Sensitive credentials opt-in.
Apple iCloud: explicit document export/import through system document picker first;
automatic backup requires signed iCloud container/provisioning and is tracked separately.
Windows: select iCloud Drive folder if installed. Android: portable file import/export.

Acceptance is evidence-based: tests/analyzer/build results are recorded; unsupported host
platforms and absent remote credentials are never represented as tested.
