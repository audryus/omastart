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
    root.scanShadows()
  }

  // ---- stock-profile shadowing -------------------------------------
  // A same-name/vidpid .cfg elsewhere (e.g. the padded stock profile)
  // outscores ours, so RetroArch silently ignores our file. Ours carry
  // an "OmaStart" display_name marker and are excluded from the check.
  property var shadows: ({})

  function normDevice(value) {
    return String(value || "").toLowerCase().replace(/\s+/g, " ").replace(/^ +| +$/g, "")
  }

  function scanShadows() {
    if (shadowProc.running) return
    shadowProc.collected = ""
    shadowProc.running = true
  }

  function applyShadows() {
    var cfgs = []
    var lines = shadowProc.collected.split("\n")
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i]
      if (line.indexOf("CFG:") !== 0) continue
      var parts = line.substring(4).split("|")
      if (parts.length < 4) continue
      cfgs.push({ path: parts[0], device: parts[1], vidpid: parts[2], ours: parts[3] === "1" })
    }
    var next = {}
    var rows = Array.isArray(root.sticks) ? root.sticks : []
    for (var j = 0; j < rows.length; j++) {
      var raw = ""
      try {
        var scanLines = scanProc.collected.split("\n")
        raw = root.rawForNode(scanLines, rows[j].node)
      } catch (e) { raw = "" }
      for (var k = 0; k < cfgs.length; k++) {
        if (cfgs[k].ours) continue
        var sameDevice = cfgs[k].device !== "" && (cfgs[k].device === raw
          || (root.normDevice(cfgs[k].device) === root.normDevice(raw)
            && cfgs[k].vidpid === rows[j].vidpid && rows[j].vidpid !== "" && rows[j].vidpid !== ":"))
        if (sameDevice) { next[rows[j].key] = cfgs[k].path; break }
      }
    }
    root.shadows = next
  }

  // Exact raw kernel name for a js node, from the last stick scan.
  function rawForNode(scanLines, node) {
    for (var i = 0; i < scanLines.length; i++) {
      var line = scanLines[i].trim()
      if (line.indexOf("JS:") !== 0) continue
      var parts = line.substring(3).split("|")
      if (parts[0] === node) return parts[7] || ""
    }
    return ""
  }

  function fixShadow(key) {
    var path = root.shadows[key]
    if (!path) return
    // pkexec prompt; package updates may restore the file later.
    Util.execDetached("pkexec mv " + Util.shellQuote(path) + " " + Util.shellQuote(path + ".bak"))
    Qt.callLater(root.scanShadows, 3000)
  }

  Process {
    id: shadowProc
    property string collected: ""
    command: ["bash", "-lc", "for f in /usr/share/libretro/autoconfig/udev/*.cfg ~/.config/retroarch/autoconfig/udev/*.cfg; do [ -f \"$f\" ] || continue; dev=$(grep -m1 -E '^input_device[[:space:]]*=' \"$f\" 2>/dev/null | sed 's/^[^=]*=[[:space:]]*\"\\(.*\\)\".*$/\\1/'); vid=$(grep -m1 -E '^input_vendor_id[[:space:]]*=' \"$f\" 2>/dev/null | grep -o '[0-9][0-9]*' | head -1); pid=$(grep -m1 -E '^input_product_id[[:space:]]*=' \"$f\" 2>/dev/null | grep -o '[0-9][0-9]*' | head -1); ours=$(grep -qm1 'OmaStart' \"$f\" 2>/dev/null && echo 1 || echo 0); echo \"CFG:$f|$dev|$vid:$pid|$ours\"; done"]
    stdout: SplitParser {
      onRead: function(data) { shadowProc.collected += data + "\n" }
    }
    onExited: root.applyShadows()
  }

  property string configRawName: ""

  function configure(row) {
    if (!row || !row.node) return
    var vidpid = String(row.vidpid || "").split(":")
    root.configNode = String(row.node)
    root.configKey = String(row.key || "")
    root.configRawName = String(row.rawname || row.label || row.node)
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

  function sanitizeFile(value) {
    var s = String(value || "joystick").trim().replace(/[\/\\]/g, "_")
    return s || "joystick"
  }

  // Install this stick's local profile as THE RetroArch profile for the
  // device (pkexec prompt): for identical twins sharing one kernel name,
  // the last one modeled wins for both.
  function makeModel(row) {
    if (!row) return
    var src = root.fsPluginDir + "/autoconfig/" + root.sanitizeFile(root.displayLabel(row)) + ".cfg"
    var dest = "/usr/share/libretro/autoconfig/udev/" + root.sanitizeFile(row.label) + ".cfg"
    Util.execDetached("pkexec cp " + Util.shellQuote(src) + " " + Util.shellQuote(dest))
    Qt.callLater(root.scanShadows, 3000)
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
    deviceRawName: root.configRawName
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
        rawname: parts[7] || "",
        baseKey: root.stickBaseKey(parts[2] || "", parts[5] || "", parts[8] || "", parts[6] || "")
      })
    }
    // Shadow data needs fresh stick rows; the shadow scan may have won
    // the race with empty hands, so run it again now (cheap, local).
    root.scanShadows()
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
    command: ["bash", "-lc", "for js in /dev/input/js*; do [ -e \"$js\" ] || continue; dev=$(basename \"$js\"); base=/sys/class/input/$dev/device; raw=$(tr -d '\\0\\n' < $base/name 2>/dev/null); name=$(echo \"$raw\" | xargs); d=$(readlink -f $base); vid=''; pid=''; mfg=''; prod=''; iface=''; serial=''; phys=''; child=''; for i in $(seq 1 8); do if [ -f \"$d/idVendor\" ]; then vid=$(cat \"$d/idVendor\"); pid=$(cat \"$d/idProduct\"); mfg=$(cat \"$d/manufacturer\" 2>/dev/null | xargs); prod=$(cat \"$d/product\" 2>/dev/null | xargs); serial=$(cat \"$d/serial\" 2>/dev/null | xargs); iface=$(basename \"$child\" | sed 's/.*://'); break; fi; child=\"$d\"; d=$(dirname \"$d\"); done; if [ -z \"$iface\" ]; then phys=$(tr -d '\\0' < $base/phys 2>/dev/null | xargs); fi; echo \"JS:$js|$name|$vid:$pid|$mfg|$prod|$iface|$phys|$raw|$serial\"; done"]
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
            readonly property bool hasPreset: root.displayPreset(modelData) !== ""
            readonly property bool shadowed: !!root.shadows[modelData.key]
            width: sticksCol.width
            height: stickCard.implicitHeight + Style.space(16)
            radius: Style.cornerRadius
            color: "transparent"
            borderSpec: Border.controlSpec("normal", Color.foreground, Color.accent)

            Column {
              id: stickCard
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(10)
              spacing: Style.space(8)

              Row {
                width: parent.width
                spacing: Style.space(4)

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(30)
                  horizontalAlignment: Text.AlignHCenter
                  textFormat: Text.PlainText
                  text: "\uf11b"
                  color: Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.iconLarge
                }

                Column {
                  width: parent.width - Style.space(30) - Style.space(4)
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
              }

              Row {
                width: parent.width
                spacing: Style.space(8)

                Button {
                  text: "Configure"
                  bordered: true
                  onClicked: root.configure(modelData)
                }

                Button {
                  visible: hasPreset
                  text: "Model"
                  bordered: true
                  onClicked: root.makeModel(modelData)
                }

                Button {
                  visible: shadowed
                  text: "Fix stock"
                  bordered: true
                  onClicked: root.fixShadow(modelData.key)

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                    PanelToolTip {
                      visible: parent.containsMouse
                      text: "A stock profile shadows ours and RetroArch ignores it. Click to move it aside (.bak)."
                    }
                  }
                }
              }
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
