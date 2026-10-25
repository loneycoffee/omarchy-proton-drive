import QtQuick
import Quickshell
import Quickshell.Io

// The drive's state, mounted once for the shell.
//
// Omarchy builds a bar per monitor; the sign-in, the folder being browsed
// and the transfer queue live here so every bar agrees and a transfer keeps
// going when the panel closes. bin/pdrive does the talking to Proton's
// `proton-drive` CLI. Transfers run one at a time, in the order asked for.
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
  // Bundled, as a path: icon-theme names vary between themes, and one the
  // notification popup cannot find shows up as a checkerboard.
  readonly property string iconDir: Qt.resolvedUrl("icons").toString().replace(/^file:\/\//, "")
  readonly property string home: Quickshell.env("HOME")

  // Set by the bar widget from its settings.
  property string downloadDir: "~/Downloads"

  property var status: ({ installed: true, signedIn: true, error: "" })
  property bool statusLoaded: false
  readonly property bool installed: root.status.installed !== false
  readonly property bool signedIn: root.status.signedIn === true
  property bool signingIn: false

  // The folder on screen.
  property string path: "/my-files"
  property var items: []
  property bool listing: false
  property string listError: ""

  property var usage: ({})
  property bool sizing: false

  // Transfers: what is running and what waits.
  property var queue: []
  property var current: null
  readonly property bool transferring: root.current !== null
  property string lastError: ""
  property string flash: ""

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function open(path) {
    root.path = path
    root.listError = ""
    listProc.command = [root.ctl, "list", path]
    root.listing = true
    // Restarting a running Process does not rerun it; stop it first.
    listProc.running = false
    listProc.running = true
  }

  function up() {
    if (root.path === "/my-files") return
    root.open(root.path.slice(0, root.path.lastIndexOf("/")) || "/my-files")
  }

  function measure() {
    if (sizeProc.running) return
    root.sizing = true
    sizeProc.running = true
  }

  function signIn() {
    if (loginProc.running) return
    root.signingIn = true
    root.lastError = ""
    loginProc.running = true
  }

  function cancelSignIn() {
    loginProc.running = false
    root.signingIn = false
  }

  function signOut() {
    actionProc.command = [root.ctl, "logout"]
    actionProc.running = true
  }

  function enqueue(job) {
    root.queue = root.queue.concat([job])
    root.next()
  }

  function next() {
    if (root.current !== null || root.queue.length === 0) return
    var job = root.queue[0]
    root.queue = root.queue.slice(1)
    root.current = job
    root.lastError = ""
    transferProc.command = job.kind === "upload"
      ? [root.ctl, "upload", job.target].concat(job.files)
      : [root.ctl, "download", job.source, job.dest]
    transferProc.running = true
  }

  function upload(files, target) {
    if (!files || files.length === 0) return
    var label = files.length === 1 ? files[0].slice(files[0].lastIndexOf("/") + 1) : files.length + " items"
    root.enqueue({ kind: "upload", files: files, target: target || root.path, label: label })
  }

  // Asks the desktop file chooser, then uploads what was picked.
  function pickAndUpload(target) {
    if (pickProc.running) return
    pickProc.target = target || root.path
    pickProc.running = true
  }

  function download(item) {
    root.enqueue({ kind: "download", source: item.path, dest: root.downloadDir, label: item.name })
  }

  function copyLink(item) {
    shareProc.label = item.name
    shareProc.command = [root.ctl, "share", item.path]
    shareProc.running = true
  }

  function notify(summary, body, icon) {
    Quickshell.execDetached(["notify-send", "-a", "Proton Drive", "-i", root.iconDir + "/" + (icon || "upload") + ".svg", summary, body || ""])
  }

  function showFlash(text) {
    root.flash = text
    flashTimer.restart()
  }

  function size(bytes) {
    var units = ["B", "KB", "MB", "GB", "TB"]
    var n = Number(bytes) || 0
    var i = 0
    while (n >= 1000 && i < units.length - 1) {
      n /= 1000
      i++
    }
    return (i === 0 ? n : n.toFixed(n < 10 ? 1 : 0)) + " " + units[i]
  }

  function parse(text, fallback) {
    try {
      return JSON.parse(String(text || ""))
    } catch (e) {
      return fallback
    }
  }

  Process {
    id: statusProc
    command: [root.ctl, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var next = root.parse(text, null)
        if (!next) return
        var was = root.signedIn
        root.status = next
        root.statusLoaded = true
        if (next.signedIn && (!was || root.items.length === 0)) root.open(root.path)
      }
    }
  }

  Process {
    id: listProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var r = root.parse(text, { ok: false, error: "unreadable listing", items: [] })
        // A slow listing for a folder already left behind is not news.
        if (r.path && r.path !== root.path) return
        root.items = r.items || []
        root.listError = r.ok ? "" : (r.error || "")
        root.listing = false
      }
    }
  }

  Process {
    id: sizeProc
    command: [root.ctl, "size", "/my-files"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.usage = root.parse(text, {})
        root.sizing = false
      }
    }
  }

  Process {
    id: loginProc
    command: [root.ctl, "login"]
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var msg = String(text || "").trim()
        if (msg !== "" && root.signingIn) root.lastError = msg.split("\n")[0]
      }
    }
    onRunningChanged: {
      if (running) return
      root.signingIn = false
      root.refresh()
    }
  }

  Process {
    id: actionProc
    onRunningChanged: if (!running) {
      root.items = []
      root.usage = {}
      root.path = "/my-files"
      root.refresh()
    }
  }

  Process {
    id: pickProc
    property string target: ""
    command: [root.ctl, "pick"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.upload(root.parse(text, []), pickProc.target)
    }
  }

  Process {
    id: shareProc
    property string label: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var r = root.parse(text, { ok: false, error: "no answer" })
        if (r.ok) {
          Quickshell.execDetached(["wl-copy", r.url])
          root.showFlash("Link to " + shareProc.label + " copied")
          root.open(root.path)
        } else {
          root.lastError = r.error
        }
      }
    }
  }

  Process {
    id: transferProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var job = root.current
        var r = root.parse(text, { ok: false, error: "no answer from proton-drive" })
        if (job) {
          var verb = job.kind === "upload" ? "Uploaded" : "Downloaded"
          if (r.ok) {
            var body = r.items + " item" + (r.items === 1 ? "" : "s") + ", " + root.size(r.bytes)
              + (r.skipped ? " (" + r.skipped + " already there)" : "")
            root.notify(verb + " " + job.label, job.kind === "download" ? body + "\nto " + job.dest : body,
              job.kind)
          } else {
            var why = r.error || (r.failures || []).join("\n") || "unknown error"
            root.lastError = (job.kind === "upload" ? "Upload" : "Download") + " of " + job.label + " failed: " + why
            root.notify((job.kind === "upload" ? "Upload" : "Download") + " failed", job.label + "\n" + why, "error")
          }
          if (job.kind === "upload" && (job.target === root.path)) root.open(root.path)
        }
        root.current = null
        root.next()
      }
    }
  }

  Timer {
    id: flashTimer
    interval: 2500
    onTriggered: root.flash = ""
  }

  Component.onCompleted: root.refresh()
}
