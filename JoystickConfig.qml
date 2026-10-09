import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Joystick configurator: preset schematics (presets/*.qml), guided key
// binding via joybind.py, and RetroArch autoconfig persistence under
// <plugin>/autoconfig/. Closes on Esc / X only (no outside-click close).
Item {
  id: root

  property bool open: false
  property var bar: null
  property var store: null
  property string stickKey: ""
  property string pluginDir: ""
  property string deviceNode: ""
  property string deviceName: ""
  // Exact kernel name (trailing spaces kept): RetroArch matches
  // input_device against EVIOCGNAME, and the stock profiles preserve
  // the padding — a trimmed name never matches.
  property string deviceRawName: ""
  property string deviceVid: ""
  property string devicePid: ""

  signal requestClose()

  readonly property string storedLabel: {
    if (!store || !stickKey) return String(root.deviceName || "").trim()
    var entry = store.identityFor(stickKey)
    if (entry && entry.label) return entry.label
    return String(root.deviceName || "").trim()
  }

  readonly property var presets: [
    { id: "gameboy", label: "Game Boy", file: "presets/GameBoy.qml" },
    { id: "gba", label: "GBA", file: "presets/GBA.qml" },
    { id: "megadrive", label: "Megadrive", file: "presets/Megadrive.qml" },
    { id: "n64", label: "N64", file: "presets/N64.qml" },
    { id: "nds", label: "NDS", file: "presets/NDS.qml" },
    { id: "playstation", label: "Playstation", file: "presets/Playstation.qml" },
    { id: "snes", label: "SNES", file: "presets/SNES.qml" },
    { id: "steam", label: "Steam", file: "presets/Steam.qml" },
    { id: "xbox", label: "Xbox", file: "presets/Xbox.qml" }
  ]
  property string presetId: "megadrive"
  readonly property var presetButtons: presetLoader.item ? presetLoader.item.buttons : []

  // key -> {kind: "btn"|"axis", value: "3"|"+2"}
  property var mapping: ({})
  property bool dirty: false
  property int bindIndex: -1
  property int bindToken: 0
  property string currentKey: ""
  property string status: ""

  readonly property string scriptPath: root.pluginDir + "/joybind.py"
  readonly property string cfgDir: root.pluginDir + "/autoconfig"

  // Local file carries the custom label (distinct per stick); the
  // installed copy must carry the kernel name or RetroArch never matches.
  function sanitizedName() {
    var s = String(root.storedLabel || root.deviceName || "joystick").trim().replace(/[\/\\]/g, "_")
    return s || "joystick"
  }

  function kernelFileName() {
    var s = String(root.deviceName || "joystick").trim().replace(/[\/\\]/g, "_")
    return s || "joystick"
  }

  function cfgPath() {
    return root.cfgDir + "/" + root.sanitizedName() + ".cfg"
  }

  function hexDec(value) {
    var n = parseInt(String(value || ""), 16)
    return isFinite(n) ? String(n) : ""
  }

  function targets() {
    return Array.isArray(root.presetButtons) ? root.presetButtons : []
  }

  // Bound keys the current preset owns. The mapping can hold others: the
  // prefill loads whatever the file had (e.g. SNES Select/X saved from
  // another preset for the same stick), and they would otherwise be
  // written back unseen — and the N64 core remap turns Select into
  // C-Down, so a stale Select on the Z button fired both.
  function presetKeys() {
    var owned = {}
    var list = root.targets()
    for (var i = 0; i < list.length; i++) owned[list[i].key] = true
    var keys = []
    for (var k in root.mapping) {
      if (owned[k] && root.mapping[k]) keys.push(k)
    }
    keys.sort()
    return keys
  }

  function bindingText(key) {
    var m = root.mapping[key]
    if (!m) return "—"
    return m.kind === "axis" ? ("axis " + m.value) : ("btn " + m.value)
  }

  // ---- guided binding ----

  function bindAll() {
    var list = root.targets()
    if (list.length === 0) {
      root.status = "Preset failed to load — reopen the window."
      return
    }
    root.bindStep(0)
  }

  function bindOne(key) {
    var list = root.targets()
    for (var i = 0; i < list.length; i++) {
      if (list[i].key === key) { root.bindStep(i); return }
    }
  }

  function bindStep(i) {
    var list = root.targets()
    if (i < 0 || i >= list.length) { root.finishBinding(); return }
    if (!root.deviceNode) {
      root.status = "No device selected — reopen from Configure."
      root.bindIndex = -1
      root.currentKey = ""
      return
    }
    root.bindIndex = i
    root.bindToken += 1
    root.currentKey = list[i].key
    root.status = "Press " + list[i].label + " on the stick… (" + (i + 1) + "/" + list.length + ")"
    bindProc.command = ["python3", root.scriptPath, root.deviceNode]
    bindProc.collected = ""
    bindProc.running = true
  }

  function skipStep() {
    // Invalidate the in-flight run (its late exit is ignored by token)
    // and move on; the stale python exits on its next event harmlessly.
    root.bindToken += 1
    try { bindProc.running = false } catch (e) { }
    root.bindStep(root.bindIndex + 1)
  }

  function stopBinding(silent) {
    root.bindToken += 1
    try { bindProc.running = false } catch (e) { }
    root.bindIndex = -1
    root.currentKey = ""
    if (!silent) root.status = ""
  }

  function finishBinding() {
    root.bindIndex = -1
    root.currentKey = ""
    root.status = "Done — review and Save."
  }

  // Axis targets only accept their own direction (l_y_minus wants -N);
  // plain keys take buttons or either axis side.
  function directionOk(key, kind, value) {
    if (kind !== "axis") return true
    if (key.substring(key.length - 6) === "_minus") return value.charAt(0) === "-"
    if (key.substring(key.length - 5) === "_plus") return value.charAt(0) === "+"
    return true
  }

  function applyCapture(token, line) {
    if (token !== root.bindToken) return
    // "h0up": D-pad hats bind like buttons (udev profile syntax).
    var mBtn = line.match(/^BTN\s+(\d+|h\d+(?:up|down|left|right))/)
    var mAxis = line.match(/^AXIS\s*([+-]\d+)/)
    var list = root.targets()
    var key = root.currentKey
    if (!key) return
    if ((mBtn || mAxis) && !root.directionOk(key, mAxis ? "axis" : "btn", mAxis ? mAxis[1] : "")) {
      root.status = "Wrong direction — move the opposite way…"
      root.bindStep(root.bindIndex)
      return
    }
    if (mBtn) {
      var next = {}
      for (var k in root.mapping) next[k] = root.mapping[k]
      next[key] = { kind: "btn", value: mBtn[1] }
      root.mapping = next
      root.dirty = true
      root.bindStep(root.bindIndex + 1)
    } else if (mAxis) {
      var next2 = {}
      for (var k2 in root.mapping) next2[k2] = root.mapping[k2]
      next2[key] = { kind: "axis", value: mAxis[1] }
      root.mapping = next2
      root.dirty = true
      root.bindStep(root.bindIndex + 1)
    } else {
      // Empty/garbled run (timeout with everything held, or disconnect):
      // retry with a hint instead of spinning silently.
      root.bindStep(root.bindIndex)
      root.status += " — no input yet, release everything first."
    }
  }

  // ---- persistence (RetroArch autoconfig) ----

  // One retropad map per device: presets are just guides with familiar
  // labels for the same keys, so every bound key is written.
  function cfgText() {
    var lines = []
    lines.push("input_driver = \"udev\"")
    var exactName = String(root.deviceRawName || "")
    if (!exactName) exactName = String(root.deviceName || "").trim()
    lines.push("input_device = \"" + exactName + "\"")
    // Marker AND proof: the in-game OSD shows this when OUR profile wins.
    // Shadow detection also keys off it to tell our copies apart.
    var pretty = root.storedLabel || String(root.deviceName || "").trim()
    lines.push("input_device_display_name = \"OmaStart " + pretty + "\"")
    var vid = root.hexDec(root.deviceVid)
    var pid = root.hexDec(root.devicePid)
    if (vid) lines.push("input_vendor_id = \"" + vid + "\"")
    if (pid) lines.push("input_product_id = \"" + pid + "\"")
    lines.push("")
    var list = root.targets()
    var labels = {}
    for (var i = 0; i < list.length; i++) labels[list[i].key] = list[i].label
    var keys = root.presetKeys()
    for (var j = 0; j < keys.length; j++) {
      var m = root.mapping[keys[j]]
      if (!m) continue
      // Descriptors must carry the same _btn/_axis suffix as the mapping
      // (upstream README), otherwise RetroArch ignores the label.
      var suffix = m.kind === "axis" ? "_axis" : "_btn"
      lines.push("input_" + keys[j] + suffix + " = \"" + m.value + "\"")
      lines.push("input_" + keys[j] + suffix + "_label = \"" + (labels[keys[j]] || keys[j]) + "\"")
    }
    return lines.join("\n") + "\n"
  }

  function save() {
    if (!root.dirty || saveProc.running) return
    var dir = root.cfgDir
    var path = root.cfgPath()
    // Two-phase: temp file first so a stray quote can never truncate the
    // profile; then move into place. The core remap goes alongside.
    var cmd = "mkdir -p " + Util.shellQuote(dir)
      + " && printf '%s' " + Util.shellQuote(root.cfgText())
      + " > " + Util.shellQuote(dir + "/.tmp.cfg")
      + " && mv " + Util.shellQuote(dir + "/.tmp.cfg") + " " + Util.shellQuote(path)
    var remap = root.buildRemap()
    if (remap) {
      cmd += " && mkdir -p " + Util.shellQuote(root.remapDir())
        + " && printf '%s' " + Util.shellQuote(remap)
        + " > " + Util.shellQuote(root.remapPath)
    }
    saveProc.command = ["bash", "-lc", cmd]
    saveProc.running = true
  }

  function remapDir() {
    var path = root.remapPath
    var slash = path.lastIndexOf("/")
    return slash > 0 ? path.substring(0, slash) : Quickshell.env("HOME")
  }

  Process {
    id: saveProc
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.status = "Save failed (exit " + exitCode + ")."
        return
      }
      root.dirty = false
      if (root.store && root.stickKey) root.store.setPreset(root.stickKey, root.presetId)
      // Local save only (preset + core remap). RetroArch install happens
      // from the list's Set Retroarch Controller button.
      root.requestClose()
    }
  }

  Process {
    id: bindProc
    property string collected: ""
    stdout: SplitParser {
      onRead: function(data) { bindProc.collected += data + "\n" }
    }
    onExited: {
      var token = root.bindToken
      var lines = bindProc.collected.split("\n")
      // Echo the raw stream so the log shows what Linux delivered, then
      // honour only the BTN/AXIS result line (RAW lines are noise here).
      for (var r = 0; r < lines.length; r++) {
        if (lines[r].indexOf("RAW") === 0) console.log("[audryus.omastart] bind " + lines[r].trim())
      }
      var last = ""
      for (var i = lines.length - 1; i >= 0; i--) {
        var t = lines[i].trim()
        if (t.indexOf("BTN") === 0 || t.indexOf("AXIS") === 0) { last = t; break }
      }
      root.applyCapture(token, last)
    }
  }

  // Core remap per preset (presets without a core write none):
  // - n64: the user's hand-tuned template; our bound keys replace its
  //   input_player1_* lines, boilerplate (turbo etc.) is preserved. No
  //   template, no remap.
  // - playstation: the core's own remap, with port 1 set to DualShock —
  //   the default PS pad device has no sticks at all.
  readonly property string remapsDir: Quickshell.env("HOME") + "/.config/retroarch/config/remaps"
  readonly property string remapTemplatePath: {
    if (root.presetId === "n64") return root.remapsDir + "/Mupen64Plus-Next/tuyi.rmp.bak"
    if (root.presetId === "playstation") return root.remapsDir + "/Beetle PSX/Beetle PSX.rmp"
    return ""
  }
  readonly property string remapPath: {
    if (root.presetId === "n64") return root.remapsDir + "/Mupen64Plus-Next/Mupen64Plus-Next.rmp"
    if (root.presetId === "playstation") return root.remapsDir + "/Beetle PSX/Beetle PSX.rmp"
    return ""
  }
  property string remapTemplate: ""

  // RETRO_DEVICE_SUBCLASS(RETRO_DEVICE_ANALOG, 1): Beetle PSX's DualShock.
  readonly property string psxDualShock: "517"

  function buildRemap() {
    if (root.presetId === "playstation") return root.buildPsxRemap()
    if (root.presetId !== "n64" || !root.remapTemplate) return ""
    // Player btn/axis overrides come ONLY from our mapping (a stale line
    // pointing at a nonexistent button would silently kill that input,
    // which is what the dead 20-23 lines did); all other boilerplate
    // (turbo, analog_dpad_mode, ports…) is preserved as-is.
    // Duplicate keys (same physical button as another, e.g. N64 B filling
    // retropad A for menu nav) keep their identity: a template remap of
    // them (btn_a = "21", C-Left, from a pad whose C-buttons were face
    // buttons) would fire together with the original key.
    var dups = {}
    var list = root.targets()
    for (var t = 0; t < list.length; t++) {
      if (list[t].dupOf) dups[list[t].key] = true
    }
    var out = []
    var lines = root.remapTemplate.split("\n")
    for (var j = 0; j < lines.length; j++) {
      var hit = lines[j].match(/^input_player1_([a-z0-9_]+?)_(btn|axis)\s*=/)
      if (hit) continue
      var remapped = lines[j].match(/^input_player1_btn_([a-z0-9]+)\s*=/)
      if (remapped && dups[remapped[1]]) continue
      out.push(lines[j])
    }
    var keys = root.presetKeys()
    for (var l = 0; l < keys.length; l++) {
      var entry = root.mapping[keys[l]]
      if (!entry) continue
      if (entry.kind === "axis") out.push("input_player1_" + keys[l] + "_axis = \"" + entry.value + "\"")
      else out.push("input_player1_" + keys[l] + "_btn = \"" + entry.value + "\"")
    }
    return out.join("\n")
  }

  // Only the port-1 device changes; RetroArch fills in the rest if the
  // file is new.
  function buildPsxRemap() {
    var line = "input_libretro_device_p1 = \"" + root.psxDualShock + "\""
    var out = []
    var found = false
    var lines = root.remapTemplate ? root.remapTemplate.split("\n") : []
    for (var i = 0; i < lines.length; i++) {
      if (/^input_libretro_device_p1\s*=/.test(lines[i])) {
        out.push(line)
        found = true
      } else {
        out.push(lines[i])
      }
    }
    if (!found) out.unshift(line)
    return out.join("\n")
  }

  FileView {
    id: remapTemplateFile
    path: root.remapTemplatePath
    watchChanges: false
    printErrors: false
    onLoaded: root.remapTemplate = text()
    onLoadFailed: root.remapTemplate = ""
  }

  // Prefill from an existing profile for this stick, if any.
  FileView {
    id: cfgFile
    path: root.open ? root.cfgPath() : ""
    watchChanges: false
    printErrors: false
    onLoaded: {
      var next = {}
      var lines = String(text()).split("\n")
      for (var i = 0; i < lines.length; i++) {
        var m = lines[i].match(/^\s*input_(.+?)_(btn|axis)\s*=\s*"([^"]*)"/)
        if (m) next[m[1]] = { kind: m[2], value: m[3] }
      }
      root.mapping = next
      root.dirty = false
      // Numbers captured under another driver point at other buttons.
      var drv = String(text()).match(/^\s*input_driver\s*=\s*"([^"]*)"/m)
      if (drv && drv[1] !== "udev")
        root.status = "Profile made for " + drv[1] + "; RetroArch uses udev — Bind keys again."
      else
        root.status = "Loaded existing profile."
    }
  }

  // N64 analog tuning: core options have no per-profile equivalent.
  readonly property string coreOptPath: Quickshell.env("HOME") + "/.config/retroarch/config/Mupen64Plus-Next/Mupen64Plus-Next.opt"
  property int sensitivity: 100
  property int deadzone: 15
  property string coreOptText: ""

  function loadCoreOpts(text) {
    root.coreOptText = String(text || "")
    var mS = root.coreOptText.match(/^mupen64plus-astick-sensitivity\s*=\s*"(\d+)"/m)
    var mD = root.coreOptText.match(/^mupen64plus-astick-deadzone\s*=\s*"(\d+)"/m)
    if (mS) root.sensitivity = Number(mS[1])
    if (mD) root.deadzone = Number(mD[1])
  }

  function writeCoreOpts() {
    var lines = root.coreOptText.split("\n")
    var hasS = false, hasD = false
    for (var i = 0; i < lines.length; i++) {
      if (/^mupen64plus-astick-sensitivity\s*=/.test(lines[i])) {
        lines[i] = "mupen64plus-astick-sensitivity = \"" + root.sensitivity + "\""
        hasS = true
      } else if (/^mupen64plus-astick-deadzone\s*=/.test(lines[i])) {
        lines[i] = "mupen64plus-astick-deadzone = \"" + root.deadzone + "\""
        hasD = true
      }
    }
    if (!hasS) lines.push("mupen64plus-astick-sensitivity = \"" + root.sensitivity + "\"")
    if (!hasD) lines.push("mupen64plus-astick-deadzone = \"" + root.deadzone + "\"")
    // RetroArch rewrites this file on exit; last writer wins.
    Util.execDetached("printf '%s' " + Util.shellQuote(lines.join("\n"))
      + " > " + Util.shellQuote(root.coreOptPath))
  }

  FileView {
    id: coreOptFile
    path: root.coreOptPath
    watchChanges: false
    printErrors: false
    onLoaded: root.loadCoreOpts(text())
  }

  // PSX DualShock analog mode (Beetle PSX core option). Real DualShocks
  // boot DIGITAL, where games ignore the sticks until the Analog button;
  // the combo (L1+R1+Select by default) stands in for that button.
  readonly property string psxOptPath: Quickshell.env("HOME") + "/.config/retroarch/config/Beetle PSX/Beetle PSX.opt"
  readonly property var psxAnalogModes: [
    { value: "enabled-analog", label: "Analog", hint: "Boots in analog mode; the combo switches to digital." },
    { value: "enabled", label: "Digital", hint: "Boots in digital mode (sticks dead) until the combo is held." },
    { value: "disabled", label: "Always analog", hint: "Locked to analog, no combo." }
  ]
  property string psxAnalogMode: "enabled"
  property string psxOptText: ""

  function loadPsxOpts(text) {
    root.psxOptText = String(text || "")
    var m = root.psxOptText.match(/^beetle_psx_analog_toggle\s*=\s*"([^"]*)"/m)
    root.psxAnalogMode = m ? m[1] : "enabled"
  }

  function setPsxAnalogMode(value) {
    root.psxAnalogMode = value
    var line = "beetle_psx_analog_toggle = \"" + value + "\""
    var lines = root.psxOptText ? root.psxOptText.split("\n") : []
    var found = false
    for (var i = 0; i < lines.length; i++) {
      if (/^beetle_psx_analog_toggle\s*=/.test(lines[i])) { lines[i] = line; found = true }
    }
    if (!found) lines.push(line)
    root.psxOptText = lines.join("\n")
    // RetroArch rewrites this file on exit; last writer wins.
    Util.execDetached("mkdir -p " + Util.shellQuote(root.psxOptPath.replace(/\/[^\/]*$/, ""))
      + " && printf '%s' " + Util.shellQuote(root.psxOptText)
      + " > " + Util.shellQuote(root.psxOptPath))
  }

  FileView {
    id: psxOptFile
    path: root.psxOptPath
    watchChanges: false
    printErrors: false
    onLoaded: root.loadPsxOpts(text())
  }

  function resetForDevice() {
    root.stopBinding(true)
    root.mapping = ({})
    root.dirty = false
    root.bindIndex = -1
    root.currentKey = ""
    root.status = ""
    // Reopen on the stored preset instead of always falling to megadrive.
    var preset = "megadrive"
    if (root.store && root.stickKey) {
      var entry = root.store.identityFor(root.stickKey)
      if (entry && entry.preset) preset = entry.preset
    }
    root.presetId = preset
  }

  onOpenChanged: if (open) {
    root.resetForDevice()
    coreOptFile.reload()
    psxOptFile.reload()
    remapTemplateFile.reload()
  }
  onDeviceNodeChanged: if (open) root.resetForDevice()

  PanelWindow {
    id: window
    visible: root.open
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omastart-joystick-config"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    onVisibleChanged: {
      if (visible) Qt.callLater(function() { keyCatcher.forceActiveFocus() })
      else root.stopBinding(true)
    }

    BorderSurface {
      id: card
      width: Math.min(Style.space(700), window.width - Style.gapsOut * 2)
      height: Math.min(Style.space(560), window.height - Style.gapsOut * 2)
      anchors.centerIn: parent
      color: Color.popups.background
      borderSpec: Border.localOrSurfaceSpec("popups", "border", Color.popups.border, Color.popups.border, Math.max(1, Style.space(2)))
      padding: Style.spacing.popupPadding
      radius: Style.cornerRadius

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

        // Header: device left, X right. No outside-click close here.
        Item {
          id: header
          width: parent.width
          height: Style.space(32)

          Text {
            anchors.left: parent.left
            anchors.right: closeGlyph.left
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: String(root.deviceName || "Joystick").trim() + "  ·  " + root.deviceNode
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            font.weight: Font.Medium
            elide: Text.ElideRight
          }

          Text {
            id: closeGlyph
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(30)
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            text: "\uf00d"
            color: Color.foreground
            opacity: closeMouse.containsMouse ? 1.0 : 0.6
            font.family: Style.font.family
            font.pixelSize: Style.font.iconLarge

            MouseArea {
              id: closeMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.requestClose()
            }
          }
        }

        // Editable stick name (defaults to the kernel label).
        Row {
          id: nameRow
          width: parent.width
          spacing: Style.space(8)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "Name"
            color: Color.foreground
            opacity: 0.6
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }

          TextField {
            id: nameField
            width: parent.width - Style.space(8) - 60
            anchors.verticalCenter: parent.verticalCenter
            placeholderText: "Stick name…"
            text: root.storedLabel
            onTextEdited: {
              if (root.store && root.stickKey) root.store.setLabel(root.stickKey, text)
            }
          }
        }

        // Preset selector (alphabetical). Flow: the presets no longer
        // fit one line of the card.
        Flow {
          id: presetRow
          width: parent.width
          spacing: Style.space(6)

          Text {
            height: Style.space(30)
            verticalAlignment: Text.AlignVCenter
            textFormat: Text.PlainText
            text: "Preset"
            color: Color.foreground
            opacity: 0.6
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }

          Repeater {
            model: root.presets
            delegate: Button {
              required property var modelData
              readonly property bool current: modelData.id === root.presetId
              height: Style.space(30)
              text: modelData.label
              bordered: !current
              selected: current
              onClicked: {
                root.presetId = modelData.id
                root.stopBinding(true)
                // Save rewrites the profile with this preset's keys only.
                if (Object.keys(root.mapping).length > 0) root.dirty = true
              }
            }
          }
        }

        // Drawing + binding list.
        Row {
          id: bodyRow
          width: parent.width
          height: parent.height - header.height - nameRow.height - presetRow.height - footerRow.height - Style.space(10) * 4
          spacing: Style.space(12)

          Column {
            width: 320
            height: parent.height
            spacing: Style.space(8)

            Loader {
              id: presetLoader
              width: 320
              height: 190
            // NOTE: a plain relative "presets/X.qml" resolves through the
            // qs: module mapping and fails with `module "qs.Commons" is not
            // installed` (seen in preserved logs); Qt.resolvedUrl gives a
            // real file:// URL and loads with normal import paths.
            source: {
              for (var i = 0; i < root.presets.length; i++) {
                if (root.presets[i].id === root.presetId) return Qt.resolvedUrl(root.presets[i].file)
              }
              return Qt.resolvedUrl(root.presets[0].file)
            }
            onLoaded: {
              if (item) item.activeKey = Qt.binding(function() { return root.currentKey })
            }
          }

          // N64 analog tuning (mupen64plus-next core options). No per-profile
          // sensitivity exists in autoconfig, so this is the only lever.
          Column {
            width: 320
            spacing: Style.space(6)
            visible: root.presetId === "n64"

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: "Analog tuning"
              color: Color.foreground
              opacity: 0.6
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            Row {
              width: parent.width
              spacing: Style.space(8)

              Text {
                width: Style.space(86)
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: "Sensitivity"
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }

              PanelSlider {
                id: sensSlider
                width: parent.width - Style.space(86) - Style.space(44) - Style.space(8) * 2
                anchors.verticalCenter: parent.verticalCenter
                bar: root.bar
                minimum: 50
                maximum: 200
                step: 5
                integer: true
                value: root.sensitivity
                onMoved: function(v) { root.sensitivity = Math.round(v) }
                onReleased: function(v) { root.sensitivity = Math.round(v); root.writeCoreOpts() }
              }

              Text {
                width: Style.space(44)
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                textFormat: Text.PlainText
                text: root.sensitivity
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(8)

              Text {
                width: Style.space(86)
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: "Deadzone"
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }

              PanelSlider {
                id: deadSlider
                width: parent.width - Style.space(86) - Style.space(44) - Style.space(8) * 2
                anchors.verticalCenter: parent.verticalCenter
                bar: root.bar
                minimum: 0
                maximum: 30
                step: 1
                integer: true
                value: root.deadzone
                onMoved: function(v) { root.deadzone = Math.round(v) }
                onReleased: function(v) { root.deadzone = Math.round(v); root.writeCoreOpts() }
              }

              Text {
                width: Style.space(44)
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                textFormat: Text.PlainText
                text: root.deadzone
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }
            }
          }

          // PSX analog mode (Beetle PSX core option): without it the
          // DualShock boots digital and games ignore the sticks.
          Column {
            width: 320
            spacing: Style.space(6)
            visible: root.presetId === "playstation"

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: "DualShock mode (Beetle PSX)"
              color: Color.foreground
              opacity: 0.6
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            Row {
              spacing: Style.space(6)

              Repeater {
                model: root.psxAnalogModes
                delegate: Button {
                  required property var modelData
                  readonly property bool current: modelData.value === root.psxAnalogMode
                  height: Style.space(30)
                  text: modelData.label
                  bordered: !current
                  selected: current
                  onClicked: root.setPsxAnalogMode(modelData.value)
                }
              }
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: {
                for (var i = 0; i < root.psxAnalogModes.length; i++) {
                  if (root.psxAnalogModes[i].value === root.psxAnalogMode) return root.psxAnalogModes[i].hint
                }
                return ""
              }
              color: Color.foreground
              opacity: 0.55
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }
          }

          ListView {
            id: bindList
            width: parent.width - 320 - Style.space(12)
            height: parent.height
            clip: true
            spacing: Style.space(2)
            model: root.presetButtons
            boundsBehavior: Flickable.StopAtBounds
            // Follow the wizard: keep the row being bound visible no
            // matter how long the preset is (no height whack-a-mole).
            currentIndex: root.bindIndex
            onCurrentIndexChanged: {
              if (currentIndex >= 0) bindList.positionViewAtIndex(currentIndex, ListView.Contain)
            }

            delegate: Item {
              required property var modelData
              required property int index
              width: bindList.width
              height: Style.space(28)

              Rectangle {
                anchors.fill: parent
                radius: Style.cornerRadius
                color: bindMouse.containsMouse || root.currentKey === modelData.key
                  ? Style.hoverFillFor(Color.foreground, Color.accent)
                  : "transparent"
                border.width: root.currentKey === modelData.key ? 1 : 0
                border.color: Color.accent
              }

              Text {
                anchors.left: parent.left
                anchors.right: bindValue.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(8)
                textFormat: Text.PlainText
                text: (index + 1) + ". " + modelData.label
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.weight: root.currentKey === modelData.key ? Font.Medium : Font.Normal
                elide: Text.ElideRight
              }

              Text {
                id: bindValue
                anchors.right: parent.right
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: root.bindingText(modelData.key)
                color: Color.foreground
                opacity: 0.6
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }

              MouseArea {
                id: bindMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.bindOne(modelData.key)
              }
            }
          }
        }

        // Footer: status + actions.
        Row {
          id: footerRow
          width: parent.width
          height: Style.space(36)
          spacing: Style.space(8)

          Text {
            width: parent.width - bindAllButton.width - skipButton.width - saveButton.width - Style.space(8) * 3
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.status
            color: Color.foreground
            opacity: 0.7
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }

          Button {
            id: bindAllButton
            anchors.verticalCenter: parent.verticalCenter
            text: "Bind keys"
            bordered: true
            enabled: root.bindIndex < 0
            onClicked: root.bindAll()
          }

          Button {
            id: skipButton
            anchors.verticalCenter: parent.verticalCenter
            text: "Skip"
            visible: root.bindIndex >= 0
            onClicked: root.skipStep()
          }

          Button {
            id: saveButton
            anchors.verticalCenter: parent.verticalCenter
            text: "Save"
            bordered: true
            enabled: root.dirty && root.bindIndex < 0
            onClicked: root.save()
          }
        }
      }
    }
  }
}
