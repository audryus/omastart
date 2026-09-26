import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Network printer discovery window: lists printers found on the network
// that are NOT installed yet, each with an Install button (not wired yet).
// No X here: outside click or Esc closes.
Item {
  id: root

  property bool open: false
  property var installed: []

  signal requestClose()

  property var found: []
  property bool scanning: false

  function refresh() {
    if (scanProc.running) return
    root.scanning = true
    root.found = []
    scanProc.collected = ""
    scanProc.running = true
  }

  function installedUris() {
    var set = {}
    var list = Array.isArray(root.installed) ? root.installed : []
    for (var i = 0; i < list.length; i++) {
      if (list[i].uri) set[String(list[i].uri)] = true
      if (list[i].name) set["name:" + String(list[i].name)] = true
    }
    return set
  }

  // `driverless list` prints one printer per line: a URI followed by quoted
  // metadata, e.g. `ipp://host/ipp/print "Model Name" "Make" ...`.
  function applyScan() {
    var known = root.installedUris()
    var rows = []
    var lines = scanProc.collected.split("\n")
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (!line) continue
      var uri = line.split(/\s+/)[0]
      if (uri.indexOf("ipp://") !== 0 && uri.indexOf("ipps://") !== 0) continue
      var name = ""
      var quoted = line.match(/"([^"]*)"/)
      if (quoted) name = quoted[1]
      if (!name) name = uri
      if (known[uri] || known["name:" + name]) continue
      rows.push({ name: name, uri: uri })
    }
    root.found = rows
    root.scanning = false
  }

  Process {
    id: scanProc
    property string collected: ""
    command: ["bash", "-lc", "driverless list 2>/dev/null"]
    stdout: SplitParser {
      onRead: function(data) { scanProc.collected += data + "\n" }
    }
    onExited: root.applyScan()
  }

  PanelWindow {
    id: window
    visible: root.open
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "audryus-printer-discovery"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    onVisibleChanged: {
      if (visible) Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    }

    // Click outside closes.
    MouseArea {
      anchors.fill: parent
      onClicked: root.requestClose()
    }

    BorderSurface {
      id: card
      width: Math.min(Style.space(520), window.width - Style.gapsOut * 2)
      height: Math.min(Style.space(420), window.height - Style.gapsOut * 2)
      anchors.centerIn: parent
      color: Color.popups.background
      borderSpec: Border.localOrSurfaceSpec("popups", "border", Color.popups.border, Color.popups.border, Math.max(1, Style.space(2)))
      padding: Style.spacing.popupPadding
      radius: Style.cornerRadius

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: root.requestClose()
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: Style.space(10)

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "Network printers" + (root.scanning ? " — scanning…" : " — " + foundList.count + " found")
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.heading
          font.weight: Font.Medium
          elide: Text.ElideRight
        }

        ListView {
          id: foundList
          width: parent.width
          height: parent.height - Style.space(10) - Style.font.heading - Style.space(8)
          clip: true
          spacing: Style.space(6)
          model: root.found
          boundsBehavior: Flickable.StopAtBounds

          delegate: BorderSurface {
            required property var modelData
            width: foundList.width
            height: Math.max(Style.space(44), foundLabel.implicitHeight + Style.space(14))
            radius: Style.cornerRadius
            color: "transparent"
            borderSpec: Border.controlSpec("normal", Color.foreground, Color.accent)

            Text {
              id: foundLabel
              anchors.left: parent.left
              anchors.right: installButton.left
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(8)
              textFormat: Text.PlainText
              text: modelData.name + "\n" + modelData.uri
              color: Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
              maximumLineCount: 2
            }

            Button {
              id: installButton
              anchors.right: parent.right
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              text: "Install"
              bordered: true
              // Not wired yet: install comes later.
              onClicked: console.log("[audryus.menu] install not implemented: " + modelData.uri)
            }
          }
        }

        Text {
          width: parent.width
          visible: !root.scanning && foundList.count === 0
          textFormat: Text.PlainText
          text: "No new printers found on the network."
          color: Color.foreground
          opacity: 0.55
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}
