import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Hotkeys.js" as HotkeysJS

// Hotkeys section: omarchy defaults merged with your own binds, searchable
// by key, command and label. Defaults can be edited (override) and reset;
// customs can be edited; Add opens the capture window. Saves rewrite only
// our managed block in ~/.config/hypr/bindings.lua and reload Hyprland.
Item {
  id: root

  property string filter: ""
  readonly property string query: filter.trim().toLowerCase()

  property var defaultBinds: []
  property var userRows: []
  property string userFileText: ""

  property var editing: null

  readonly property string userPath: Quickshell.env("HOME") + "/.config/hypr/bindings.lua"
  readonly property string defaultsGlob: "/usr/share/omarchy/default/hypr/bindings"

  function focusSearch() { searchField.forceActiveFocus() }

  function takenKeys(exceptKey) {
    var rows = HotkeysJS.mergeView(root.defaultBinds, root.userRows)
    var out = []
    for (var i = 0; i < rows.length; i++) {
      if (exceptKey && rows[i].key === exceptKey) continue
      out.push(rows[i].key)
    }
    return out
  }

  function displayRows() {
    var rows = HotkeysJS.mergeView(root.defaultBinds, root.userRows)
    // Customs and modified defaults first, then everything else.
    var mine = []
    var rest = []
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].source === "user" || rows[i].modifiedBy) mine.push(rows[i])
      else rest.push(rows[i])
    }
    rows = mine.concat(rest)
    if (root.query === "") return rows
    var out = []
    for (var j = 0; j < rows.length; j++) {
      var hay = [rows[j].key, rows[j].label, rows[j].action].join(" ").toLowerCase()
      if (hay.indexOf(root.query) >= 0) out.push(rows[j])
    }
    return out
  }

  function rebuildDefaults(text) {
    var parsed = HotkeysJS.parseFile(text)
    root.defaultBinds = parsed.binds
  }

  function rebuildUser(text) {
    root.userFileText = String(text || "")
    root.userRows = HotkeysJS.parseUserRows(root.userFileText)
  }

  function refreshDefaults() {
    if (!defaultsProc.running) {
      defaultsProc.collected = ""
      defaultsProc.running = true
    }
  }

  function refresh() {
    root.refreshDefaults()
    userFile.reload()
  }

  function openAdd() {
    root.editing = null
    editWindow.reset(null)
    editWindow.open = true
  }

  function openEdit(row) {
    if (!row) return
    var entry = row.source === "default"
      ? { key: row.key, label: row.label, action: row.action, actionKind: row.actionKind, source: "default" }
      : userRowFor(row.key)
    if (!entry) return
    root.editing = entry
    editWindow.reset(entry)
    editWindow.open = true
  }

  function userRowFor(key) {
    for (var i = 0; i < root.userRows.length; i++) {
      if (root.userRows[i].key === key) return root.userRows[i]
    }
    return null
  }

  // Accepted from the edit window: replace any user row with the same key
  // (or the row it was edited from), keep the rest.
  function applyAccepted(payload) {
    var next = []
    for (var i = 0; i < root.userRows.length; i++) {
      if (root.userRows[i].key === payload.key) continue
      if (root.editing && root.userRows[i].key === root.editing.key && payload.key !== root.editing.key) continue
      next.push(root.userRows[i])
    }
    var replaces = []
    if (root.editing && root.editing.source === "default") replaces = [root.editing.key]
    else if (root.editing) replaces = root.editing.replaces || []
    next.push({ key: payload.key, label: payload.label, action: payload.action, actionKind: payload.actionKind, replaces: replaces })
    root.userRows = next
    root.editing = null
    root.save()
  }

  function resetDefault(row) {
    if (!row) return
    var next = []
    for (var i = 0; i < root.userRows.length; i++) {
      var reps = root.userRows[i].replaces || []
      if (reps.indexOf(row.key) >= 0) continue
      if (root.userRows[i].key === row.key) continue
      next.push(root.userRows[i])
    }
    root.userRows = next
    root.save()
  }

  function save() {
    var block = HotkeysJS.serializeBlock(root.userRows)
    var full = HotkeysJS.replaceBlock(root.userFileText, block)
    saveProc.command = ["bash", "-lc", "printf '%s' " + Util.shellQuote(full)
      + " > " + Util.shellQuote(root.userPath)]
    if (!saveProc.running) saveProc.running = true
  }

  Process {
    id: defaultsProc
    property string collected: ""
    command: ["bash", "-lc", "cat /usr/share/omarchy/default/hypr/bindings/*.lua 2>/dev/null"]
    stdout: SplitParser {
      onRead: function(data) { defaultsProc.collected += data + "\n" }
    }
    onExited: root.rebuildDefaults(defaultsProc.collected)
  }

  Process {
    id: saveProc
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.status = "Save failed (exit " + exitCode + ")."
        return
      }
      root.status = "Saved — " + root.userRows.length + " custom binds active."
      Util.execDetached("hyprctl reload")
      Qt.callLater(root.refresh, 500)
    }
  }

  property string status: ""

  FileView {
    id: userFile
    path: root.userPath
    watchChanges: true
    printErrors: false
    onLoaded: root.rebuildUser(text())
    onLoadFailed: root.rebuildUser("")
    onFileChanged: reload()
  }

  Component.onCompleted: root.refreshDefaults()

  HotkeyEdit {
    id: editWindow
    open: false
    takenKeys: root.takenKeys(root.editing ? root.editing.key : "")
    onAccepted: function(payload) { editWindow.open = false; root.applyAccepted(payload) }
    onCancelled: { editWindow.open = false; root.editing = null }
  }

  Column {
    anchors.fill: parent
    spacing: Style.space(10)

    Row {
      width: parent.width
      spacing: Style.space(8)

      TextField {
        id: searchField
        width: parent.width - addButton.width - Style.space(8)
        placeholderText: "Filter by key, command, label…"
        text: root.filter
        onTextEdited: if (text !== root.filter) root.filter = text
        Keys.onEscapePressed: root.filter = ""
      }

      Button {
        id: addButton
        text: "Add"
        bordered: true
        onClicked: root.openAdd()
      }
    }

    Text {
      id: statusText
      width: parent.width
      visible: root.status !== ""
      textFormat: Text.PlainText
      text: root.status
      color: Color.urgent
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }

    Flickable {
      width: parent.width
      height: parent.height - Style.space(10) * 2 - searchField.height - (statusText.visible ? statusText.height + Style.space(10) : 0)
      contentWidth: width
      contentHeight: rowsCol.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height

      Column {
        id: rowsCol
        width: parent.width
        spacing: Style.space(2)

        Repeater {
          model: root.displayRows()
          delegate: BorderSurface {
            required property var modelData
            width: rowsCol.width
            height: rowCard.implicitHeight + Style.space(16)
            radius: Style.cornerRadius
            color: "transparent"
            borderSpec: Border.controlSpec("normal", Color.foreground, Color.accent)

            Column {
              id: rowCard
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(10)
              spacing: Style.space(8)

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: modelData.key
                  + (modelData.label ? "  ·  " + modelData.label : "")
                  + (modelData.source === "default" ? "" : "  ·  custom")
                color: modelData.modifiedBy ? Color.accent : Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.weight: Font.Medium
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                visible: !!modelData.modifiedBy
                textFormat: Text.PlainText
                text: "modified → " + (modelData.modifiedBy ? modelData.modifiedBy.key : "")
                color: Color.accent
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }

              Row {
                width: parent.width
                spacing: Style.space(8)

                Button {
                  text: "Edit"
                  bordered: true
                  onClicked: root.openEdit(modelData)
                }

                Button {
                  visible: !!modelData.modifiedBy
                  text: "Reset"
                  bordered: true
                  onClicked: root.resetDefault(modelData)
                }
              }
            }
          }
        }

        Text {
          visible: rowsCol.implicitHeight === 0
          width: parent.width
          textFormat: Text.PlainText
          text: "No hotkeys match."
          color: Color.foreground
          opacity: 0.5
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }
      }
    }
  }
}
