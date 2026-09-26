import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

// Joystick section: connected gamepads/joysticks. There is no "installed"
// concept here — Linux exposes them as kernel hotplug devices, so plugging
// one in is all it takes; this page just lists what is present.
Item {
  id: root

  property var bar: null
  property var sticks: []
  property bool configOpen: false
  property string configNode: ""
  property string configName: ""
  property string configVid: ""
  property string configPid: ""
  // True while the configurator window is up (Settings yields to it).
  readonly property bool configuring: configWindow.open

  function focusSearch() {}

  function refresh() {
    if (scanProc.running) return
    scanProc.collected = ""
    scanProc.running = true
  }

  function configure(row) {
    if (!row || !row.node) return
    var vidpid = String(row.vidpid || "").split(":")
    root.configNode = String(row.node)
    root.configName = String(row.label || row.node)
    root.configVid = vidpid.length > 0 ? vidpid[0] : ""
    root.configPid = vidpid.length > 1 ? vidpid[1] : ""
    root.configOpen = true
  }

  JoystickConfig {
    id: configWindow
    open: root.configOpen
    bar: root.bar
    pluginDir: String(Qt.resolvedUrl("joybind.py")).replace(/^file:\/\//, "").replace(/\/joybind\.py$/, "")
    deviceNode: root.configNode
    deviceName: root.configName
    deviceVid: root.configVid
    devicePid: root.configPid
    onRequestClose: root.configOpen = false
  }

  // `for js in /dev/input/js*` with node, name, USB vid:pid + strings.
  // device is a symlink: resolve it before walking up to the USB device.
  function applyScan() {
    var rows = []
    var lines = scanProc.collected.split("\n")
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (line.indexOf("JS:") !== 0) continue
      var parts = line.substring(3).split("|")
      if (parts.length < 2) continue
      var detail = []
      if (parts[0]) detail.push(parts[0])
      if (parts[2] && parts[2] !== ":") detail.push(parts[2])
      if (parts[4]) detail.push(parts[4])
      else if (parts[3]) detail.push(parts[3])
      rows.push({ node: parts[0], label: parts[1] || parts[0], detail: detail.join("  ·  "), vidpid: parts[2] || "" })
    }
    root.sticks = rows
  }

  Process {
    id: scanProc
    property string collected: ""
    command: ["bash", "-lc", "for js in /dev/input/js*; do [ -e \"$js\" ] || continue; dev=$(basename \"$js\"); name=$(tr -d '\\0' < /sys/class/input/$dev/device/name 2>/dev/null | xargs); d=$(readlink -f /sys/class/input/$dev/device); vid=''; pid=''; mfg=''; prod=''; for i in $(seq 1 8); do if [ -f \"$d/idVendor\" ]; then vid=$(cat \"$d/idVendor\"); pid=$(cat \"$d/idProduct\"); mfg=$(cat \"$d/manufacturer\" 2>/dev/null | xargs); prod=$(cat \"$d/product\" 2>/dev/null | xargs); break; fi; d=$(dirname \"$d\"); done; echo \"JS:$js|$name|$vid:$pid|$mfg|$prod\"; done"]
    stdout: SplitParser {
      onRead: function(data) { scanProc.collected += data + "\n" }
    }
    onExited: root.applyScan()
  }

  Component.onCompleted: root.refresh()

  Column {
    anchors.fill: parent
    spacing: Style.space(10)

    Row {
      width: parent.width
      spacing: Style.space(8)

      Text {
        width: parent.width - refreshButton.width - Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "Joysticks"
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.heading
        font.weight: Font.Medium
      }

      Button {
        id: refreshButton
        text: "Refresh"
        bordered: true
        onClicked: root.refresh()
      }
    }

    Flickable {
      width: parent.width
      height: parent.height - Style.space(10)
      contentWidth: width
      contentHeight: sticksCol.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height

      Column {
        id: sticksCol
        width: parent.width
        spacing: Style.space(6)

        Repeater {
          model: root.sticks
          delegate: BorderSurface {
            required property var modelData
            width: sticksCol.width
            height: Math.max(Style.space(44), stickLabel.implicitHeight + Style.space(14))
            radius: Style.cornerRadius
            color: "transparent"
            borderSpec: Border.controlSpec("normal", Color.foreground, Color.accent)

            Text {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(36)
              horizontalAlignment: Text.AlignHCenter
              textFormat: Text.PlainText
              text: "\uf11b"
              color: Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.iconLarge
            }

            Column {
              id: stickLabel
              anchors.left: parent.left
              anchors.right: configButton.left
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(36)
              anchors.rightMargin: Style.space(8)
              spacing: 2

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: modelData.label
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.weight: Font.Medium
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                visible: (modelData.detail || "") !== ""
                textFormat: Text.PlainText
                text: modelData.detail || ""
                color: Color.foreground
                opacity: 0.55
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }

            Button {
              id: configButton
              anchors.right: parent.right
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              text: "Configure"
              bordered: true
              onClicked: root.configure(modelData)
            }
          }
        }

        Text {
          visible: root.sticks.length === 0
          width: parent.width
          textFormat: Text.PlainText
          text: "No joysticks connected. Plug one in — nothing to install."
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
