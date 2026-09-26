import QtQuick
import qs.Commons

// SNES schematic. Retropad positions match 1:1 (bottom=B, right=A,
// left=Y, top=X). activeKey highlights the shape being bound.
Item {
  id: root

  property string activeKey: ""
  property var buttons: [
    { key: "up", label: "D-Pad Up" },
    { key: "down", label: "D-Pad Down" },
    { key: "left", label: "D-Pad Left" },
    { key: "right", label: "D-Pad Right" },
    { key: "select", label: "Select" },
    { key: "start", label: "Start" },
    { key: "b", label: "B" },
    { key: "a", label: "A" },
    { key: "y", label: "Y" },
    { key: "x", label: "X" },
    { key: "l", label: "L" },
    { key: "r", label: "R" }
  ]

  readonly property color line: Util.alpha(Color.foreground, 0.35)
  readonly property color dim: Util.alpha(Color.foreground, 0.06)

  implicitWidth: 320
  implicitHeight: 190

  function hot(keys) {
    return keys.indexOf(root.activeKey) >= 0
  }

  // Body.
  Rectangle {
    x: 30; y: 45; width: 260; height: 105
    radius: 24
    color: root.dim
    border.width: 1
    border.color: root.line
  }

  // Shoulders.
  Rectangle {
    x: 70; y: 36; width: 44; height: 12; radius: 6
    color: root.hot(["l"]) ? Color.accent : root.dim
    border.width: 1; border.color: root.line
  }
  Rectangle {
    x: 206; y: 36; width: 44; height: 12; radius: 6
    color: root.hot(["r"]) ? Color.accent : root.dim
    border.width: 1; border.color: root.line
  }
  Text {
    x: 70; y: 20; width: 44; horizontalAlignment: Text.AlignHCenter
    text: "L"; color: Color.foreground; font.pixelSize: 10; font.family: Style.font.family
  }
  Text {
    x: 206; y: 20; width: 44; horizontalAlignment: Text.AlignHCenter
    text: "R"; color: Color.foreground; font.pixelSize: 10; font.family: Style.font.family
  }

  // D-pad (plus shape).
  Rectangle {
    x: 68; y: 88; width: 56; height: 18
    color: root.hot(["left", "right"]) ? Color.accent : root.dim
    border.width: 1; border.color: root.line
  }
  Rectangle {
    x: 87; y: 69; width: 18; height: 56
    color: root.hot(["up", "down"]) ? Color.accent : root.dim
    border.width: 1; border.color: root.line
  }
  Rectangle {
    x: 87; y: 88; width: 18; height: 18
    color: Util.alpha(Color.foreground, 0.25)
  }

  // Face diamond: right=A, bottom=B, left=Y, top=X.
  Repeater {
    model: [
      { key: "a", dx: 20, dy: 0, cap: "A" },
      { key: "b", dx: 0, dy: 20, cap: "B" },
      { key: "y", dx: -20, dy: 0, cap: "Y" },
      { key: "x", dx: 0, dy: -20, cap: "X" }
    ]
    delegate: Item {
      required property var modelData
      x: 232 + modelData.dx - 11
      y: 97 - 11 + modelData.dy
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

  // Select / Start pills.
  Rectangle {
    x: 138; y: 108; width: 30; height: 10; radius: 5
    color: root.hot(["select"]) ? Color.accent : root.dim
    border.width: 1; border.color: root.line
  }
  Rectangle {
    x: 176; y: 108; width: 30; height: 10; radius: 5
    color: root.hot(["start"]) ? Color.accent : root.dim
    border.width: 1; border.color: root.line
  }
  Text {
    x: 128; y: 122; width: 50; horizontalAlignment: Text.AlignHCenter
    text: "Select"; color: Color.foreground; opacity: 0.6
    font.pixelSize: 9; font.family: Style.font.family
  }
  Text {
    x: 166; y: 122; width: 50; horizontalAlignment: Text.AlignHCenter
    text: "Start"; color: Color.foreground; opacity: 0.6
    font.pixelSize: 9; font.family: Style.font.family
  }
}
