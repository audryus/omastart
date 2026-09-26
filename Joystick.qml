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
    root.configKey = String(row.key || "")
    root.configNode = String(row.node)
    root.configName = String(row.label || row.node)
    root.configVid = vidpid.length > 0 ? vidpid[0] : ""
    root.configPid = vidpid.length > 1 ? vidpid[1] : ""
    root.configOpen = true
  }

  // ---- identities (labels + presets), kept in joysticks.json ---------
  readonly property string storePath: fsPluginDir + "/joysticks.json"
  readonly property string fsPluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/$/, "")

  property var identities: ({})
  property string configKey: ""

  readonly property var presetShort: ({
    megadrive: "Mega", n64: "N64", playstation: "PS",
    snes: "SNES", steam: "Steam", xbox: "Xbox"
  })

  function identityFor(key) {
    if (!key) return null
    var entry = root.identities[key]
    return entry ? entry : null
  }

  function displayLabel(row) {
    var entry = root.identityFor(row.key)
    if (entry && entry.label) return entry.label
    return row.label
  }

  function displayPreset(row) {
    var entry = root.identityFor(row.key)
    if (entry && entry.preset && root.presetShort[entry.preset]) return root.presetShort[entry.preset]
    return ""
  }

  function setLabel(key, label) {
    if (!key) return
    var next = {}
    for (var k in root.identities) next[k] = root.identities[k]
    var entry = next[key] || {}
    entry.label = String(label || "")
    next[key] = entry
    root.identities = next
    root.saveIdentities()
  }

  function setPreset(key, presetId) {
    if (!key) return
    var next = {}
    for (var k in root.identities) next[k] = root.identities[k]
    var entry = next[key] || {}
    entry.preset = String(presetId || "")
    next[key] = entry
    root.identities = next
    root.saveIdentities()
  }

  function saveIdentities() {
    Util.execDetached("printf '%s' " + Util.shellQuote(JSON.stringify(root.identities))
      + " > " + Util.shellQuote(root.storePath))
  }

  function loadIdentities(text) {
    var next = ({})
    try {
      var parsed = JSON.parse(String(text || ""))
      if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) next = parsed
    } catch (e) { }
    root.identities = next
  }

  FileView {
    id: identitiesFile
    path: root.storePath
    watchChanges: true
    printErrors: false
    onLoaded: root.loadIdentities(text())
    onLoadFailed: root.identities = ({})
    onFileChanged: reload()
  }

  JoystickConfig {
    id: configWindow
    open: root.configOpen
    bar: root.bar
    store: root
    stickKey: root.configKey
    pluginDir: String(Qt.resolvedUrl("joybind.py")).replace(/^file:\/\//, "").replace(/\/joybind\.py$/, "")
    deviceNode: root.configNode
    deviceName: root.configName
    deviceVid: root.configVid
    devicePid: root.configPid
    onRequestClose: root.configOpen = false
  }

  // `for js in /dev/input/js*` with node, name, USB vid:pid + strings.
  // device is a symlink: resolve it before walking up to the USB device.
  // Best identity available wins: USB serial (unique per unit, survives
  // anything), else vid:pid@iface + deterministic #n among identical
  // units in the same scan (these clones carry no serials, and twin
  // units share vid:pid AND interface on separate plugs), else phys,
  // else bare vid:pid.
  function stickBaseKey(vidpid, iface, serial, phys) {
    var cleanSerial = String(serial || "").replace(/\s+/g, "")
    if (vidpid && vidpid !== ":" && cleanSerial) return "usb:" + vidpid + "#" + cleanSerial
    if (vidpid && vidpid !== ":" && iface) return "usb:" + vidpid + "@if" + iface
    if (phys) return "phys:" + phys.replace(/\s+/g, " ")
    if (vidpid && vidpid !== ":") return "usb:" + vidpid
    return ""
  }

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
      rows.push({
        node: parts[0],
        label: parts[1] || parts[0],
        detail: detail.join("  ·  "),
        vidpid: parts[2] || "",
        baseKey: root.stickBaseKey(parts[2] || "", parts[5] || "", parts[7] || "", parts[6] || "")
      })
    }
    // Deterministic numbering for identical units (sorted by node).
    rows.sort(function(a, b) { return a.node < b.node ? -1 : (a.node > b.node ? 1 : 0) })
    var seen = {}
    for (var j = 0; j < rows.length; j++) {
      var base = rows[j].baseKey || ("node:" + rows[j].node)
      seen[base] = (seen[base] || 0) + 1
      rows[j].key = seen[base] > 1 ? (base + "#" + seen[base]) : base
    }
    root.sticks = rows
  }

  Process {
    id: scanProc
    property string collected: ""
    command: ["bash", "-lc", "for js in /dev/input/js*; do [ -e \"$js\" ] || continue; dev=$(basename \"$js\"); base=/sys/class/input/$dev/device; name=$(tr -d '\\0' < $base/name 2>/dev/null | xargs); d=$(readlink -f $base); vid=''; pid=''; mfg=''; prod=''; iface=''; serial=''; phys=''; child=''; for i in $(seq 1 8); do if [ -f \"$d/idVendor\" ]; then vid=$(cat \"$d/idVendor\"); pid=$(cat \"$d/idProduct\"); mfg=$(cat \"$d/manufacturer\" 2>/dev/null | xargs); prod=$(cat \"$d/product\" 2>/dev/null | xargs); serial=$(cat \"$d/serial\" 2>/dev/null | xargs); iface=$(basename \"$child\" | sed 's/.*://'); break; fi; child=\"$d\"; d=$(dirname \"$d\"); done; if [ -z \"$iface\" ]; then phys=$(tr -d '\\0' < $base/phys 2>/dev/null | xargs); fi; echo \"JS:$js|$name|$vid:$pid|$mfg|$prod|$iface|$phys|$serial\"; done"]
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
                text: root.displayLabel(modelData)
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.weight: Font.Medium
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: root.displayPreset(modelData) || "not configured yet"
                color: root.displayPreset(modelData) ? Color.accent : Color.foreground
                opacity: root.displayPreset(modelData) ? 1.0 : 0.55
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.weight: root.displayPreset(modelData) ? Font.Medium : Font.Normal
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
