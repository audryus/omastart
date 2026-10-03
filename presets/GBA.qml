import QtQuick
import qs.Commons

// Game Boy Advance schematic: the Game Boy buttons plus L/R shoulders.
// Retropad positions follow mGBA: A->a, B->b, L->l, R->r,
// Select->select, Start->start.
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
    { key: "l", label: "L" },
    { key: "r", label: "R" },
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

  // Shoulders, behind the body's top corners.
  Rectangle {
    x: 34; y: 38; width: 60; height: 16; radius: 8
    color: root.hot(["l"]) ? Color.accent : root.dim
    border.width: 1; border.color: root.line
  }
  Rectangle {
    x: 226; y: 38; width: 60; height: 16; radius: 8
    color: root.hot(["r"]) ? Color.accent : root.dim
    border.width: 1; border.color: root.line
  }
  Text {
    x: 34; y: 22; width: 60; horizontalAlignment: Text.AlignHCenter
    text: "L"; color: Color.foreground; font.pixelSize: 10; font.family: Style.font.family
  }
  Text {
    x: 226; y: 22; width: 60; horizontalAlignment: Text.AlignHCenter
    text: "R"; color: Color.foreground; font.pixelSize: 10; font.family: Style.font.family
  }

  // Landscape body.
  Rectangle {
    x: 24; y: 48; width: 272; height: 112; radius: 40
    color: root.dim; border.width: 1; border.color: root.line
  }

  // Screen.
  Rectangle {
    x: 110; y: 62; width: 100; height: 68; radius: 4
    color: Util.alpha(Color.foreground, 0.12)
    border.width: 1; border.color: root.line
  }

  // D-pad.
  Rectangle {
    x: 50; y: 86; width: 40; height: 13
    color: root.hot(["left", "right"]) ? Color.accent : root.dim
    border.width: 1; border.color: root.line
  }
  Rectangle {
    x: 63; y: 73; width: 14; height: 39
    color: root.hot(["up", "down"]) ? Color.accent : root.dim
    border.width: 1; border.color: root.line
  }

  // B (lower left) and A (upper right).
  Repeater {
    model: [
      { key: "b", x: 232, y: 92, cap: "B" },
      { key: "a", x: 256, y: 78, cap: "A" }
    ]
    delegate: Item {
      required property var modelData
      x: modelData.x; y: modelData.y
      width: 20; height: 20

      Rectangle {
        anchors.fill: parent
        radius: 10
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

  // Start / Select, stacked under the D-pad as on the GBA.
  Rectangle {
    x: 60; y: 124; width: 9; height: 9; radius: 4.5
    color: root.hot(["start"]) ? Color.accent : root.dim
    border.width: 1; border.color: root.line
  }
  Rectangle {
    x: 60; y: 138; width: 9; height: 9; radius: 4.5
    color: root.hot(["select"]) ? Color.accent : root.dim
    border.width: 1; border.color: root.line
  }
  Text {
    x: 73; y: 122; text: "Start"; color: Color.foreground; opacity: 0.6
    font.pixelSize: 8; font.family: Style.font.family
  }
  Text {
    x: 73; y: 136; text: "Select"; color: Color.foreground; opacity: 0.6
    font.pixelSize: 8; font.family: Style.font.family
  }
}
