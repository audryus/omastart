import QtQuick
import qs.Commons

// Xbox schematic. Retropad positions: bottom=A->b, right=B->a,
// left=X->y, top=Y->x (labels match the stock X-Box profile).
Item {
  id: root

  property string activeKey: ""
  property var buttons: [
    { key: "up", label: "D-Pad Up" },
    { key: "down", label: "D-Pad Down" },
    { key: "left", label: "D-Pad Left" },
    { key: "right", label: "D-Pad Right" },
    { key: "b", label: "A" },
    { key: "a", label: "B" },
    { key: "y", label: "X" },
    { key: "x", label: "Y" },
    { key: "l", label: "LB" },
    { key: "r", label: "RB" },
    { key: "l2", label: "LT" },
    { key: "r2", label: "RT" },
    { key: "select", label: "View" },
    { key: "start", label: "Menu" },
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
    x: 55; y: 40; width: 210; height: 100; radius: 34
    color: root.dim; border.width: 1; border.color: root.line
  }
  Rectangle {
    x: 62; y: 108; width: 36; height: 62; radius: 16; rotation: 14
    color: root.dim; border.width: 1; border.color: root.line
  }
  Rectangle {
    x: 222; y: 108; width: 36; height: 62; radius: 16; rotation: -14
    color: root.dim; border.width: 1; border.color: root.line
  }
  // Guide button.
  Rectangle {
    x: 150; y: 56; width: 20; height: 20; radius: 10
    color: root.dim; border.width: 1; border.color: root.line
  }

  // Shoulders + triggers.
  Repeater {
    model: [
      { key: "l", x: 88 }, { key: "r", x: 198 },
      { key: "l2", x: 88, y: 0 }, { key: "r2", x: 198, y: 0 }
    ]
    delegate: Rectangle {
      required property var modelData
      x: modelData.x; y: modelData.y !== undefined ? 18 : 30
      width: 34; height: 10; radius: 5
      color: root.hot([modelData.key]) ? Color.accent : root.dim
      border.width: 1; border.color: root.line
    }
  }
  Text {
    x: 80; y: 4; width: 50; horizontalAlignment: Text.AlignHCenter
    text: "LB/LT"; color: Color.foreground; opacity: 0.6
    font.pixelSize: 9; font.family: Style.font.family
  }
  Text {
    x: 190; y: 4; width: 50; horizontalAlignment: Text.AlignHCenter
    text: "RB/RT"; color: Color.foreground; opacity: 0.6
    font.pixelSize: 9; font.family: Style.font.family
  }

  // D-pad (lower-left on Xbox).
  Rectangle {
    x: 84; y: 104; width: 44; height: 15
    color: root.hot(["left", "right"]) ? Color.accent : root.dim
    border.width: 1; border.color: root.line
  }
  Rectangle {
    x: 98; y: 90; width: 15; height: 44
    color: root.hot(["up", "down"]) ? Color.accent : root.dim
    border.width: 1; border.color: root.line
  }

  // Face diamond: right=B, bottom=A, left=X, top=Y.
  Repeater {
    model: [
      { key: "a", dx: 20, dy: 0, cap: "B" },
      { key: "b", dx: 0, dy: 20, cap: "A" },
      { key: "y", dx: -20, dy: 0, cap: "X" },
      { key: "x", dx: 0, dy: -20, cap: "Y" }
    ]
    delegate: Item {
      required property var modelData
      x: 218 + modelData.dx - 11
      y: 82 - 11 + modelData.dy
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

  // Sticks: left upper-center, right lower-center.
  Repeater {
    model: [
      { keys: ["l_x_minus", "l_x_plus", "l_y_minus", "l_y_plus", "l3"], x: 128, y: 62, cap: "L3" },
      { keys: ["r_x_minus", "r_x_plus", "r_y_minus", "r_y_plus", "r3"], x: 164, y: 102, cap: "R3" }
    ]
    delegate: Item {
      required property var modelData
      x: modelData.x; y: modelData.y
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

  // View / Menu pills.
  Rectangle {
    x: 132; y: 96; width: 24; height: 9; radius: 4
    color: root.hot(["select"]) ? Color.accent : root.dim
    border.width: 1; border.color: root.line
  }
  Rectangle {
    x: 164; y: 96; width: 24; height: 9; radius: 4
    color: root.hot(["start"]) ? Color.accent : root.dim
    border.width: 1; border.color: root.line
  }
}
