import QtQuick
import qs.Commons

// Steam Deck schematic (face controls subset; trackpads decorative).
// Same retropad positions as Xbox: bottom=A->b, right=B->a,
// left=X->y, top=Y->x.
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

  // Wide body + trackpads (decorative).
  Rectangle {
    x: 25; y: 45; width: 270; height: 105; radius: 40
    color: root.dim; border.width: 1; border.color: root.line
  }
  Rectangle {
    x: 37; y: 78; width: 44; height: 44; radius: 8
    color: root.dim; border.width: 1; border.color: root.line
  }
  Rectangle {
    x: 239; y: 78; width: 44; height: 44; radius: 8
    color: root.dim; border.width: 1; border.color: root.line
  }
  Text {
    x: 37; y: 124; width: 44; horizontalAlignment: Text.AlignHCenter
    text: "pad"; color: Color.foreground; opacity: 0.45
    font.pixelSize: 9; font.family: Style.font.family
  }
  Text {
    x: 239; y: 124; width: 44; horizontalAlignment: Text.AlignHCenter
    text: "pad"; color: Color.foreground; opacity: 0.45
    font.pixelSize: 9; font.family: Style.font.family
  }

  // Shoulders + triggers.
  Repeater {
    model: [
      { key: "l", x: 100 }, { key: "r", x: 186 },
      { key: "l2", x: 100, y: 0 }, { key: "r2", x: 186, y: 0 }
    ]
    delegate: Rectangle {
      required property var modelData
      x: modelData.x; y: modelData.y !== undefined ? 24 : 36
      width: 34; height: 9; radius: 4
      color: root.hot([modelData.key]) ? Color.accent : root.dim
      border.width: 1; border.color: root.line
    }
  }

  // D-pad left-center.
  Rectangle {
    x: 96; y: 96; width: 40; height: 14
    color: root.hot(["left", "right"]) ? Color.accent : root.dim
    border.width: 1; border.color: root.line
  }
  Rectangle {
    x: 109; y: 83; width: 14; height: 40
    color: root.hot(["up", "down"]) ? Color.accent : root.dim
    border.width: 1; border.color: root.line
  }

  // Face diamond: right=B, bottom=A, left=X, top=Y.
  Repeater {
    model: [
      { key: "a", dx: 19, dy: 0, cap: "B" },
      { key: "b", dx: 0, dy: 19, cap: "A" },
      { key: "y", dx: -19, dy: 0, cap: "X" },
      { key: "x", dx: 0, dy: -19, cap: "Y" }
    ]
    delegate: Item {
      required property var modelData
      x: 207 + modelData.dx - 10
      y: 103 - 10 + modelData.dy
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

  // Sticks.
  Repeater {
    model: [
      { keys: ["l_x_minus", "l_x_plus", "l_y_minus", "l_y_plus", "l3"], x: 140, cap: "L3" },
      { keys: ["r_x_minus", "r_x_plus", "r_y_minus", "r_y_plus", "r3"], x: 172, cap: "R3" }
    ]
    delegate: Item {
      required property var modelData
      x: modelData.x; y: 82
      width: 26; height: 26

      Rectangle {
        anchors.fill: parent
        radius: 13
        color: root.hot(modelData.keys) ? Color.accent : root.dim
        border.width: 1; border.color: root.line
      }
      Rectangle {
        anchors.centerIn: parent
        width: 11; height: 11; radius: 5
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
    x: 146; y: 122; width: 22; height: 8; radius: 4
    color: root.hot(["select"]) ? Color.accent : root.dim
    border.width: 1; border.color: root.line
  }
  Rectangle {
    x: 172; y: 122; width: 22; height: 8; radius: 4
    color: root.hot(["start"]) ? Color.accent : root.dim
    border.width: 1; border.color: root.line
  }
}
