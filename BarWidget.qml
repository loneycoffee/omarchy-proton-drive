import QtQuick
import Quickshell
import qs.Ui
import qs.Commons

// Bar cloud and panel for Proton Drive, in the same quiet style as the
// Displays panel: a switch that mounts the drive as a folder, the space it
// uses, and ways into it — the folder, the web app, rclone's log.
//
// Left click opens the panel; right click opens the folder (mounting it
// first if needed). Everything goes through bin/pdrive, which runs
// `rclone mount` as the systemd user unit proton-drive.service.
//
// Summon from a keybinding with:  omarchy-shell shell toggle proton-drive
Panel {
  id: root

  moduleName: "proton-drive"

  property var svc: null

  function bindService() {
    if (root.svc) return
    var host = root.bar && root.bar.shell ? root.bar.shell : null
    if (!host || typeof host.serviceFor !== "function") return
    root.svc = host.serviceFor("proton-drive")
    root.pushServiceSettings()
  }

  function pushServiceSettings() {
    if (!root.svc) return
    root.svc.remote = String(root.setting("remote", "proton"))
    root.svc.mountpoint = String(root.setting("mountpoint", "~/ProtonDrive"))
  }

  onBarChanged: bindService()
  onSettingsChanged: pushServiceSettings()

  // The service may mount after the bar, and is rebuilt on plugin hot-reload.
  Timer {
    interval: 250
    repeat: true
    running: !root.svc
    onTriggered: root.bindService()
  }

  readonly property var status: root.svc ? root.svc.status : ({})
  readonly property var about: root.svc ? root.svc.about : ({})
  readonly property bool installed: root.status.installed !== false
  readonly property bool configured: root.status.configured !== false
  readonly property bool mounted: root.svc ? root.svc.mounted : false
  readonly property bool starting: root.svc ? root.svc.starting : false
  readonly property bool failed: root.svc ? root.svc.failed : false
  readonly property string webUrl: String(root.setting("webUrl", "https://drive.proton.me"))

  readonly property color fg: Color.popups.text
  readonly property color dim: Util.alpha(fg, 0.62)
  readonly property color faint: Util.alpha(fg, 0.38)
  readonly property color solidBackground: Qt.rgba(Color.popups.background.r, Color.popups.background.g, Color.popups.background.b, 0.96)
  readonly property string fontFamily: root.bar && root.bar.fontFamily ? root.bar.fontFamily : Style.font.family

  readonly property string icon: root.failed ? "󰧠" : (root.mounted ? "󰅠" : (root.starting ? "󰘿" : "󰅤"))

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

  function prettyPath(path) {
    var home = Quickshell.env("HOME")
    path = String(path || "")
    return home && path.indexOf(home) === 0 ? "~" + path.slice(home.length) : path
  }

  function quickAction() {
    if (!root.svc) return
    if (!root.installed || !root.configured) {
      root.open()
    } else if (root.mounted) {
      root.svc.openFolder("")
    } else {
      root.svc.mount()
      openWhenMounted.restart()
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: {
    if (!opened || !root.svc) return
    root.svc.refresh()
    if (root.configured) root.svc.refreshAbout()
  }

  // Right click on an unmounted drive: open the folder once it is there.
  Timer {
    id: openWhenMounted
    property int tries: 0
    interval: 1000
    repeat: true
    onRunningChanged: if (running) tries = 0
    onTriggered: {
      tries++
      if (root.mounted) {
        stop()
        root.svc.openFolder("")
      } else if (tries > 30 || root.failed) {
        stop()
      }
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    tooltipText: root.mounted ? "Proton Drive: " + root.prettyPath(root.status.mountpoint)
      : (root.starting ? "Proton Drive: mounting…" : (root.failed ? "Proton Drive: failed" : "Proton Drive: not mounted"))
    onPressed: function(b) {
      if (b === Qt.RightButton) root.quickAction()
      else root.toggle()
    }

    SequentialAnimation on opacity {
      running: root.starting
      loops: Animation.Infinite
      alwaysRunToEnd: true
      NumberAnimation { to: 0.35; duration: 600; easing.type: Easing.InOutQuad }
      NumberAnimation { to: 1; duration: 600; easing.type: Easing.InOutQuad }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(view.implicitHeight, Style.space(640))

    Rectangle {
      anchors.fill: parent
      anchors.margins: -panel.padding
      radius: Style.cornerRadius
      color: root.solidBackground
    }

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onActivateRequested: if (root.svc && root.configured) root.svc.toggle()
      onTextKey: function(text) {
        if (text === "o" && root.mounted) root.svc.openFolder("")
        else if (text === "w") Quickshell.execDetached(["xdg-open", root.webUrl])
        else if (text === "r" && root.svc) root.svc.refreshAbout()
      }

      Column {
        id: view
        width: parent.width
        spacing: Style.space(14)

        // ---------- Title and switch ----------
        Item {
          width: parent.width
          height: Math.max(title.implicitHeight, power.implicitHeight)

          Text {
            id: title
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "Proton Drive"
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }

          ToggleSwitch {
            id: power
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: root.installed && root.configured
            checked: root.mounted || root.starting
            busy: root.starting || (!!root.svc && root.svc.busy)
            foreground: root.fg
            onToggled: if (root.svc) root.svc.toggle()
          }
        }

        // ---------- Not set up ----------
        Column {
          width: parent.width
          spacing: Style.space(10)
          visible: !root.installed || !root.configured

          Text {
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            text: !root.installed
              ? "rclone is not installed. Install it with:\nomarchy pkg add rclone"
              : "Sign in to put your Proton Drive at " + root.prettyPath(root.status.mountpoint) + ". rclone asks for your password and, if you use one, a 2FA code."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          Button {
            visible: root.installed
            text: "Sign in…"
            iconText: "󰍂"
            bordered: true
            foreground: root.fg
            fontFamily: root.fontFamily
            onClicked: {
              if (root.svc) root.svc.signIn()
              root.close()
            }
          }
        }

        // ---------- Status ----------
        Column {
          width: parent.width
          spacing: Style.space(10)
          visible: root.installed && root.configured

          Row {
            spacing: Style.space(14)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: root.icon
              color: root.failed ? Color.urgent : (root.mounted ? Color.accent : root.faint)
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }

            Column {
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                textFormat: Text.PlainText
                text: root.mounted ? "Mounted" : (root.starting ? "Mounting…" : (root.failed ? "Stopped with an error" : "Not mounted"))
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.subtitle
                font.bold: true
              }

              Text {
                textFormat: Text.PlainText
                text: root.prettyPath(root.status.mountpoint) + "  ·  " + (root.status.remote || "") + ":"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }

          Text {
            width: parent.width
            visible: text !== ""
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            text: root.svc && root.svc.lastError !== "" ? root.svc.lastError : (root.status.error || "")
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          // Storage.
          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: root.about.ok === true && root.about.total > 0

            Item {
              width: parent.width
              height: usedLabel.implicitHeight

              Text {
                id: usedLabel
                anchors.left: parent.left
                textFormat: Text.PlainText
                text: root.size(root.about.used) + " used"
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Text {
                anchors.right: parent.right
                textFormat: Text.PlainText
                text: root.size(root.about.free) + " free of " + root.size(root.about.total)
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }

            Rectangle {
              width: parent.width
              height: Style.space(6)
              radius: Style.cornerRadius > 0 ? height / 2 : 0
              color: Util.alpha(root.fg, 0.12)

              Rectangle {
                width: Math.round(parent.width * Math.min(1, root.about.used / Math.max(1, root.about.total)))
                height: parent.height
                radius: parent.radius
                color: root.about.used / Math.max(1, root.about.total) > 0.9 ? Color.urgent : Style.selectedStateColor(root.fg, Color.accent)
              }
            }
          }

          Text {
            visible: !!root.svc && root.svc.aboutLoading && root.about.ok !== true
            textFormat: Text.PlainText
            text: "Asking Proton for your storage…"
            color: root.faint
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Flow {
            width: parent.width
            spacing: Style.space(6)

            Button {
              text: "Open folder"
              iconText: "󰉋"
              bordered: true
              enabled: root.mounted
              foreground: root.fg
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              onClicked: {
                root.svc.openFolder("")
                root.close()
              }
            }

            Button {
              text: "Web"
              iconText: "󰖟"
              bordered: true
              foreground: root.fg
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              onClicked: {
                Quickshell.execDetached(["xdg-open", root.webUrl])
                root.close()
              }
            }

            Button {
              text: "Log"
              iconText: "󰦪"
              bordered: true
              foreground: root.fg
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              onClicked: {
                root.svc.showLog()
                root.close()
              }
            }
          }

          PanelSeparator { foreground: root.fg }

          Item {
            width: parent.width
            height: Math.max(autoLabel.implicitHeight, autoSwitch.implicitHeight)

            Text {
              id: autoLabel
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "Mount at login"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            ToggleSwitch {
              id: autoSwitch
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              checked: root.status.autostart === true
              foreground: root.fg
              onToggled: if (root.svc) root.svc.setAutostart(!checked)
            }
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            text: "Files open at local speed once read; changes upload in the background. Unmounting with uploads pending finishes them next time."
            color: root.faint
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
