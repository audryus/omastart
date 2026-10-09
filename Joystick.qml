import QtQuick
import Quickshell
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
  // True while a RetroArch install runs (Settings keeps yielding so the
  // polkit prompt stays usable).
  property bool installing: false

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
      cfgs.push({ path: parts[0], devices: parts[1].split("^"), vidpids: parts[2].split(","), ours: parts[3] === "1" })
    }
    var next = {}
    var rows = Array.isArray(root.sticks) ? root.sticks : []
    for (var j = 0; j < rows.length; j++) {
      var raw = ""
      try {
        var scanLines = scanProc.collected.split("\n")
        raw = root.rawForNode(scanLines, rows[j].node)
      } catch (e) { raw = "" }
      // Profiles carry decimal ids, the scan hex ones.
      var hex = String(rows[j].vidpid || "").split(":")
      var decVidpid = hex.length === 2 && hex[0] && hex[1]
        ? parseInt(hex[0], 16) + ":" + parseInt(hex[1], 16) : ""
      for (var k = 0; k < cfgs.length; k++) {
        if (cfgs[k].ours) continue
        var sameIds = decVidpid !== "" && cfgs[k].vidpids.indexOf(decVidpid) >= 0
        // Ours carries name + vid:pid, so only a profile matching both
        // can tie with it (name alone, e.g. the DS3 Bluez one, scores lower).
        var sameDevice = false
        for (var d = 0; d < cfgs[k].devices.length; d++) {
          var dev = cfgs[k].devices[d]
          var sameName = dev !== "" && (dev === raw || root.normDevice(dev) === root.normDevice(raw))
          if (sameName && (sameIds || decVidpid === "")) sameDevice = true
        }
        // Every tie counts: RetroArch picks one of them, not necessarily ours.
        if (sameDevice) next[rows[j].key] = (next[rows[j].key] || []).concat([cfgs[k].path])
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

  // "mv a a.bak && mv b b.bak…" for every stock profile tying with ours.
  function moveAsideCmd(key) {
    var paths = root.shadows[key] || []
    var parts = []
    for (var i = 0; i < paths.length; i++)
      parts.push("mv " + Util.shellQuote(paths[i]) + " " + Util.shellQuote(paths[i] + ".bak"))
    return parts.join(" && ")
  }

  function fixShadow(key) {
    var cmd = root.moveAsideCmd(key)
    if (!cmd) return
    // pkexec prompt; package updates may restore the files later.
    Util.execDetached("pkexec sh -c " + Util.shellQuote(cmd))
    Qt.callLater(root.scanShadows, 3000)
  }

  Process {
    id: shadowProc
    property string collected: ""
    // Primary + alt names and vid:pid pairs: the stock DS4 profile only
    // lists this pad (Sony Computer Entertainment…, 1356:1476) as alt3.
    // Names are "^"-joined (they may contain commas: "HORI CO.,LTD.").
    command: ["bash", "-lc", "for f in /usr/share/libretro/autoconfig/udev/*.cfg ~/.config/retroarch/autoconfig/udev/*.cfg; do [ -f \"$f\" ] || continue; devs=''; ids=''; for sfx in '' _alt1 _alt2 _alt3 _alt4 _alt5; do dev=$(grep -m1 -E \"^input_device$sfx[[:space:]]*=\" \"$f\" 2>/dev/null | sed 's/^[^=]*=[[:space:]]*\"\\(.*\\)\".*$/\\1/'); [ -n \"$dev\" ] && devs=\"$devs^$dev\"; vid=$(grep -m1 -E \"^input_vendor_id$sfx[[:space:]]*=\" \"$f\" 2>/dev/null | grep -o '[0-9][0-9]*' | tail -1); pid=$(grep -m1 -E \"^input_product_id$sfx[[:space:]]*=\" \"$f\" 2>/dev/null | grep -o '[0-9][0-9]*' | tail -1); [ -n \"$vid$pid\" ] && ids=\"$ids,$vid:$pid\"; done; ours=$(grep -qm1 'OmaStart' \"$f\" 2>/dev/null && echo 1 || echo 0); echo \"CFG:$f|${devs#^}|${ids#,}|$ours\"; done"]
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
    gameboy: "GB", gba: "GBA", megadrive: "Mega", n64: "N64", nds: "NDS", playstation: "PS",
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

  readonly property string retroarchCfgPath: Quickshell.env("HOME") + "/.config/retroarch/retroarch.cfg"

  // Install this stick's local profile as THE RetroArch profile for the
  // device (pkexec prompt): for identical twins sharing one kernel name,
  // the last one modeled wins for both.
  // Per-player joypad binds in retroarch.cfg (set from RetroArch's own
  // menu) beat any autoconfig profile, so they are reset to "nul". That
  // only sticks with RetroArch closed: it rewrites the file on exit.
  function makeModel(row) {
    if (!row || installProc.running) return
    var src = root.fsPluginDir + "/autoconfig/" + root.sanitizeFile(root.displayLabel(row)) + ".cfg"
    var dest = "/usr/share/libretro/autoconfig/udev/" + root.sanitizeFile(row.label) + ".cfg"
    // Stock profiles with our name + vid:pid tie with ours and RetroArch
    // may load theirs (seen: "Generic USB Gamepad" beat "OmaStart USB
    // gamepad"), so they go aside in the same polkit prompt.
    var rootCmd = "cp " + Util.shellQuote(src) + " " + Util.shellQuote(dest)
    var aside = root.moveAsideCmd(row.key)
    if (aside) rootCmd += " && " + aside
    installProc.command = ["bash", "-lc",
      "if pgrep -x retroarch >/dev/null; then notify-send 'OmaStart' 'Close RetroArch before setting the controller.'; exit 3; fi"
      + " && pkexec sh -c " + Util.shellQuote(rootCmd)
      + " && sed -i -E 's/^(input_player[0-9]+_[a-z0-9_]+_(btn|axis)) = \".*\"$/\\1 = \"nul\"/' "
      + Util.shellQuote(root.retroarchCfgPath)
      + " && notify-send 'OmaStart' " + Util.shellQuote(root.displayLabel(row) + " installed for RetroArch.")]
    root.installing = true
    installProc.running = true
  }

  Process {
    id: installProc
    onExited: {
      root.installing = false
      root.scanShadows()
    }
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
                  text: "Set Retroarch Controller"
                  bordered: true
                  onClicked: root.makeModel(modelData)

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                    PanelToolTip {
                      visible: parent.containsMouse
                      text: "Install this stick's profile for RetroArch and reset retroarch.cfg's per-player binds so it wins. Close RetroArch first."
                    }
                  }
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
                      text: "Stock profiles tie with ours and RetroArch may load theirs. Click to move them aside (.bak); Set Retroarch Controller also does it."
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
