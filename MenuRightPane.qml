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
  width: parent.width * 0.3
  radius: Style.cornerRadius
  color: "transparent"

  readonly property string homeDir: Quickshell.env("HOME")
  readonly property var places: [
    { label: "My Computer", dir: homeDir, icon: "\uf015" },
    { divider: true },
    { label: "Projects", dir: homeDir + "/Projects", icon: "\uf121" },
    { label: "Work", dir: homeDir + "/Work", special: "work", icon: "\uf0b1" },
    { divider: true },
    { label: "Documents", dir: homeDir + "/Documents", icon: "\uf15c" },
    { label: "Downloads", dir: homeDir + "/Downloads", icon: "\uf019" },
    { label: "Games", dir: homeDir + "/Games", icon: "\uf11b" },
    { divider: true },
    { label: "Music", dir: homeDir + "/Music", icon: "\uf001" },
    { label: "Pictures", dir: homeDir + "/Pictures", icon: "\uf03e" },
    { label: "Videos", dir: homeDir + "/Videos", icon: "\uf008" },
  ]

  // Last path segment only (e.g. valid8); full path goes to the tooltip.
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
          tip: true,
          agent: true
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

  Column {
    anchors.fill: parent
    anchors.margins: Style.space(8)
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
          color: Util.alpha(root.bar ? root.bar.barForeground : Color.foreground, 0.15)
        }

        Item {
          visible: !modelData.divider
          anchors.fill: parent

          Text {
            id: placeIcon
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(30)
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            text: modelData.icon || ""
            color: root.bar ? root.bar.barForeground : Color.foreground
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
            color: root.bar ? root.bar.barForeground : Color.foreground
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
            onClicked: function(mouse) {
              var dir = modelData.dir
              var special = modelData.special
              root.closeRequested()
              if (mouse.button === Qt.RightButton) root.openTerm(dir)
              else if (mouse.button === Qt.MiddleButton) {
                if (special === "work" || modelData.agent) root.openAgent(dir)
              } else root.openFm(dir)
            }
          }

          PanelToolTip {
            visible: placeMouse.containsMouse && !!modelData.tip
            text: modelData.dir || ""
          }
        }
      }
    }
  }
}
