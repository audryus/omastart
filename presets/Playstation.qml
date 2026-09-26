import QtQuick
import qs.Commons

// Playstation schematic. Retropad positions: bottom=Cross->b,
// right=Circle->a, left=Square->y, top=Triangle->x.
Item {
  id: root

  property string activeKey: ""
  property var buttons: [
    { key: "up", label: "D-Pad Up" },
    { key: "down", label: "D-Pad Down" },
    { key: "left", label: "D-Pad Left" },
    { key: "right", label: "D-Pad Right" },
    { key: "b", label: "Cross" },
    { key: "a", label: "Circle" },
    { key: "y", label: "Square" },
    { key: "x", label: "Triangle" },
    { key: "l", label: "L1" },
    { key: "r", label: "R1" },
    { key: "l2", label: "L2" },
    { key: "r2", label: "R2" },
    { key: "select", label: "Select" },
    { key: "start", label: "Start" },
    { key: "l3", label: "L3" },
    { key: "r3", label: "R3" },
    { key: "l_x_minus", label: "Left Stick Left" },
    { key: "l_x_plus", label: "Left Stick Right" },
    { key: "l_y_minus", label: "Left Stick Up" },
    { key: "l_y_plus", label: "Left Stick Down" },
    { key: "r_x_minus", label: "Right Stick Left" },
    { key: "r_x_plus", label: "Right Stick Right" },
    { key: "r_y_minus", label: "Right Stick Up" },
    { key: "r_y_plus", label: "Right Stick Down" }
  ]

  readonly property color line: Util.alpha(Color.foreground, 0.35)
  readonly property color dim: Util.alpha(Color.foreground, 0.06)

  implicitWidth: 320
  implicitHeight: 190

  function hot(keys) {
    return keys.indexOf(root.activeKey) >= 0
  }

  // Body + grips.
  Rectangle {
    x: 50; y: 45; width: 220; height: 95; radius: 30
    color: root.dim; border.width: 1; border.color: root.line
  }
  Rectangle {
    x: 58; y: 110; width: 34; height: 60; radius: 15; rotation: 12
    color: root.dim; border.width: 1; border.color: root.line
  }
  Rectangle {
    x: 228; y: 110; width: 34; height: 60; radius: 15; rotation: -12
    color: root.dim; border.width: 1; border.color: root.line
  }

  // Shoulders L1/R1 + triggers L2/R2.
  Repeater {
    model: [
      { key: "l", x: 84 }, { key: "r", x: 202 },
      { key: "l2", x: 84, y: 0 }, { key: "r2", x: 202, y: 0 }
    ]
    delegate: Rectangle {
      required property var modelData
      x: modelData.x; y: modelData.y !== undefined ? 22 : 34
      width: 34; height: 10; radius: 5
      color: root.hot([modelData.key]) ? Color.accent : root.dim
      border.width: 1; border.color: root.line
    }
  }
  Text {
    x: 76; y: 8; width: 50; horizontalAlignment: Text.AlignHCenter
    text: "L1/L2"; color: Color.foreground; opacity: 0.6
    font.pixelSize: 9; font.family: Style.font.family
  }
  Text {
    x: 194; y: 8; width: 50; horizontalAlignment: Text.AlignHCenter
    text: "R1/R2"; color: Color.foreground; opacity: 0.6
    font.pixelSize: 9; font.family: Style.font.family
  }

  // D-pad left.
  Rectangle {
    x: 72; y: 84; width: 48; height: 16
    color: root.hot(["left", "right"]) ? Color.accent : root.dim
    border.width: 1; border.color: root.line
  }
  Rectangle {
    x: 88; y: 68; width: 16; height: 48
    color: root.hot(["up", "down"]) ? Color.accent : root.dim
    border.width: 1; border.color: root.line
  }

  // Face symbols with captions.
  Repeater {
    model: [
      { key: "a", dx: 20, dy: 0, cap: "Circle" },
      { key: "b", dx: 0, dy: 20, cap: "Cross" },
      { key: "y", dx: -20, dy: 0, cap: "Square" },
      { key: "x", dx: 0, dy: -20, cap: "Tri" }
    ]
    delegate: Item {
      required property var modelData
      x: 222 + modelData.dx - 11
      y: 92 - 11 + modelData.dy
      width: 22; height: 22

      Rectangle {
        anchors.fill: parent
        radius: 11
        color: root.hot([modelData.key]) ? Color.accent : root.dim
        border.width: 1; border.color: root.line
      }
      Text {
        anchors.centerIn: parent
        text: modelData.cap.substring(0, 2)
        color: Color.foreground
        font.pixelSize: 9
        font.family: Style.font.family
        font.bold: true
      }
    }
  }

  // Sticks.
  Repeater {
    model: [
      { keys: ["l_x_minus", "l_x_plus", "l_y_minus", "l_y_plus", "l3"], x: 128, cap: "L3" },
      { keys: ["r_x_minus", "r_x_plus", "r_y_minus", "r_y_plus", "r3"], x: 170, cap: "R3" }
    ]
    delegate: Item {
      required property var modelData
      x: modelData.x; y: 108
      width: 28; height: 28

      Rectangle {
        anchors.fill: parent
        radius: 14
        color: root.hot(modelData.keys) ? Color.accent : root.dim
        border.width: 1; border.color: root.line
      }
      Rectangle {
        anchors.centerIn: parent
        width: 12; height: 12; radius: 6
        color: Util.alpha(Color.foreground, 0.3)
      }
      Text {
        anchors.top: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        text: modelData.cap
        color: Color.foreground; opacity: 0.6
        font.pixelSize: 9; font.family: Style.font.family
      }
    }
  }

  // Select / Start pills.
  Rectangle {
    x: 138; y: 66; width: 26; height: 9; radius: 4
    color: root.hot(["select"]) ? Color.accent : root.dim
    border.width: 1; border.color: root.line
  }
  Rectangle {
    x: 170; y: 66; width: 26; height: 9; radius: 4
    color: root.hot(["start"]) ? Color.accent : root.dim
    border.width: 1; border.color: root.line
  }
}
