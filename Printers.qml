import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Printers section: installed CUPS printers plus network discovery.
// Discovery opens its own window (outside click / Esc closes, no X);
// install buttons are listed but not wired yet.
Item {
  id: root

  property var installed: []
  property bool discoveryOpen: false

  function refreshInstalled() {
    if (!installedProc.running) {
      installedProc.collected = ""
      installedProc.running = true
    }
  }

  // `lpstat -p` lines look like: `printer NAME is idle. enabled since ...`
  // `lpstat -v` lines look like: `device for NAME: URI`
  // `lpstat -d` line looks like: `system default destination: NAME`
  function applyInstalled() {
    var uris = {}
    var states = []
    var fallback = "no system default destination"
    var lines = installedProc.collected.split("\n")
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      // CUPS names carry no spaces; \S+ avoids the greedy match eating
      // the colons inside ipp:// URIs.
      var mDev = line.match(/^device for (\S+):\s*(\S+)/)
      if (mDev) { uris[mDev[1]] = mDev[2]; continue }
      var mPr = line.match(/^printer (\S+)\s+(.*)$/)
      if (mPr) { states.push({ name: mPr[1], state: mPr[2] }); continue }
      var mDef = line.match(/destination:\s*(.+)$/)
      if (mDef) fallback = mDef[1].trim()
    }
    var rows = []
    for (var j = 0; j < states.length; j++) {
      rows.push({
        name: states[j].name,
        state: states[j].state,
        uri: uris[states[j].name] || "",
        isDefault: states[j].name === fallback
      })
    }
    root.installed = rows
  }

  Process {
    id: installedProc
    property string collected: ""
    command: ["bash", "-lc", "lpstat -p 2>/dev/null; lpstat -v 2>/dev/null; lpstat -d 2>/dev/null"]
    stdout: SplitParser {
      onRead: function(data) { installedProc.collected += data + "\n" }
    }
    onExited: root.applyInstalled()
  }

  Component.onCompleted: root.refreshInstalled()

  Column {
    anchors.fill: parent
    spacing: Style.space(10)

    Text {
      id: heading
      width: parent.width
      textFormat: Text.PlainText
      text: "Printers"
      color: Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.heading
      font.weight: Font.Medium
    }

    Button {
      id: findButton
      width: parent.width
      text: "Find network printers"
      bordered: true
      onClicked: {
        root.discoveryOpen = true
        discovery.refresh()
      }
    }

    Flickable {
      width: parent.width
      height: parent.height - heading.height - findButton.height - Style.space(10) * 2
      contentWidth: width
      contentHeight: installedCol.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height

      Column {
        id: installedCol
        width: parent.width
        spacing: Style.space(6)

        Repeater {
          model: root.installed
          delegate: BorderSurface {
            required property var modelData
            width: installedCol.width
            height: Math.max(Style.space(40), printerLabel.implicitHeight + Style.space(14))
            radius: Style.cornerRadius
            color: "transparent"
            borderSpec: Border.controlSpec("normal", Color.foreground, Color.accent)

            Column {
              id: printerLabel
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(10)
              spacing: 2

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: modelData.name + (modelData.isDefault ? "  ·  default" : "")
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.weight: Font.Medium
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                visible: (modelData.uri || modelData.state) !== ""
                textFormat: Text.PlainText
                text: [modelData.state, modelData.uri].filter(function(p) { return p }).join("  ·  ")
                color: Color.foreground
                opacity: 0.55
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }
          }
        }

        Text {
          visible: root.installed.length === 0
          width: parent.width
          textFormat: Text.PlainText
          text: "No printers installed."
          color: Color.foreground
          opacity: 0.55
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          wrapMode: Text.WordWrap
        }
      }
    }
  }

  // ---- Network discovery window (no X; outside click / Esc closes) ----
  Discovery {
    id: discovery
    open: root.discoveryOpen
    installed: root.installed
    onRequestClose: root.discoveryOpen = false
  }
}
