import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Right places column (static places + favorite folders). Favorites arrive
// via property (owned by BarWidget, shared with Settings/General); launch
// helpers are local.
Rectangle {
  id: root

  property var bar: null
  property var favorites: []

  signal closeRequested()

  anchors.top: parent.top
  anchors.bottom: parent.bottom
  anchors.right: parent.right
  width: parent.width * 0.35
  radius: Style.cornerRadius
  color: "transparent"

  readonly property string homeDir: Quickshell.env("HOME")
  // Per-mouse-button actions ("fm" = file manager, "term" = terminal,
  // "agent" = default agent). Missing button = do nothing (not even close).
  readonly property var places: [
    { label: "My Computer", dir: homeDir, icon: "\uf015", left: "fm", right: "term" },
    { divider: true },
    { label: "Projects", dir: homeDir + "/Projects", icon: "\uf121", left: "fm", middle: "agent", right: "term" },
    { label: "Work", dir: homeDir + "/Work", icon: "\uf0b1", left: "fm", middle: "agent", right: "term" },
    { divider: true },
    { label: "Documents", dir: homeDir + "/Documents", icon: "\uf15c", left: "fm", right: "term" },
    { label: "Downloads", dir: homeDir + "/Downloads", icon: "\uf019", left: "fm", right: "term" },
    { label: "Games", dir: homeDir + "/Games", icon: "\uf11b", left: "fm", right: "term" },
    { divider: true },
    { label: "Music", dir: homeDir + "/Music", icon: "\uf001", left: "fm", right: "term" },
    { label: "Pictures", dir: homeDir + "/Pictures", icon: "\uf03e", left: "fm", right: "term" },
    { label: "Videos", dir: homeDir + "/Videos", icon: "\uf008", left: "fm", right: "term" },
  ]

  function runPlaceAction(entry, button) {
    var act = button === Qt.LeftButton ? entry.left
      : button === Qt.MiddleButton ? entry.middle
      : button === Qt.RightButton ? entry.right : undefined
    if (act === "fm") { root.closeRequested(); root.openFm(entry.dir) }
    else if (act === "term") { root.closeRequested(); root.openTerm(entry.dir) }
    else if (act === "agent") { root.closeRequested(); root.openAgent(entry.dir) }
    // No action defined: do nothing (menu stays open).
  }

  // Last path segment only (e.g. valid8); full path goes to the actions card.
  function shortFavorite(path) {
    var parts = String(path || "").split("/").filter(function(p) { return p.length > 0 })
    if (parts.length === 0) return String(path || "")
    return parts[parts.length - 1]
  }

  // Static places + divider + favorites. Favorites behave like Work:
  // left = file manager, middle = default agent, right = terminal.
  readonly property var placesWithFavorites: {
    var out = root.places.slice()
    var favs = Array.isArray(root.favorites) ? root.favorites : []
    if (favs.length > 0) {
      out.push({ divider: true })
      for (var i = 0; i < favs.length; i++) {
        out.push({
          label: root.shortFavorite(favs[i]),
          dir: favs[i],
          icon: "\uf07b",
          left: "fm",
          middle: "agent",
          right: "term"
        })
      }
    }
    return out
  }

  // Default file manager via XDG (inode/directory MIME): honors nautilus,
  // strata, flea, or whatever the user set — unlike omarchy-launch-nautilus.
  function openFm(dir) { Util.execDetached('xdg-open "' + dir + '"') }
  function openTerm(dir) { Util.execDetached('uwsm-app -- xdg-terminal-exec --dir="' + dir + '"') }
  function openAgent(dir) { Util.execDetached('uwsm-app -- xdg-terminal-exec --dir="' + dir + '" $(omarchy-default-agent)') }

  // Hovered place (drives the actions card). Cleared with a short delay so
  // sliding across dividers/spacing between rows doesn't flash the idle state.
  property var hoveredPlace: null
  Timer { id: hoverClear; interval: 120; onTriggered: root.hoveredPlace = null }
  function setHovered(entry, inside) {
    if (inside) { hoverClear.stop(); root.hoveredPlace = entry }
    else if (root.hoveredPlace === entry) hoverClear.restart()
  }

  readonly property var actionLabels: ({
    fm: "Open in file manager",
    term: "Open terminal here",
    agent: "Open coding agent here"
  })
  // Idle card: what the buttons do in general (middle only on dev folders).
  readonly property var idleActions: ({
    left: "Open in file manager",
    middle: "Coding agent (dev folders)",
    right: "Open terminal here"
  })

  readonly property color fg: root.bar ? root.bar.barForeground : Color.foreground

  Flickable {
    id: placesFlick
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: actionsCard.top
    anchors.margins: Style.space(8)
    contentHeight: placesColumn.height
    boundsBehavior: Flickable.StopAtBounds
    clip: true

  Column {
    id: placesColumn
    width: parent.width
    spacing: Style.space(2)

    Repeater {
      model: root.placesWithFavorites
      delegate: Item {
        required property var modelData
        width: parent.width
        height: modelData.divider ? Style.space(9) : Style.space(34)

        Rectangle {
          visible: !!modelData.divider
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          height: 1
          color: Util.alpha(root.fg, 0.15)
        }

        Item {
          visible: !modelData.divider
          anchors.fill: parent

          Rectangle {
            anchors.fill: parent
            radius: Style.cornerRadius
            color: Util.alpha(root.fg, placeMouse.containsMouse ? 0.08 : 0)
          }

          Text {
            id: placeIcon
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(30)
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            text: modelData.icon || ""
            color: root.fg
            opacity: placeMouse.containsMouse ? 1.0 : 0.75
            font.family: Style.font.family
            font.pixelSize: Style.font.iconLarge
          }

          Text {
            id: placeLabel
            anchors.left: placeIcon.right
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: modelData.label || ""
            color: root.fg
            opacity: placeMouse.containsMouse ? 1.0 : 0.75
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            font.weight: Font.Medium
            elide: Text.ElideRight
          }

          MouseArea {
            id: placeMouse
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onContainsMouseChanged: root.setHovered(modelData, containsMouse)
            onClicked: function(mouse) { root.runPlaceAction(modelData, mouse.button) }
          }
        }
      }
    }
  }
  }

  // Mouse actions card: always visible, updates with the hovered place so
  // the middle/right buttons are discoverable without trial and error.
  Rectangle {
    id: actionsCard
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: Style.space(8)
    height: cardColumn.implicitHeight + Style.space(16)
    radius: Style.cornerRadius
    color: Util.alpha(root.fg, 0.05)
    border.width: 1
    border.color: Util.alpha(root.fg, 0.12)

    Column {
      id: cardColumn
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(5)

      // Header: hovered place's full path, or a neutral title when idle.
      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: root.hoveredPlace ? (root.hoveredPlace.dir || "") : "Mouse actions"
        color: root.fg
        opacity: 0.6
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideMiddle
      }

      Repeater {
        model: ["left", "middle", "right"]
        delegate: Row {
          id: actionRow
          required property string modelData
          readonly property string act: root.hoveredPlace ? (root.hoveredPlace[modelData] || "") : ""
          readonly property string label: root.hoveredPlace
            ? (act ? (root.actionLabels[act] || act) : "Nothing")
            : root.idleActions[modelData]
          readonly property bool active: !root.hoveredPlace || act !== ""
          width: parent.width
          spacing: Style.space(8)
          opacity: active ? (root.hoveredPlace ? 1.0 : 0.7) : 0.35

          MouseGlyph {
            anchors.verticalCenter: parent.verticalCenter
            button: actionRow.modelData
            lit: actionRow.active && !!root.hoveredPlace
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - x
            textFormat: Text.PlainText
            text: actionRow.label
            color: root.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            font.italic: !actionRow.active
            elide: Text.ElideRight
          }
        }
      }
    }
  }

  // Tiny mouse drawing with one button highlighted (font-independent, so it
  // reads the same whatever Nerd Font the theme uses).
  component MouseGlyph: Item {
    id: glyph
    property string button: "left"
    property bool lit: false
    readonly property color ink: root.fg
    readonly property color hot: Color.accent
    width: Style.space(12)
    height: Style.space(17)

    readonly property real splitY: Math.round(height * 0.42)

    // Highlighted half (left/right): clip a full-size rounded body.
    Item {
      visible: glyph.button !== "middle"
      x: glyph.button === "right" ? Math.round(glyph.width / 2) : 0
      width: Math.round(glyph.width / 2)
      height: glyph.splitY
      clip: true
      Rectangle {
        x: -parent.x
        width: glyph.width
        height: glyph.height
        radius: glyph.width / 2
        color: glyph.lit ? glyph.hot : glyph.ink
        opacity: glyph.lit ? 1.0 : 0.55
      }
    }

    Rectangle {
      anchors.fill: parent
      radius: glyph.width / 2
      color: "transparent"
      border.width: 1
      border.color: glyph.ink
    }
    // Button split + palm line.
    Rectangle { x: Math.round(glyph.width / 2); y: 0; width: 1; height: glyph.splitY; color: glyph.ink }
    Rectangle { x: 0; y: glyph.splitY; width: glyph.width; height: 1; color: glyph.ink }
    // Wheel.
    Rectangle {
      x: Math.round(glyph.width / 2) - (glyph.button === "middle" ? 1 : 0)
      y: Math.round(glyph.splitY * 0.25)
      width: glyph.button === "middle" ? 3 : 1
      height: Math.round(glyph.splitY * 0.5)
      radius: 1
      color: glyph.button === "middle" ? (glyph.lit ? glyph.hot : glyph.ink) : glyph.ink
    }
  }
}
