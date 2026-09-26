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
  property string pluginDir: ""
  property string deviceNode: ""
  property string deviceName: ""
  property string deviceVid: ""
  property string devicePid: ""

  signal requestClose()

  readonly property var presets: [
    { id: "megadrive", label: "Megadrive", file: "presets/Megadrive.qml" },
    { id: "n64", label: "N64", file: "presets/N64.qml" },
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

  function sanitizedName() {
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

  function bindingText(key) {
    var m = root.mapping[key]
    if (!m) return "—"
    return m.kind === "axis" ? ("axis " + m.value) : ("btn " + m.value)
  }

  // ---- guided binding ----

  function bindAll() {
    var list = root.targets()
    if (list.length === 0) return
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

  function applyCapture(token, line) {
    if (token !== root.bindToken) return
    var mBtn = line.match(/^BTN\s+(\d+)/)
    var mAxis = line.match(/^AXIS\s*([+-]\d+)/)
    var list = root.targets()
    var key = root.currentKey
    if (!key) return
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
      // Empty/garbled run: retry the same step.
      root.bindStep(root.bindIndex)
    }
  }

  // ---- persistence (RetroArch autoconfig) ----

  // One retropad map per device: presets are just guides with familiar
  // labels for the same keys, so every bound key is written.
  function cfgText() {
    var lines = []
    lines.push("input_driver = \"udev\"")
    lines.push("input_device = \"" + String(root.deviceName || "").trim() + "\"")
    var vid = root.hexDec(root.deviceVid)
    var pid = root.hexDec(root.devicePid)
    if (vid) lines.push("input_vendor_id = \"" + vid + "\"")
    if (pid) lines.push("input_product_id = \"" + pid + "\"")
    lines.push("")
    var list = root.targets()
    var labels = {}
    for (var i = 0; i < list.length; i++) labels[list[i].key] = list[i].label
    var keys = []
    for (var k in root.mapping) keys.push(k)
    keys.sort()
    for (var j = 0; j < keys.length; j++) {
      var m = root.mapping[keys[j]]
      if (!m) continue
      if (m.kind === "axis") lines.push("input_" + keys[j] + "_axis = \"" + m.value + "\"")
      else lines.push("input_" + keys[j] + "_btn = \"" + m.value + "\"")
      lines.push("input_" + keys[j] + "_label = \"" + (labels[keys[j]] || keys[j]) + "\"")
    }
    return lines.join("\n") + "\n"
  }

  function save() {
    if (!root.dirty || saveProc.running) return
    var dir = root.cfgDir
    var path = root.cfgPath()
    // Two-phase: temp file first so a stray quote can never truncate the
    // profile; then move into place.
    saveProc.command = ["bash", "-lc", "mkdir -p " + Util.shellQuote(dir)
      + " && printf '%s' " + Util.shellQuote(root.cfgText())
      + " > " + Util.shellQuote(dir + "/.tmp.cfg")
      + " && mv " + Util.shellQuote(dir + "/.tmp.cfg") + " " + Util.shellQuote(path)]
    saveProc.running = true
  }

  Process {
    id: saveProc
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.dirty = false
        root.status = "Saved to " + root.cfgPath()
      } else {
        root.status = "Save failed (exit " + exitCode + ")."
      }
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
      var last = ""
      for (var i = lines.length - 1; i >= 0; i--) {
        if (lines[i].trim()) { last = lines[i].trim(); break }
      }
      root.applyCapture(token, last)
    }
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
      root.status = "Loaded existing profile."
    }
  }

  function resetForDevice() {
    root.stopBinding(true)
    root.mapping = ({})
    root.dirty = false
    root.bindIndex = -1
    root.currentKey = ""
    root.status = ""
  }

  onOpenChanged: if (open) root.resetForDevice()
  onDeviceNodeChanged: if (open) root.resetForDevice()

  PanelWindow {
    id: window
    visible: root.open
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "audryus-joystick-config"
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

        // Preset selector (alphabetical).
        Row {
          id: presetRow
          width: parent.width
          spacing: Style.space(6)

          Text {
            anchors.verticalCenter: parent.verticalCenter
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
              }
            }
          }
        }

        // Drawing + binding list.
        Row {
          id: bodyRow
          width: parent.width
          height: parent.height - header.height - presetRow.height - footerRow.height - Style.space(10) * 3
          spacing: Style.space(12)

          Loader {
            id: presetLoader
            width: 320
            height: parent.height
            source: {
              for (var i = 0; i < root.presets.length; i++) {
                if (root.presets[i].id === root.presetId) return root.presets[i].file
              }
              return root.presets[0].file
            }
            onLoaded: {
              if (item) item.activeKey = Qt.binding(function() { return root.currentKey })
            }
          }

          Flickable {
            width: parent.width - 320 - Style.space(12)
            height: parent.height
            contentWidth: width
            contentHeight: bindCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height

            Column {
              id: bindCol
              width: parent.width
              spacing: Style.space(2)

              Repeater {
                model: root.presetButtons
                delegate: Item {
                  required property var modelData
                  required property int index
                  width: bindCol.width
                  height: Style.space(28)

                  Rectangle {
                    anchors.fill: parent
                    radius: Style.cornerRadius
                    color: bindMouse.containsMouse || root.currentKey === modelData.key
                      ? Style.hoverFillFor(Color.foreground, Color.accent)
                      : "transparent"
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
