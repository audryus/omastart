import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Hotkeys.js" as HotkeysJS

// Hotkeys section: every bind Hyprland has live, merged with your own and
// grouped by category; searchable by key, command and description. Defaults
// can be edited (override) and reset;
// customs can be edited; Add opens the capture window. Saves rewrite only
// our managed block in ~/.config/hypr/bindings.lua and reload Hyprland.
Item {
  id: root

  property string filter: ""
  readonly property string query: filter.trim().toLowerCase()

  property var liveBinds: []
  property var fileBinds: []
  property var configBinds: []
  property var userRows: []
  readonly property var defaultBinds: HotkeysJS.buildDefaults(root.liveBinds, root.fileBinds, root.configBinds, root.userRows)
  readonly property var shownRows: root.displayRows()
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

  function removeCustom(row) {
    if (!row || row.source !== "user") return
    var next = []
    for (var i = 0; i < root.userRows.length; i++) {
      if (root.userRows[i].key === row.key) continue
      next.push(root.userRows[i])
    }
    root.userRows = next
    root.save()
  }

  function displayRows() {
    var rows = HotkeysJS.mergeView(root.defaultBinds, root.userRows)
    // Customs first, then untouched defaults. Overridden defaults are
    // hidden (their replacement carries the context); Reset lives on it.
    var customs = []
    var rest = []
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].source === "user") customs.push(rows[i])
      else if (!rows[i].modifiedBy) rest.push(rows[i])
    }
    rows = customs.concat(rest)
    var out = []
    for (var j = 0; j < rows.length; j++) {
      if (HotkeysJS.matchesQuery(rows[j], root.query)) out.push(rows[j])
    }
    return HotkeysJS.groupRows(out)
  }

  function rebuildDefaults(text) {
    var parts = HotkeysJS.splitDefaultsOutput(text)
    root.fileBinds = HotkeysJS.parseFile(parts.files).binds
    root.liveBinds = HotkeysJS.parseLiveBinds(parts.live)
  }

  function rebuildUser(text) {
    root.userFileText = String(text || "")
    root.userRows = HotkeysJS.parseUserRows(root.userFileText)
    root.configBinds = HotkeysJS.parseFile(HotkeysJS.stripManaged(root.userFileText)).binds
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

  // Accepted from the edit window: a default being re-edited drops its
  // previous override (matched via replaces, not key); anything else
  // replaces by key. Keeps exactly one row per edit.
  function applyAccepted(payload) {
    var origKey = root.editing ? root.editing.key : ""
    var wasDefault = root.editing && root.editing.source === "default"
    var next = []
    for (var i = 0; i < root.userRows.length; i++) {
      var current = root.userRows[i]
      if (current.key === payload.key) continue
      if (wasDefault) {
        var reps = current.replaces || []
        if (reps.indexOf(origKey) >= 0) continue
      } else if (origKey && current.key === origKey && payload.key !== origKey) continue
      next.push(current)
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
    command: ["bash", "-c", "for f in " + root.defaultsGlob + "/*.lua; do printf '%s\\n' \"" + HotkeysJS.FILE_MARK + "$(basename \"$f\" .lua)\"; cat \"$f\"; done 2>/dev/null; echo '" + HotkeysJS.LIVE_MARK + "'; hyprctl binds 2>/dev/null"]
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
      refreshTimer.restart()
    }
  }

  property string status: ""

  // hyprctl reload is asynchronous: give it a moment before reading binds.
  Timer {
    id: refreshTimer
    interval: 500
    onTriggered: root.refresh()
  }

  FileView {
    id: userFile
    path: root.userPath
    watchChanges: true
    printErrors: false
    onLoaded: root.rebuildUser(text())
    onLoadFailed: root.rebuildUser("")
    onFileChanged: {
      reload()
      refreshTimer.restart()
    }
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
          model: root.shownRows
          delegate: Item {
            id: rowItem
            required property var modelData
            readonly property bool isHeader: modelData.header !== undefined
            readonly property bool mine: modelData.source === "user" || modelData.origin === "config"
            width: rowsCol.width
            height: isHeader ? headerText.implicitHeight + Style.space(14) : rowCard.implicitHeight + Style.space(16)

            Text {
              id: headerText
              visible: rowItem.isHeader
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.bottomMargin: Style.space(4)
              textFormat: Text.PlainText
              text: rowItem.isHeader ? rowItem.modelData.header + "  ·  " + rowItem.modelData.count : ""
              color: Color.accent
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            BorderSurface {
              visible: !rowItem.isHeader
              anchors.fill: parent
              radius: Style.cornerRadius
              color: rowItem.mine ? Style.selectedFillFor(Color.foreground, Color.accent) : "transparent"
              borderSpec: Border.controlSpec("normal", Color.foreground, Color.accent)

              Column {
                id: rowCard
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(10)
                spacing: Style.space(6)

                Item {
                  width: parent.width
                  height: Math.max(caps.implicitHeight, actions.implicitHeight)

                  Flow {
                    id: caps
                    anchors.left: parent.left
                    anchors.right: actions.left
                    anchors.rightMargin: Style.space(8)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(4)

                    Repeater {
                      model: rowItem.isHeader ? [] : HotkeysJS.keyCaps(rowItem.modelData.key)
                      delegate: Rectangle {
                        required property string modelData
                        width: capText.implicitWidth + Style.space(12)
                        height: capText.implicitHeight + Style.space(4)
                        radius: Style.cornerRadius
                        color: "transparent"
                        border.width: 1
                        border.color: Qt.alpha(Color.foreground, 0.35)

                        Text {
                          id: capText
                          anchors.centerIn: parent
                          textFormat: Text.PlainText
                          text: parent.modelData
                          color: Color.foreground
                          font.family: Style.font.family
                          font.pixelSize: Style.font.caption
                          font.weight: Font.Medium
                        }
                      }
                    }
                  }

                  Row {
                    id: actions
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(6)

                    Button {
                      text: "Edit"
                      bordered: true
                      onClicked: root.openEdit(rowItem.modelData)
                    }

                    Button {
                      visible: (rowItem.modelData.replaces || []).length > 0
                      text: "Reset"
                      bordered: true
                      onClicked: root.resetDefault({ key: (rowItem.modelData.replaces || [])[0] })
                    }

                    Button {
                      visible: rowItem.modelData.source === "user" && (rowItem.modelData.replaces || []).length === 0
                      text: "Remove"
                      bordered: true
                      onClicked: root.removeCustom(rowItem.modelData)
                    }
                  }
                }

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: rowItem.isHeader ? "" : (rowItem.modelData.label || "No description")
                  color: Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.weight: Font.Medium
                  wrapMode: Text.WordWrap
                }

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: rowItem.isHeader ? "" : HotkeysJS.describeAction(rowItem.modelData)
                    + ((rowItem.modelData.replaces || []).length > 0 ? "  ·  replaces " + rowItem.modelData.replaces.join(", ") : "")
                  color: Color.foreground
                  opacity: 0.6
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WrapAnywhere
                  maximumLineCount: 2
                  elide: Text.ElideRight
                }
              }
            }
          }
        }

        Text {
          visible: root.shownRows.length === 0
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
