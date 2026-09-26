import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Uninstall section: flat A-Z list of installed apps (no sessions) plus the
// obscure preinstalls (web apps, TUIs, CLI stubs, packages) discovered live.
// Per-app removal mirrors the original menu: omarchy-remove-launcher-entry
// dispatches webapp/TUI/user-desktop/pacman/flatpak itself.
Item {
  id: root

  property string filter: ""
  readonly property string query: filter.trim().toLowerCase()

  property var apps: []
  property var preinstalls: []
  property var miseTools: []
  property bool preinstallsDone: false

  property string pendingKind: ""
  property string pendingId: ""
  property string pendingToolId: ""
  property string pendingLabel: ""
  property string pendingCommand: ""
  property bool confirmOpen: false

  function focusSearch() { searchField.forceActiveFocus() }

  function iconSource(icon) {
    var v = String(icon || "")
    if (!v) return Quickshell.iconPath("application-x-executable", true)
    if (v.indexOf("file://") === 0 || v.indexOf("image://") === 0) return v
    if (v.charAt(0) === "/") return "file://" + v
    var themed = ""
    try { themed = Quickshell.iconPath(v, true) } catch (e) { themed = "" }
    if (themed && themed.length > 0) return themed
    return Quickshell.iconPath("application-x-executable", true)
  }

  function appEntries() {
    var values = []
    try { values = DesktopEntries.applications.values || [] } catch (e) { values = [] }
    var out = []
    for (var i = 0; i < values.length; i++) {
      var entry = values[i]
      if (!entry || entry.noDisplay) continue
      var name = String(entry.name || entry.id || "")
      if (!name) continue
      out.push({
        appId: String(entry.id || ""),
        label: name,
        icon: String(entry.icon || ""),
        section: appSection(name)
      })
    }
    out.sort(function(a, b) {
      var x = a.label.toLowerCase(), y = b.label.toLowerCase()
      return x < y ? -1 : (x > y ? 1 : 0)
    })
    return out
  }

  function appSection(label) {
    var first = String(label || "").charAt(0).toUpperCase()
    if (first >= "0" && first <= "9") return "0-9"
    if (first >= "A" && first <= "Z") return first
    return "#"
  }

  function rebuildApps() {
    var all = root.appEntries()
    if (root.query === "") { root.apps = all; return }
    var out = []
    for (var i = 0; i < all.length; i++) {
      if (all[i].label.toLowerCase().indexOf(root.query) >= 0) out.push(all[i])
    }
    root.apps = out
  }

  // Same discovery as omarchy-remove-preinstalls, but itemized so each
  // piece is visible (the bulk remover hides them behind one confirm).
  property bool scanPending: false

  function scanPreinstalls() {
    // Never stack scans; a stuck pacman (db lock) must not wedge us.
    if (scanProc.running) { root.scanPending = true; return }
    root.scanPending = false
    scanProc.collected = ""
    scanProc.running = true
  }

  function applyPreinstalls() {
    var rows = []
    var done = false
    var miseJson = ""
    var inMise = false
    var lines = scanProc.collected.split("\n")
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (!line) continue
      if (line === "@@MISE") { inMise = true; continue }
      if (inMise) { miseJson += lines[i] + "\n"; continue }
      if (line === "DONE") { done = true; continue }
      var colon = line.indexOf(":")
      if (colon < 0) continue
      rows.push({ kind: line.substring(0, colon), name: line.substring(colon + 1), detail: "" })
    }
    rows.sort(function(a, b) {
      if (a.kind < b.kind) return -1
      if (a.kind > b.kind) return 1
      return a.name < b.name ? -1 : (a.name > b.name ? 1 : 0)
    })
    root.preinstalls = rows
    root.preinstallsDone = done
    root.applyMise(miseJson)
  }

  // mise tools keyed by EXACT registry id (e.g. http:muse, not muse):
  // `mise unuse <wrong-id>` exits 0 doing nothing, so commands must use
  // the full key. Labels show the short name.
  function miseLabel(toolId) {
    var parts = String(toolId || "").split(/[:/]/)
    return parts.length > 0 ? parts[parts.length - 1] : String(toolId || "")
  }

  function applyMise(jsonText) {
    var tools = []
    try {
      var data = JSON.parse(jsonText || "{}")
      for (var tool in data) {
        var entries = data[tool]
        if (!Array.isArray(entries)) continue
        var versions = []
        for (var i = 0; i < entries.length; i++) {
          if (entries[i] && entries[i].installed && entries[i].version)
            versions.push(String(entries[i].version))
        }
        if (versions.length > 0) tools.push({ kind: "MISE", name: root.miseLabel(tool), toolId: tool, detail: versions.join(", ") })
      }
    } catch (e) { }
    tools.sort(function(a, b) { return a.name < b.name ? -1 : (a.name > b.name ? 1 : 0) })
    root.miseTools = tools
  }

  function removeCommand(kind, name, toolId) {
    var q = Util.shellQuote(name)
    if (kind === "PKG") return "omarchy-launch-floating-terminal-with-presentation " + Util.shellQuote("sudo pacman -Rns " + q)
    if (kind === "WEBAPP") return "omarchy-webapp-remove " + q
    if (kind === "TUI") return "omarchy-tui-remove " + q
    if (kind === "STUB") return "rm -f " + Util.shellQuote(Quickshell.env("HOME") + "/.local/bin/" + name)
    // unuse drops the toml request (deactivates) but leaves installs
    // behind; uninstall -a deletes them (verified with --dry-run).
    if (kind === "MISE") return root.miseRemoveCommand(toolId || name)
    return ""
  }

  // toolId is the full registry key (http:muse, not muse).
  function miseRemoveCommand(toolId) {
    var q = Util.shellQuote(toolId)
    return "mise unuse " + q + " && mise uninstall -a " + q
  }

  function askRemoveApp(appId, label) {
    root.pendingKind = "APP"
    root.pendingId = appId
    root.pendingLabel = label
    root.pendingCommand = "omarchy-remove-launcher-entry " + Util.shellQuote(appId) + " " + Util.shellQuote(label)
    root.confirmOpen = true
  }

  function askRemovePreinstall(kind, name, toolId) {
    var cmd = root.removeCommand(kind, name, toolId)
    if (!cmd) return
    root.pendingKind = kind
    root.pendingId = name
    root.pendingToolId = toolId || name
    root.pendingLabel = name
    root.pendingCommand = cmd
    root.confirmOpen = true
  }

  function confirmRemove() {
    var cmd = root.pendingCommand
    var kind = root.pendingKind
    var id = root.pendingId
    root.confirmOpen = false
    root.pendingCommand = ""
    if (!cmd) return
    Util.execDetached(cmd)
    if (kind === "APP") {
      // Converges via onValuesChanged below.
      slowRescan.restart()
      return
    }
    // Instant local removals drop the row now; a later rescan brings it
    // back if anything failed (self-correcting). Package removals run in
    // a terminal and converge via rescans.
    if (kind === "STUB" || kind === "WEBAPP" || kind === "TUI") {
      root.preinstalls = root.preinstalls.filter(function(r) {
        return !(r.kind === kind && r.name === id)
      })
    } else if (kind === "MISE") {
      var dropped = root.pendingToolId
      root.miseTools = root.miseTools.filter(function(r) { return (r.toolId || r.name) !== dropped })
    }
    Qt.callLater(root.scanPreinstalls, 2000)
    slowRescan.restart()
  }

  // Safety net for slow sudo flows: one more rebuild after things settle.
  Timer {
    id: slowRescan
    interval: 15000
    repeat: false
    onTriggered: {
      root.rebuildApps()
      root.scanPreinstalls()
    }
  }

  // Live refresh when desktop entries appear/vanish (same as AppLibrary).
  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() { root.rebuildApps() }
  }

  function refresh() {
    root.rebuildApps()
    root.scanPreinstalls()
  }

  Process {
    id: scanProc
    property string collected: ""
    command: ["bash", "-lc", "M=~/.local/state/omarchy/preinstalls-removed; if [ ! -f \"$M\" ]; then for p in aether cliamp libreoffice-fresh xournalpp pinta obsidian obs-studio kdenlive moonlight-qt lazydocker omacut omacalc omawrite; do pacman -Qq \"$p\" >/dev/null 2>&1 && echo \"PKG:$p\"; done; D=~/.local/share/applications; for f in \"$D\"/*.desktop; do [ -f \"$f\" ] || continue; if grep -q 'Exec=omarchy-launch-webapp\\|Exec=omarchy-webapp-handler' \"$f\" 2>/dev/null; then echo \"WEBAPP:$(basename \"$f\" .desktop)\"; elif grep -q 'Exec=xdg-terminal-exec --app-id=TUI\\.' \"$f\" 2>/dev/null; then echo \"TUI:$(basename \"$f\" .desktop)\"; fi; done; for s in codex claude gemini copilot gh opencode playwright playwright-cli pi omp grok crush ghui hunk; do [ -f ~/.local/bin/$s ] && echo \"STUB:$s\"; done; else echo DONE; fi; echo '@@MISE'; mise ls --json 2>/dev/null"]
    stdout: SplitParser {
      onRead: function(data) { scanProc.collected += data + "\n" }
    }
    onExited: {
      root.applyPreinstalls()
      if (root.scanPending) Qt.callLater(root.scanPreinstalls)
    }
  }

  Component.onCompleted: root.refresh()

  Column {
    anchors.fill: parent
    spacing: Style.space(10)

    TextField {
      id: searchField
      width: parent.width
      placeholderText: "Filter applications…"
      text: root.filter
      onTextEdited: if (text !== root.filter) { root.filter = text; root.rebuildApps() }
      Keys.onEscapePressed: { root.filter = ""; root.rebuildApps() }
    }

    Flickable {
      width: parent.width
      height: parent.height - searchField.height - Style.space(10)
      contentWidth: width
      contentHeight: uninstallCol.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height

      Column {
        id: uninstallCol
        width: parent.width
        spacing: Style.space(14)

        Column {
          width: parent.width
          spacing: Style.space(4)
          visible: root.preinstalls.length > 0

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: "Preinstalls"
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            font.weight: Font.Medium
          }

          Repeater {
            model: root.preinstalls
            delegate: Item {
              required property var modelData
              width: uninstallCol.width
              height: Style.space(34)

              Rectangle {
                anchors.fill: parent
                radius: Style.cornerRadius
                color: preMouse.containsMouse
                  ? Style.hoverFillFor(Color.foreground, Color.accent)
                  : "transparent"
              }

              Text {
                anchors.left: parent.left
                anchors.right: removeButton.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(8)
                textFormat: Text.PlainText
                text: modelData.name
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }

              Text {
                anchors.right: removeButton.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: modelData.kind
                color: Color.foreground
                opacity: 0.45
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }

              Button {
                id: removeButton
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                text: "Remove"
                onClicked: root.askRemovePreinstall(modelData.kind, modelData.name)
              }

              MouseArea {
                id: preMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
              }
            }
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(4)
          visible: root.miseTools.length > 0

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: "Mise"
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            font.weight: Font.Medium
          }

          Repeater {
            model: root.miseTools
            delegate: Item {
              required property var modelData
              width: uninstallCol.width
              height: Style.space(40)

              Rectangle {
                anchors.fill: parent
                radius: Style.cornerRadius
                color: miseMouse.containsMouse
                  ? Style.hoverFillFor(Color.foreground, Color.accent)
                  : "transparent"
              }

              Column {
                anchors.left: parent.left
                anchors.right: miseRemoveButton.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(8)
                spacing: 0

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: modelData.name
                  color: Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: modelData.detail
                  color: Color.foreground
                  opacity: 0.55
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }

              Button {
                id: miseRemoveButton
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                text: "Remove"
                onClicked: root.askRemovePreinstall("MISE", modelData.name, modelData.toolId)
              }

              MouseArea {
                id: miseMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
              }
            }
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(4)

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: "Applications"
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            font.weight: Font.Medium
          }

          ListView {
            id: appList
            width: parent.width
            height: Math.max(Style.space(120), contentHeight)
            clip: true
            spacing: Style.space(2)
            model: root.apps
            boundsBehavior: Flickable.StopAtBounds

            section.property: "section"
            section.criteria: ViewSection.FullString
            section.delegate: Item {
              required property string section
              width: appList.width
              height: Style.space(20)

              Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: section
                color: Color.foreground
                opacity: 0.45
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
              }
            }

            delegate: Item {
              required property var modelData
              width: appList.width
              height: Style.space(34)

              Rectangle {
                anchors.fill: parent
                radius: Style.cornerRadius
                color: appMouse.containsMouse
                  ? Style.hoverFillFor(Color.foreground, Color.accent)
                  : "transparent"
              }

              Image {
                id: appIcon
                anchors.left: parent.left
                anchors.leftMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(22)
                height: Style.space(22)
                fillMode: Image.PreserveAspectFit
                sourceSize.width: width * Screen.devicePixelRatio
                sourceSize.height: height * Screen.devicePixelRatio
                source: root.iconSource(modelData.icon)
                asynchronous: true
              }

              Text {
                anchors.left: appIcon.right
                anchors.leftMargin: Style.space(8)
                anchors.right: appRemoveButton.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: modelData.label || ""
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }

              Button {
                id: appRemoveButton
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                text: "Remove"
                onClicked: root.askRemoveApp(modelData.appId, modelData.label)
              }

              MouseArea {
                id: appMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
              }
            }
          }

          Text {
            visible: appList.count === 0
            width: parent.width
            textFormat: Text.PlainText
            text: "No applications found."
            color: Color.foreground
            opacity: 0.5
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }
        }
      }
    }
  }

  ConfirmDialog {
    anchors.fill: parent
    opened: root.confirmOpen
    message: "Uninstall " + root.pendingLabel + "?"
    confirmText: "Uninstall"
    background: Color.popups.background
    foreground: Color.popups.text
    scrim: Util.alpha(Color.foreground, 0.5)
    selectedBackground: Color.accent
    selectedText: Color.background
    fontFamily: Style.font.family
    cornerRadius: Style.cornerRadius
    onCanceled: root.confirmOpen = false
    onConfirmed: root.confirmRemove()
  }
}
