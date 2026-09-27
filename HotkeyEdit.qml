import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Hotkeys.js" as HotkeysJS

// Key-capture + edit window for one hotkey. `editing` is null when adding,
// otherwise {key, label, action, actionKind, source}. `takenKeys` lists
// normalized sequences already mapped (excluding the row being edited);
// Save stays disabled on collision with a "Sequence Keys already exists"
// warning. Emits accepted({key, label, action, actionKind}).
Item {
  id: root

  property bool open: false
  property var editing: null
  property var takenKeys: []

  signal accepted(var row)
  signal cancelled()

  readonly property string originalKey: editing ? String(editing.key || "") : ""
  property string seq: ""
  property string label: ""
  property string command: ""
  property string commandKind: "string"
  property bool listening: false

  readonly property string normSeq: HotkeysJS.normalizeKey(root.seq)
  readonly property bool duplicate: {
    if (root.normSeq === "") return true
    if (root.originalKey !== "" && root.normSeq === HotkeysJS.normalizeKey(root.originalKey)) return false
    return root.takenKeys.indexOf(root.normSeq) >= 0
  }

  function reset(entry) {
    root.editing = entry || null
    root.seq = entry ? String(entry.key || "") : ""
    root.label = entry ? String(entry.label || "") : ""
    root.command = entry ? String(entry.action || "") : ""
    root.commandKind = entry ? String(entry.actionKind || "string") : "string"
    root.listening = false
  }

  function modifierName(key) {
    if (key === Qt.Key_Shift || key === Qt.Key_Shift_L || key === Qt.Key_Shift_R) return "SHIFT"
    if (key === Qt.Key_Control || key === Qt.Key_Control_L || key === Qt.Key_Control_R) return "CTRL"
    if (key === Qt.Key_Alt || key === Qt.Key_Alt_L || key === Qt.Key_Alt_R || key === Qt.Key_AltGr) return "ALT"
    if (key === Qt.Key_Meta || key === Qt.Key_Meta_L || key === Qt.Key_Meta_R
      || key === Qt.Key_Super_L || key === Qt.Key_Super_R) return "SUPER"
    return ""
  }

  function keyDisplayName(event) {
    var k = event.key
    var mod = root.modifierName(k)
    if (mod) return mod
    if (event.text && event.text.length === 1) {
      var ch = event.text.toUpperCase()
      if (ch !== " ") return ch
    }
    if (k === Qt.Key_Return || k === Qt.Key_Enter) return "RETURN"
    if (k === Qt.Key_Escape) return "ESCAPE"
    if (k === Qt.Key_Space) return "SPACE"
    if (k === Qt.Key_Tab) return "TAB"
    if (k === Qt.Key_Backspace) return "BACKSPACE"
    if (k === Qt.Key_Delete) return "DELETE"
    if (k === Qt.Key_Insert) return "INSERT"
    if (k === Qt.Key_Home) return "HOME"
    if (k === Qt.Key_End) return "END"
    if (k === Qt.Key_PageUp) return "PAGEUP"
    if (k === Qt.Key_PageDown) return "PAGEDOWN"
    if (k === Qt.Key_Up) return "UP"
    if (k === Qt.Key_Down) return "DOWN"
    if (k === Qt.Key_Left) return "LEFT"
    if (k === Qt.Key_Right) return "RIGHT"
    if (k >= Qt.Key_F1 && k <= Qt.Key_F12) return "F" + (k - Qt.Key_F1 + 1)
    if (k === Qt.Key_Print) return "PRINT"
    if (k === Qt.Key_Pause) return "PAUSE"
    if (k === Qt.Key_Menu) return "MENU"
    if (k === Qt.Key_Slash) return "SLASH"
    if (k === Qt.Key_Period) return "PERIOD"
    if (k === Qt.Key_Comma) return "COMMA"
    if (k === Qt.Key_Minus) return "MINUS"
    if (k === Qt.Key_Equal) return "EQUAL"
    if (k === Qt.Key_BracketLeft) return "BRACKETLEFT"
    if (k === Qt.Key_BracketRight) return "BRACKETRIGHT"
    if (k === Qt.Key_Semicolon) return "SEMICOLON"
    if (k === Qt.Key_Apostrophe) return "APOSTROPHE"
    if (k === Qt.Key_Grave) return "GRAVE"
    if (k === Qt.Key_Backslash) return "BACKSLASH"
    return ""
  }

  function captureEvent(event) {
    var name = root.keyDisplayName(event)
    if (!name) return
    var mods = []
    if (event.modifiers & Qt.MetaModifier) mods.push("SUPER")
    if (event.modifiers & Qt.ShiftModifier) mods.push("SHIFT")
    if (event.modifiers & Qt.AltModifier) mods.push("ALT")
    if (event.modifiers & Qt.ControlModifier) mods.push("CTRL")
    // Bare modifier press (e.g. SUPER alone): record it but KEEP
    // listening so the chord can complete (SUPER, then E).
    var bareMod = mods.length === 1 && mods[0] === name
    if (!bareMod) {
      if (mods.indexOf(name) < 0) mods.push(name)
      root.seq = mods.join(" + ")
      root.listening = false
    } else {
      root.seq = name
    }
    event.accepted = true
  }

  PanelWindow {
    id: window
    visible: root.open
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omastart-hotkey-edit"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    onVisibleChanged: {
      if (visible) Qt.callLater(function() { keyCatcher.forceActiveFocus() })
      else root.listening = false
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.cancelled()
    }

    BorderSurface {
      id: card
      width: Math.min(Style.space(480), window.width - Style.gapsOut * 2)
      height: content.implicitHeight + contentTopInset + contentBottomInset
      anchors.centerIn: parent
      color: Color.popups.background
      borderSpec: Border.localOrSurfaceSpec("popups", "border", Color.popups.border, Color.popups.border, Math.max(1, Style.space(2)))
      padding: Style.spacing.popupPadding
      radius: Style.cornerRadius

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: root.listening ? root.listening = false : root.cancelled()
        Keys.onPressed: function(event) {
          if (root.listening) root.captureEvent(event)
        }
      }

      Column {
        id: content
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: Style.space(10)

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.editing ? "Edit hotkey" : "Add hotkey"
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.heading
          font.weight: Font.Medium
        }

        Button {
          width: parent.width
          text: root.listening ? "Press keys now…" : (root.seq || "Click to capture keys")
          bordered: true
          onClicked: root.listening = !root.listening
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "Keys"
          color: Color.foreground
          opacity: 0.6
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        TextField {
          width: parent.width
          text: root.seq
          // Editable fallback: chords already taken by the system are
          // intercepted by Hyprland before they reach this window —
          // type them here instead (e.g. SUPER, SUPER + SPACE).
          placeholderText: "Capture above, or type e.g. SUPER + SPACE"
          onTextEdited: root.seq = text
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "Taken system chords never arrive here — type them manually."
          color: Color.foreground
          opacity: 0.5
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Text {
          width: parent.width
          visible: HotkeysJS.isBareMod(root.normSeq)
          textFormat: Text.PlainText
          text: "A lone modifier can never fire — add a key to it."
          color: Color.urgent
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.weight: Font.Medium
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "Label"
          color: Color.foreground
          opacity: 0.6
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        TextField {
          width: parent.width
          text: root.label
          placeholderText: "e.g. Omastart"
          onTextEdited: root.label = text
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "Command"
          color: Color.foreground
          opacity: 0.6
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        TextField {
          width: parent.width
          text: root.command
          placeholderText: "e.g. omarchy-shell shell toggle audryus.omastart"
          onTextEdited: {
            root.command = text
            root.commandKind = "string"
          }
        }

        Text {
          width: parent.width
          visible: root.seq !== "" && root.duplicate && root.normSeq !== HotkeysJS.normalizeKey(root.originalKey)
          textFormat: Text.PlainText
          text: "Sequence Keys already exists"
          color: Color.urgent
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.weight: Font.Medium
        }

        Row {
          width: parent.width
          spacing: Style.space(8)

          Item { width: parent.width - saveButton.width - cancelButton.width - Style.space(8) * 2; height: 1 }

          Button {
            id: cancelButton
            text: "Cancel"
            onClicked: root.cancelled()
          }

          Button {
            id: saveButton
            text: "Save"
            bordered: true
            enabled: root.seq !== "" && root.label.trim() !== "" && !root.duplicate && !HotkeysJS.isBareMod(root.normSeq)
            onClicked: {
              var kind = root.commandKind
              if (root.editing && root.command === String(root.editing.action || "")) kind = String(root.editing.actionKind || "string")
              root.accepted({ key: root.normSeq, label: root.label.trim(), action: root.command, actionKind: kind })
            }
          }
        }
      }
    }
  }
}
