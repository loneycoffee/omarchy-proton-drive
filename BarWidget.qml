import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Ui
import qs.Commons

// Bar cloud and panel for Proton Drive, in the same quiet style as the
// Displays panel, on Proton's own `proton-drive` CLI:
//
//   Browse     My files, folder by folder
//   Upload     files from the desktop file chooser, into the folder on screen
//   Download   a file or folder into ~/Downloads (click it)
//   Share      copy a public link to anything (made if it has none)
//
// Left click opens the panel; right click uploads into `uploadFolder`.
// Transfers carry on with the panel closed and end in a notification.
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
    if (root.svc) root.svc.downloadDir = String(root.setting("downloadDir", "~/Downloads"))
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

  readonly property bool installed: root.svc ? root.svc.installed : true
  readonly property bool signedIn: root.svc ? root.svc.signedIn : false
  readonly property bool ready: root.installed && root.signedIn
  readonly property bool transferring: root.svc ? root.svc.transferring : false
  readonly property var current: root.svc ? root.svc.current : null
  readonly property string uploadFolder: String(root.setting("uploadFolder", "/my-files"))
  readonly property string webUrl: String(root.setting("webUrl", "https://drive.proton.me"))

  readonly property color fg: Color.popups.text
  readonly property color dim: Util.alpha(fg, 0.62)
  readonly property color faint: Util.alpha(fg, 0.38)
  readonly property color solidBackground: Qt.rgba(Color.popups.background.r, Color.popups.background.g, Color.popups.background.b, 0.96)
  readonly property string fontFamily: root.bar && root.bar.fontFamily ? root.bar.fontFamily : Style.font.family

  readonly property string icon: root.transferring
    ? (root.current && root.current.kind === "download" ? "󰅢" : "󰅧")
    : (root.ready ? "󰅟" : "󰅤")

  // "/my-files/Documents/Taxes" -> ["My files", "Documents", "Taxes"]
  readonly property var crumbs: {
    var path = root.svc ? root.svc.path : "/my-files"
    var parts = path.replace(/^\/my-files\/?/, "").split("/").filter(function(p) { return p !== "" })
    return ["My files"].concat(parts)
  }

  function iconFor(item) {
    if (item.folder) return "󰉋"
    var t = String(item.mediaType || "")
    if (t.indexOf("image/") === 0) return "󰋩"
    if (t.indexOf("video/") === 0) return "󰈫"
    if (t.indexOf("audio/") === 0) return "󰈣"
    if (t === "application/pdf") return "󰈦"
    if (t.indexOf("zip") !== -1 || t.indexOf("compressed") !== -1 || t.indexOf("tar") !== -1) return "󰗄"
    if (t.indexOf("text/") === 0) return "󰈙"
    return "󰈔"
  }

  function dateLabel(iso) {
    if (!iso) return ""
    var d = new Date(iso)
    if (isNaN(d.getTime())) return ""
    var now = new Date()
    if (d.toDateString() === now.toDateString()) return Qt.formatTime(d, "HH:mm")
    if (d.getFullYear() === now.getFullYear()) return Qt.formatDate(d, "d MMM")
    return Qt.formatDate(d, "d MMM yyyy")
  }

  function goToCrumb(index) {
    if (!root.svc) return
    var parts = root.crumbs.slice(1, index + 1)
    root.svc.open("/my-files" + (parts.length ? "/" + parts.join("/") : ""))
  }

  function quickAction() {
    if (!root.svc) return
    if (!root.ready) root.open()
    else root.svc.pickAndUpload(root.uploadFolder)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: {
    if (!opened || !root.svc) return
    root.svc.refresh()
    if (root.svc.signedIn) root.svc.open(root.svc.path)
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    tooltipText: root.transferring
      ? (root.current.kind === "upload" ? "Uploading " : "Downloading ") + root.current.label + "…"
      : (root.ready ? "Proton Drive" : "Proton Drive: signed out")
    onPressed: function(b) {
      if (b === Qt.RightButton) root.quickAction()
      else root.toggle()
    }

    SequentialAnimation on opacity {
      running: root.transferring
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
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(header.implicitHeight + Style.space(12) + body.implicitHeight, Style.space(680))

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
      onMoveRequested: function(dx, dy) { if (dx < 0 && root.svc) root.svc.up() }
      onTextKey: function(text) {
        if (!root.svc || !root.ready) return
        if (text === "u") root.svc.pickAndUpload(root.svc.path)
        else if (text === "r") root.svc.open(root.svc.path)
        else if (text === "w") Quickshell.execDetached(["xdg-open", root.webUrl])
      }

      // ---------- Title ----------
      Item {
        id: header
        width: parent.width
        implicitHeight: Math.max(title.implicitHeight, uploadButton.implicitHeight)

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

        Button {
          id: uploadButton
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          visible: root.ready
          text: "Upload"
          iconText: "󰅧"
          bordered: true
          foreground: root.fg
          fontFamily: root.fontFamily
          fontSize: Style.font.caption
          tooltipText: "Upload files here (u)"
          onClicked: root.svc.pickAndUpload(root.svc.path)
        }
      }

      Column {
        id: body
        anchors.top: header.bottom
        anchors.topMargin: Style.space(12)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        spacing: Style.space(10)

        // ---------- Not set up ----------
        Text {
          width: parent.width
          visible: !root.installed
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          text: "Proton's Drive CLI is not installed. Install it with:\nomarchy pkg aur add proton-drive-cli-git\nor get it from proton.me/download/drive/cli"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        Column {
          width: parent.width
          spacing: Style.space(10)
          visible: root.installed && !root.signedIn && !!root.svc && root.svc.statusLoaded

          Text {
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            text: root.svc && root.svc.signingIn
              ? "Finish signing in in your browser. This panel picks it up on its own."
              : "Sign in with your browser. Proton's CLI keeps the session in your keyring; no password is stored."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          Row {
            spacing: Style.space(6)

            Button {
              text: root.svc && root.svc.signingIn ? "Waiting…" : "Sign in"
              iconText: "󰍂"
              bordered: true
              enabled: !(root.svc && root.svc.signingIn)
              foreground: root.fg
              fontFamily: root.fontFamily
              onClicked: root.svc.signIn()
            }

            Button {
              visible: !!root.svc && root.svc.signingIn
              text: "Cancel"
              foreground: root.dim
              fontFamily: root.fontFamily
              onClicked: root.svc.cancelSignIn()
            }
          }
        }

        // ---------- Where we are ----------
        Item {
          width: parent.width
          height: Math.max(crumbRow.implicitHeight, refreshButton.height)
          visible: root.ready

          Row {
            id: crumbRow
            anchors.left: parent.left
            anchors.right: refreshButton.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)
            clip: true

            PanelActionButton {
              anchors.verticalCenter: parent.verticalCenter
              visible: root.crumbs.length > 1
              iconText: "󰁍"
              fontSize: Style.font.body
              size: Style.space(22)
              tooltipText: "Up (h)"
              foreground: root.dim
              fontFamily: root.fontFamily
              onClicked: root.svc.up()
            }

            Repeater {
              model: root.crumbs

              Row {
                id: crumb
                required property var modelData
                required property int index
                readonly property bool last: index === root.crumbs.length - 1
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  visible: crumb.index > 0
                  text: "/"
                  color: root.faint
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: crumb.modelData
                  color: crumb.last ? root.fg : (crumbMouse.containsMouse ? Color.accent : root.dim)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: crumb.last

                  MouseArea {
                    id: crumbMouse
                    anchors.fill: parent
                    enabled: !crumb.last
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.goToCrumb(crumb.index)
                  }
                }
              }
            }
          }

          PanelActionButton {
            id: refreshButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            iconText: "󰑐"
            fontSize: Style.font.body
            size: Style.space(22)
            tooltipText: "Refresh (r)"
            foreground: root.dim
            fontFamily: root.fontFamily
            onClicked: root.svc.open(root.svc.path)
          }
        }

        // ---------- The folder ----------
        Item {
          width: parent.width
          height: Math.min(Math.max(list.contentHeight, Style.space(70)), Style.space(380))
          visible: root.ready

          Text {
            anchors.centerIn: parent
            visible: list.count === 0
            textFormat: Text.PlainText
            text: root.svc && root.svc.listing ? "Loading…"
              : (root.svc && root.svc.listError !== "" ? root.svc.listError : "This folder is empty")
            color: root.svc && root.svc.listError !== "" ? Color.urgent : root.faint
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
          }

          ListView {
            id: list
            anchors.fill: parent
            clip: true
            spacing: Style.space(2)
            boundsBehavior: Flickable.StopAtBounds
            model: root.svc ? root.svc.items : []
            opacity: root.svc && root.svc.listing ? 0.5 : 1
            ScrollBar.vertical: ScrollBar { policy: list.contentHeight > list.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }

            delegate: ItemRow {
              required property var modelData
              item: modelData
              width: list.width
            }
          }
        }

        // ---------- Transfers and messages ----------
        Text {
          width: parent.width
          visible: root.transferring
          textFormat: Text.PlainText
          elide: Text.ElideRight
          text: root.current
            ? (root.current.kind === "upload" ? "󰅧  Uploading " : "󰅢  Downloading ") + root.current.label + "…"
              + (root.svc.queue.length > 0 ? "  (+" + root.svc.queue.length + " waiting)" : "")
            : ""
          color: Color.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          width: parent.width
          visible: !!root.svc && root.svc.flash !== ""
          textFormat: Text.PlainText
          text: root.svc ? "󰄬  " + root.svc.flash : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          width: parent.width
          visible: !!root.svc && root.svc.lastError !== ""
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          maximumLineCount: 4
          elide: Text.ElideRight
          text: root.svc ? root.svc.lastError : ""
          color: Color.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        // ---------- Footer ----------
        PanelSeparator { visible: root.ready; foreground: root.fg }

        Item {
          width: parent.width
          height: Math.max(usageLabel.implicitHeight, footerLinks.implicitHeight)
          visible: root.ready

          Text {
            id: usageLabel
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: !root.svc ? ""
              : root.svc.sizing ? "Adding up My files…"
              : root.svc.usage.ok ? root.svc.size(root.svc.usage.size) + " in " + root.svc.usage.items + " items"
              : ""
            color: root.faint
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Row {
            id: footerLinks
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)

            LinkButton {
              visible: !!root.svc && !root.svc.sizing && !root.svc.usage.ok
              text: "Size"
              iconText: "󰋊"
              tooltipText: "Add up what My files holds (can take a while)"
              onClicked: root.svc.measure()
            }

            LinkButton {
              text: "Web"
              iconText: "󰖟"
              tooltipText: "Open Proton Drive in the browser (w)"
              onClicked: {
                Quickshell.execDetached(["xdg-open", root.webUrl])
                root.close()
              }
            }

            LinkButton {
              text: "Sign out"
              iconText: "󰍃"
              onClicked: root.svc.signOut()
            }
          }
        }
      }
    }
  }

  // A small text button for secondary actions.
  component LinkButton: Button {
    foreground: root.dim
    fontFamily: root.fontFamily
    fontSize: Style.font.caption
    iconSize: Style.font.caption
    verticalPadding: Style.spacing.xxs
    horizontalPadding: Style.spacing.sm
  }

  // One file or folder. Click a folder to open it, a file to download it;
  // the buttons on hover download (folders too) and copy a link.
  component ItemRow: Rectangle {
    id: row
    property var item: ({})

    height: Style.space(34)
    radius: Math.min(Style.cornerRadius, Style.space(6))
    color: rowHover.hovered ? Util.alpha(root.fg, 0.07) : "transparent"

    HoverHandler { id: rowHover }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        if (row.item.folder) root.svc.open(row.item.path)
        else root.svc.download(row.item)
      }
    }

    Text {
      id: rowIcon
      anchors.left: parent.left
      anchors.leftMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(20)
      textFormat: Text.PlainText
      text: root.iconFor(row.item)
      color: row.item.folder ? Color.accent : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    Text {
      anchors.left: rowIcon.right
      anchors.leftMargin: Style.space(6)
      anchors.right: meta.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: row.item.name + (row.item.shared ? "  󰌷" : "")
      color: root.fg
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      elide: Text.ElideMiddle
    }

    Text {
      id: meta
      anchors.right: actions.left
      anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      visible: !rowHover.hovered
      textFormat: Text.PlainText
      text: (row.item.folder ? "" : root.svc.size(row.item.size) + "  ") + root.dateLabel(row.item.modified)
      color: root.faint
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Row {
      id: actions
      anchors.right: parent.right
      anchors.rightMargin: Style.space(4)
      anchors.verticalCenter: parent.verticalCenter
      visible: rowHover.hovered
      width: visible ? implicitWidth : 0
      spacing: Style.space(2)

      PanelActionButton {
        iconText: "󰇚"
        fontSize: Style.font.body
        size: Style.space(24)
        tooltipText: "Download to " + root.setting("downloadDir", "~/Downloads")
        foreground: root.dim
        fontFamily: root.fontFamily
        onClicked: root.svc.download(row.item)
      }

      PanelActionButton {
        iconText: "󰌷"
        fontSize: Style.font.body
        size: Style.space(24)
        tooltipText: row.item.shared ? "Copy its link" : "Make a public link and copy it"
        foreground: root.dim
        fontFamily: root.fontFamily
        onClicked: root.svc.copyLink(row.item)
      }
    }
  }
}
