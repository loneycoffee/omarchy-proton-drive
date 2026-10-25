# Proton Drive

A cloud on the Omarchy bar that puts your Proton Drive in a folder, using
[rclone's Proton Drive backend](https://rclone.org/protondrive/).

- **The cloud** is checked while the drive is mounted, pulses while mounting,
  and shows a warning when rclone stopped with an error. **Right click** opens
  the folder, mounting it first if needed.
- **The panel** has the mount switch, the space used and free, and buttons for
  the folder, the web app and rclone's log.
- **Mount at login**, as a switch.

The mount is `rclone mount` run by the systemd user unit
`proton-drive.service` (written to `~/.config/systemd/user/` on first mount),
with a full VFS cache: a file opens at local speed once it has been read, and
changes go up in the background, even across restarts.

## Install

```bash
omarchy pkg add rclone
omarchy plugin add https://github.com/loneycoffee/omarchy-proton-drive.git --enable
```

Then click the cloud and **Sign in…**: a terminal asks for your username,
password, mailbox password (two-password mode only) and 2FA code, and checks
them right away. rclone keeps the session afterwards, so the 2FA code is
needed once.

Your password is stored *obscured* in `~/.config/rclone/rclone.conf`, which is
not encryption: keep that file to yourself, or set a config password with
`rclone config` (the unit then needs `RCLONE_CONFIG_PASS`).

Open the panel from a keybinding with
`omarchy-shell shell toggle proton-drive`.

## Settings

On the `proton-drive` bar entry in `~/.config/omarchy/shell.json`:

| Key          | Default                   | Meaning                         |
|--------------|---------------------------|---------------------------------|
| `mountpoint` | `~/ProtonDrive`           | Where the drive shows up        |
| `remote`     | `proton`                  | The rclone remote's name        |
| `webUrl`     | `https://drive.proton.me` | What the Web button opens       |

## Keys in the panel

`enter` mount/unmount · `o` open folder · `w` web · `r` refresh storage · `esc` close

## Command line

```
pdrive [OPTS] status        JSON: installed, signed in, mounted, the unit's state
pdrive [OPTS] about         JSON: used / free / total bytes (asks Proton)
pdrive [OPTS] mount         write the user unit and start it
pdrive [OPTS] unmount       stop the unit
pdrive [OPTS] autostart on|off
pdrive [OPTS] log           the last lines rclone logged
pdrive [OPTS] setup         interactive: sign in to Proton Drive

OPTS: --remote NAME (default proton)   --mount DIR (default ~/ProtonDrive)
```

rclone's Proton Drive backend is community-built against Proton's unofficial
API; it works well for files and folders, but it is not Proton's own client.
