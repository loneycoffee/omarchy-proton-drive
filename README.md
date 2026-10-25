# Proton Drive

A cloud on the Omarchy bar for Proton's official
[Drive CLI](https://github.com/protondriveapps/sdk/tree/main/cli)
(`proton-drive`): your files a click away, without a sync client.

- **Browse** My files folder by folder, with sizes and dates; the path on top
  takes you back up.
- **Upload** files picked in the desktop file chooser into the folder on
  screen. **Right click** the cloud to upload into `uploadFolder` without
  opening anything.
- **Download** a file (click it) or a whole folder (the button on hover) into
  `~/Downloads`. Nothing local is overwritten: a name already there gets a
  suffix.
- **Copy a public link** to anything; one is made if it has none.
- Transfers queue up, carry on with the panel closed, and end in a
  notification. The cloud pulses while one runs.
- **Size** adds up what My files holds (it walks the whole tree, so it waits for
  a click).

Uploads that meet a file of the same name keep both; folders are merged.

## Install

Put Proton's binary on your `PATH` as `proton-drive` (check it against the
SHA-512 on [proton.me/download/drive/cli](https://proton.me/download/drive/cli/index.html)):

```bash
curl -Lo ~/.local/bin/proton-drive https://proton.me/download/drive/cli/0.9.0/linux-x64/proton-drive
sha512sum ~/.local/bin/proton-drive   # compare with the page
chmod +x ~/.local/bin/proton-drive
omarchy plugin add https://github.com/loneycoffee/omarchy-proton-drive.git --enable
```

The AUR's `proton-drive-cli-git` builds from source instead, but its build
fetches packages from Proton's own registry (`pkg.protontech.ch`), which is not
reachable from every network; when it is not, the build hangs. `proton-drive
version` says when a newer CLI is out. Then click the cloud and **Sign in**: Proton's
sign-in page opens in your browser, and the panel picks it up once you are
through. The CLI keeps the session in your keyring (libsecret); no password is
stored anywhere.

Open the panel from a keybinding with
`omarchy-shell shell toggle proton-drive`.

## What it does not do

Proton's CLI has no mount and no sync yet (Proton lists sync as coming), so
there is no `~/ProtonDrive` folder that stays up to date: this is a browser
with upload and download. The CLI is pre-release, and Proton plans a change of
its encryption model around the turn of 2027 that older CLI versions will not
survive; keep it updated.

## Settings

On the `proton-drive` bar entry in `~/.config/omarchy/shell.json`:

| Key            | Default                   | Meaning                                  |
|----------------|---------------------------|------------------------------------------|
| `uploadFolder` | `/my-files`               | Where right click uploads (a Drive path) |
| `downloadDir`  | `~/Downloads`             | Where downloads land                     |
| `webUrl`       | `https://drive.proton.me` | What the Web link opens                  |

## Keys in the panel

`h` up a folder · `u` upload here · `r` refresh · `w` web · `esc` close

## Command line

```
pdrive status                  JSON: is the CLI installed, is anyone signed in
pdrive login                   sign in through the browser (waits until done)
pdrive logout                  sign out
pdrive list PATH               JSON: a folder's items, folders first
pdrive size [PATH]             JSON: bytes and items under PATH (default /my-files)
pdrive upload PARENT FILE...   upload files or folders into PARENT, as JSON
pdrive download PATH DIR       download PATH into the local DIR, as JSON
pdrive share PATH              JSON: the public link to PATH, made if missing
pdrive pick                    JSON: files chosen in the desktop file chooser
```

Drive paths are the CLI's: `/my-files` is your root.
