import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "MenuModel.js" as MenuModel

// Defaults section: friendlier take on setup.default.* — the four sessions
// (Agent, Browser, Terminal, Editor) as radio lists. Options, visibility
// rules and set actions come from the merged menu (user overrides apply,
// own FileViews); install actions come from the matching install.*
// entries, like the traditional menu.
Item {
  id: root

  property var menu: null

  signal closeRequested()

  // session key, menu subtree, install subtree, current-value getter.
  readonly property var sessions: [
    { key: "agent", title: "Agent", menu: "setup.default.agent", install: "install.ai", get: "omarchy-default-agent" },
    { key: "browser", title: "Browser", menu: "setup.default.browser", install: "install.browser", get: "omarchy-default-browser" },
    { key: "terminal", title: "Terminal", menu: "setup.default.terminal", install: "install.terminal", get: "omarchy-default-terminal" },
    { key: "editor", title: "Editor", menu: "setup.default.editor", install: "install.editor", get: "omarchy-default-editor" }
  ]

  property var rows: []
  property bool evalPending: false
  property string filter: ""
  readonly property string query: filter.trim().toLowerCase()

  function focusSearch() { searchField.forceActiveFocus() }

  function rowMatches(row) {
    if (root.query === "") return true
    return String(row.label || "").toLowerCase().indexOf(root.query) >= 0
  }

  function sessionVisible(sessionKey) {
    if (root.query === "") return true
    return root.rows.some(function(r) { return r.session === sessionKey && root.rowMatches(r) })
  }

  function sessionKey(session, value) {
    return session + ":" + value
  }

  // One bash run evaluates every `when:` (installed?) plus the four
  // getters (current default?). Plain `if` lines on purpose: the shared
  // guardScript prelude scans all installed packages, overkill for the
  // `omarchy-cmd-present` checks used here.
  function evalScript(skeleton) {
    var script = ""
    for (var i = 0; i < skeleton.length; i++) {
      var opt = skeleton[i]
      if (opt.when)
        script += "if { " + opt.when + "; } >/dev/null 2>&1; then echo 'k" + i + ":1'; else echo 'k" + i + ":0'; fi\n"
      else
        script += "echo 'k" + i + ":1'\n"
    }
    for (var s = 0; s < root.sessions.length; s++) {
      var key = root.sessions[s].key
      var get = root.sessions[s].get
      script += "echo 'cur:" + key + ":'$(" + get + " 2>/dev/null)" + "\n"
    }
    return script
  }

  property var defaultMenuItems: []
  property var userMenuItems: []

  function menuMerged() {
    return MenuModel.mergeMenuSources(root.defaultMenuItems, root.userMenuItems)
  }

  FileView {
    id: defaultMenuFile
    path: "/usr/share/omarchy/default/omarchy/omarchy-menu.jsonc"
    watchChanges: true
    printErrors: false
    onLoaded: { root.defaultMenuItems = MenuModel.parseMenuJsonc(text()); root.rebuild() }
    onFileChanged: reload()
  }

  FileView {
    id: userMenuFile
    path: Quickshell.env("HOME") + "/.config/omarchy/extensions/omarchy-menu.jsonc"
    watchChanges: true
    printErrors: false
    onLoaded: { root.userMenuItems = MenuModel.parseMenuJsonc(text()); root.rebuild() }
    onLoadFailed: { root.userMenuItems = []; root.rebuild() }
    onFileChanged: reload()
  }

  function rebuild() {
    var merged = root.menuMerged()
    var items = merged.items
    var skeleton = []
    for (var s = 0; s < root.sessions.length; s++) {
      var session = root.sessions[s]
      var order = Array.isArray(merged.itemOrder) ? merged.itemOrder : []
      for (var i = 0; i < order.length; i++) {
        var entry = items[order[i]]
        if (!entry || entry.parent !== session.menu) continue
        var value = String(entry.id).substring(session.menu.length + 1)
        var installEntry = items[session.install + "." + value]
        skeleton.push({
          session: session.key,
          title: session.title,
          value: value,
          label: entry.label || value,
          icon: entry.icon || "",
          iconFont: entry.iconFont || "",
          when: entry.when || "",
          setAction: entry.action || "",
          installAction: installEntry ? (installEntry.action || "") : ""
        })
      }
    }
    root.rows = skeleton
    root.evaluate()
  }

  function evaluate() {
    if (evalProc.running) { root.evalPending = true; return }
    root.evalPending = false
    if (root.rows.length === 0) return
    evalProc.collected = ""
    evalProc.command = ["bash", "-lc", root.evalScript(root.rows)]
    evalProc.running = true
  }

  function applyEval() {
    var installed = {}
    var current = {}
    var lines = evalProc.collected.split("\n")
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (!line) continue
      if (line.indexOf("cur:") === 0) {
        var rest = line.substring(4)
        var colon = rest.indexOf(":")
        if (colon > 0) current[rest.substring(0, colon)] = rest.substring(colon + 1).trim()
      } else {
        var parts = line.split(":")
        if (parts.length === 2) installed[parts[0]] = parts[1] === "1"
      }
    }
    var next = []
    for (var j = 0; j < root.rows.length; j++) {
      var opt = root.rows[j]
      var row = {}
      for (var k in opt) row[k] = opt[k]
      row.installed = installed["k" + j] !== false
      row.isDefault = current[opt.session] === opt.value
      next.push(row)
    }
    root.rows = next
  }

  function pick(row) {
    if (!row) return
    if (row.installed || !row.installAction) {
      if (row.setAction) {
        Util.execDetached(row.setAction)
        Qt.callLater(root.evaluate)
      }
    } else {
      // Not installed: open the traditional installer, like install.* does.
      root.closeRequested()
      Util.execDetached(row.installAction)
    }
  }

  function refresh() {
    root.rebuild()
  }

  Process {
    id: evalProc
    property string collected: ""
    stdout: SplitParser {
      onRead: function(data) { evalProc.collected += data + "\n" }
    }
    onExited: {
      root.applyEval()
      if (root.evalPending) Qt.callLater(root.evaluate)
    }
  }

  // Live refresh when a default changes on disk behind our back.
  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/defaults/agent"
    watchChanges: true
    printErrors: false
    onFileChanged: root.evaluate()
    onLoaded: root.evaluate()
  }

  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/defaults/editor"
    watchChanges: true
    printErrors: false
    onFileChanged: root.evaluate()
    onLoaded: root.evaluate()
  }

  FileView {
    path: Quickshell.env("HOME") + "/.config/xdg-terminals.list"
    watchChanges: true
    printErrors: false
    onFileChanged: root.evaluate()
    onLoaded: root.evaluate()
  }

  FileView {
    path: Quickshell.env("HOME") + "/.config/mimeapps.list"
    watchChanges: true
    printErrors: false
    onFileChanged: root.evaluate()
    onLoaded: root.evaluate()
  }

  Component.onCompleted: root.rebuild()

  Column {
    anchors.fill: parent
    spacing: Style.space(10)

    TextField {
      id: searchField
      width: parent.width
      placeholderText: "Filter defaults…"
      text: root.filter
      onTextEdited: if (text !== root.filter) root.filter = text
      Keys.onEscapePressed: root.filter = ""
    }

    Flickable {
      width: parent.width
      height: parent.height - searchField.height - Style.space(10)
      contentWidth: width
      contentHeight: sessionsCol.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height

    Column {
      id: sessionsCol
      width: parent.width
      spacing: Style.space(14)

      Repeater {
        model: root.sessions
        delegate: Column {
          required property var modelData
          readonly property string sessionKey: modelData.key
          width: sessionsCol.width
          spacing: Style.space(4)
          visible: root.sessionVisible(sessionKey)

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: modelData.title
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            font.weight: Font.Medium
          }

          Repeater {
            model: root.rows.filter(function(r) { return r.session === sessionKey && root.rowMatches(r) })
            delegate: Item {
              required property var modelData
              width: sessionsCol.width
              height: Style.space(34)

              Rectangle {
                anchors.fill: parent
                radius: Style.cornerRadius
                color: optMouse.containsMouse
                  ? Style.hoverFillFor(Color.foreground, Color.accent)
                  : "transparent"
              }

              Text {
                id: radioGlyph
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(28)
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                text: modelData.isDefault ? "\uf192" : "\uf10c"
                color: modelData.isDefault ? Color.accent : Color.foreground
                opacity: modelData.installed ? 1.0 : 0.45
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }

              Text {
                anchors.left: radioGlyph.right
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(30)
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                text: modelData.icon || ""
                color: Color.foreground
                opacity: modelData.installed ? 1.0 : 0.45
                font.family: modelData.iconFont || Style.font.family
                font.pixelSize: Style.font.iconLarge
              }

              Text {
                anchors.left: radioGlyph.right
                anchors.leftMargin: Style.space(30)
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: modelData.label + (modelData.installed ? "" : "  ·  not installed")
                color: Color.foreground
                opacity: modelData.installed ? 1.0 : 0.55
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.weight: modelData.isDefault ? Font.Medium : Font.Normal
                elide: Text.ElideRight
              }

              MouseArea {
                id: optMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.pick(modelData)
              }
            }
          }
        }
      }

      Text {
        width: parent.width
        visible: root.query !== "" && !root.rows.some(function(r) { return root.rowMatches(r) })
        textFormat: Text.PlainText
        text: "No matches"
        color: Color.foreground
        opacity: 0.5
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
    }
    }
  }
}
