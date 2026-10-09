import QtQuick
import qs.Commons

// Megadrive 6-button schematic. RetroArch mapping: B->b, A->y, C->a,
// X->l, Y->x, Z->r, Mode->select, Start->start.
Item {
  id: root

  property string activeKey: ""
  property var buttons: [
    { key: "up", label: "D-Pad Up" },
    { key: "down", label: "D-Pad Down" },
    { key: "left", label: "D-Pad Left" },
    { key: "right", label: "D-Pad Right" },
    { key: "b", label: "B" },
    { key: "y", label: "A" },
    { key: "a", label: "C" },
    { key: "x", label: "Y" },
    { key: "l", label: "X" },
    { key: "r", label: "Z" },
    { key: "select", label: "Mode" },
    { key: "start", label: "Start" }
  ]

  readonly property color line: Util.alpha(Color.foreground, 0.35)
  readonly property color dim: Util.alpha(Color.foreground, 0.06)

  implicitWidth: 320
  implicitHeight: 190

  function hot(keys) {
    return keys.indexOf(root.activeKey) >= 0
  }

  // Mode sits on the top-right shoulder (6-button pad); Start alone
  // in the center, clear of the face buttons.
  Rectangle {
    x: 228; y: 42; width: 40; height: 12; radius: 6
    color: root.hot(["select"]) ? Color.accent : root.dim
    border.width: 1; border.color: root.line
  }
  Text {
    x: 223; y: 26; width: 50; horizontalAlignment: Text.AlignHCenter
    text: "Mode"; color: Color.foreground; opacity: 0.6
    font.pixelSize: 9; font.family: Style.font.family
  }

  // Wide rounded body.
  Rectangle {
    x: 20; y: 50; width: 280; height: 100
    radius: 40
    color: root.dim
    border.width: 1
    border.color: root.line
  }

  // D-pad (left).
  Rectangle {
    x: 52; y: 91; width: 52; height: 18
    color: root.hot(["left", "right"]) ? Color.accent : root.dim
    border.width: 1; border.color: root.line
  }
  Rectangle {
    x: 69; y: 74; width: 18; height: 52
    color: root.hot(["up", "down"]) ? Color.accent : root.dim
    border.width: 1; border.color: root.line
  }
  Rectangle {
    x: 69; y: 91; width: 18; height: 18; radius: 9
    color: Util.alpha(Color.foreground, 0.25)
  }

  // 6 face buttons: top row X Y Z, bottom row A B C (bottom row
  // offset left, like the real pad).
  Repeater {
    model: [
      { key: "l", col: 0, row: 0, cap: "X" },
      { key: "x", col: 1, row: 0, cap: "Y" },
      { key: "r", col: 2, row: 0, cap: "Z" },
      { key: "y", col: 0, row: 1, cap: "A" },
      { key: "b", col: 1, row: 1, cap: "B" },
      { key: "a", col: 2, row: 1, cap: "C" }
    ]
    delegate: Item {
      required property var modelData
      x: 210 + modelData.col * 28 - modelData.row * 8 - 11
      y: 84 + modelData.row * 30 - 11
      width: 22; height: 22

      Rectangle {
        anchors.fill: parent
        radius: 11
        color: root.hot([modelData.key]) ? Color.accent : root.dim
        border.width: 1; border.color: root.line
      }
      Text {
        anchors.centerIn: parent
        text: modelData.cap
        color: Color.foreground
        font.pixelSize: 10
        font.family: Style.font.family
        font.bold: true
      }
    }
  }

  // Start pill, center.
  Rectangle {
    x: 128; y: 112; width: 34; height: 11; radius: 5
    color: root.hot(["start"]) ? Color.accent : root.dim
    border.width: 1; border.color: root.line
  }
  Text {
    x: 120; y: 126; width: 50; horizontalAlignment: Text.AlignHCenter
    text: "Start"; color: Color.foreground; opacity: 0.6
    font.pixelSize: 9; font.family: Style.font.family
  }
}
