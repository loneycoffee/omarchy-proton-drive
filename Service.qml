import QtQuick
import Quickshell
import Quickshell.Io

// The drive's state, mounted once for the shell.
//
// Omarchy builds a bar per monitor; whether the drive is mounted, the space
// used and whatever action is running live here so every bar agrees.
// bin/pdrive does the work: `status` is local and cheap (systemctl and the
// mount table), `about` asks Proton and runs only when the panel opens.
Item {
  id: root
  width: 0
  height: 0
  visible: false

  // Host injection.
  property var shell: null
  property var manifest: null
  property string omarchyPath: ""

  readonly property string ctl: Qt.resolvedUrl("bin/pdrive").toString().replace(/^file:\/\//, "")
  readonly property string omarchyBin: (root.omarchyPath || Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy") + "/bin"

  // Set by the bar widget from its settings.
  property string remote: "proton"
  property string mountpoint: "~/ProtonDrive"
  readonly property var opts: ["--remote", root.remote, "--mount", root.mountpoint]

  property var status: ({ installed: true, configured: true, mounted: false, state: "inactive" })
  property var about: ({})
  property bool aboutLoading: false
  property bool busy: false
  property string lastError: ""

  readonly property bool mounted: root.status.mounted === true
  readonly property bool starting: root.status.state === "activating" || (root.busy && !root.mounted)
  readonly property bool failed: root.status.state === "failed"

  property bool _wasMounted: false
  property bool _announced: false

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function refreshAbout() {
    if (aboutProc.running) return
    root.aboutLoading = true
    aboutProc.running = true
  }

  function act(args) {
    if (actionProc.running) return
    root.busy = true
    root.lastError = ""
    actionProc.command = [root.ctl].concat(root.opts).concat(args)
    actionProc.running = true
  }

  function mount() { root.act(["mount"]) }
  function unmount() { root.act(["unmount"]) }
  function toggle() { root.mounted || root.starting ? root.unmount() : root.mount() }
  function setAutostart(on) { root.act(["autostart", on ? "on" : "off"]) }

  function openFolder(sub) {
    Quickshell.execDetached(["xdg-open", root.status.mountpoint + (sub ? "/" + sub : "")])
  }

  // Signing in asks for a password and maybe a 2FA code, so it goes to a
  // terminal rather than through the panel.
  function signIn() {
    var cmd = [root.ctl].concat(root.opts).concat(["setup"]).map(function(a) { return "'" + String(a).replace(/'/g, "'\\''") + "'" }).join(" ")
    Quickshell.execDetached([root.omarchyBin + "/omarchy-launch-floating-terminal-with-presentation", cmd])
    signinWatch.restart()
  }

  function showLog() {
    var cmd = "journalctl --user -u proton-drive.service -n 200 -f"
    Quickshell.execDetached([root.omarchyBin + "/omarchy-launch-floating-terminal-with-presentation", cmd])
  }

  function notify(summary, body) {
    Quickshell.execDetached(["notify-send", "-a", "Proton Drive", "-i", "folder-remote", summary, body || ""])
  }

  Process {
    id: statusProc
    command: [root.ctl].concat(root.opts).concat(["status"])
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var next = JSON.parse(String(text || "{}"))
          var was = root._wasMounted
          root.status = next
          if (next.mounted !== was) {
            root._wasMounted = next.mounted === true
            if (root._announced && !next.mounted && next.state === "failed")
              root.notify("Proton Drive stopped", next.error || "rclone exited; see the log")
          }
          root._announced = true
        } catch (e) {
          console.warn("proton-drive: unreadable status")
        }
      }
    }
  }

  Process {
    id: aboutProc
    command: [root.ctl].concat(root.opts).concat(["about"])
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          root.about = JSON.parse(String(text || "{}"))
        } catch (e) {
          root.about = {}
        }
        root.aboutLoading = false
      }
    }
  }

  Process {
    id: actionProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var r = JSON.parse(String(text || "{}"))
          if (!r.ok) root.lastError = r.message || "systemctl failed"
        } catch (e) {}
        root.busy = false
        root.refresh()
        settle.restart()
      }
    }
  }

  // Starting a mount takes a few seconds (rclone signs in first); look again
  // quickly until it settles.
  Timer {
    id: settle
    property int tries: 0
    interval: 1000
    repeat: true
    onRunningChanged: if (running) tries = 0
    onTriggered: {
      root.refresh()
      tries++
      if (tries > 20 || (root.status.state !== "activating" && root.status.state !== "deactivating")) stop()
    }
  }

  Timer {
    interval: 15000
    repeat: true
    running: true
    onTriggered: root.refresh()
  }

  Timer {
    id: signinWatch
    property int tries: 0
    interval: 5000
    repeat: true
    onRunningChanged: if (running) tries = 0
    onTriggered: {
      root.refresh()
      tries++
      if (root.status.configured || tries > 36) {
        stop()
        if (root.status.configured) root.refreshAbout()
      }
    }
  }

  onOptsChanged: root.refresh()
  Component.onCompleted: root.refresh()
}
