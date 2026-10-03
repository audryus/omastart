import QtQuick
import qs.Commons

// Game Boy / Game Boy Color schematic (same buttons on both). Retropad
// positions follow the libretro cores (Gambatte, SameBoy, mGBA):
// A->a, B->b, Select->select, Start->start.
Item {
  id: root

  property string activeKey: ""
  property var buttons: [
    { key: "up", label: "D-Pad Up" },
    { key: "down", label: "D-Pad Down" },
    { key: "left", label: "D-Pad Left" },
    { key: "right", label: "D-Pad Right" },
    { key: "b", label: "B" },
    { key: "a", label: "A" },
    { key: "select", label: "Select" },
    { key: "start", label: "Start" }
  ]

  readonly property color line: Util.alpha(Color.foreground, 0.35)
  readonly property color dim: Util.alpha(Color.foreground, 0.06)

  implicitWidth: 320
  implicitHeight: 190

  function hot(keys) {
    return keys.indexOf(root.activeKey) >= 0
  }

  // Portrait body.
  Rectangle {
    x: 110; y: 4; width: 100; height: 182; radius: 8
    color: root.dim; border.width: 1; border.color: root.line
  }

  // Screen.
  Rectangle {
    x: 122; y: 14; width: 76; height: 62; radius: 4
    color: Util.alpha(Color.foreground, 0.12)
    border.width: 1; border.color: root.line
  }

  // D-pad.
  Rectangle {
    x: 120; y: 106; width: 36; height: 12
    color: root.hot(["left", "right"]) ? Color.accent : root.dim
    border.width: 1; border.color: root.line
  }
  Rectangle {
    x: 132; y: 94; width: 12; height: 36
    color: root.hot(["up", "down"]) ? Color.accent : root.dim
    border.width: 1; border.color: root.line
  }

  // B (lower left) and A (upper right), tilted like the real pad.
  Repeater {
    model: [
      { key: "b", x: 166, y: 106, cap: "B" },
      { key: "a", x: 186, y: 96, cap: "A" }
    ]
    delegate: Item {
      required property var modelData
      x: modelData.x; y: modelData.y
      width: 18; height: 18

      Rectangle {
        anchors.fill: parent
        radius: 9
        color: root.hot([modelData.key]) ? Color.accent : root.dim
        border.width: 1; border.color: root.line
      }
      Text {
        anchors.centerIn: parent
        text: modelData.cap
        color: Color.foreground
        font.pixelSize: 9
        font.family: Style.font.family
        font.bold: true
      }
    }
  }

  // Select / Start pills.
  Rectangle {
    x: 136; y: 146; width: 20; height: 7; radius: 3; rotation: -25
    color: root.hot(["select"]) ? Color.accent : root.dim
    border.width: 1; border.color: root.line
  }
  Rectangle {
    x: 162; y: 146; width: 20; height: 7; radius: 3; rotation: -25
    color: root.hot(["start"]) ? Color.accent : root.dim
    border.width: 1; border.color: root.line
  }
  Text {
    x: 126; y: 156; width: 40; horizontalAlignment: Text.AlignHCenter
    text: "Select"; color: Color.foreground; opacity: 0.6
    font.pixelSize: 8; font.family: Style.font.family
  }
  Text {
    x: 152; y: 156; width: 40; horizontalAlignment: Text.AlignHCenter
    text: "Start"; color: Color.foreground; opacity: 0.6
    font.pixelSize: 8; font.family: Style.font.family
  }
}
