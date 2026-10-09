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

  // Shoulders (LB/RB) with triggers (LT/RT) behind them.
  Repeater {
    model: [
      { key: "l2", x: 80, y: 16 }, { key: "r2", x: 206, y: 16 },
      { key: "l", x: 80, y: 29 }, { key: "r", x: 206, y: 29 }
    ]
    delegate: Rectangle {
      required property var modelData
      x: modelData.x; y: modelData.y
      width: 34; height: 10; radius: 5
      color: root.hot([modelData.key]) ? Color.accent : root.dim
      border.width: 1; border.color: root.line
    }
  }
  Text {
    x: 72; y: 2; width: 50; horizontalAlignment: Text.AlignHCenter
    text: "LB/LT"; color: Color.foreground; opacity: 0.6
    font.pixelSize: 9; font.family: Style.font.family
  }
  Text {
    x: 198; y: 2; width: 50; horizontalAlignment: Text.AlignHCenter
    text: "RB/RT"; color: Color.foreground; opacity: 0.6
    font.pixelSize: 9; font.family: Style.font.family
  }

  // Grips, clipped at the body's bottom edge (translucent fills would
  // otherwise show their tops through the body).
  Item {
    x: 0; y: 137; width: 320; height: 53
    clip: true

    Rectangle {
      x: 64; y: 92 - 137; width: 40; height: 82; radius: 18; rotation: 16
      color: root.dim; border.width: 1; border.color: root.line
    }
    Rectangle {
      x: 216; y: 92 - 137; width: 40; height: 82; radius: 18; rotation: -16
      color: root.dim; border.width: 1; border.color: root.line
    }
  }

  // Body.
  Rectangle {
    x: 50; y: 38; width: 220; height: 102; radius: 30
    color: root.dim; border.width: 1; border.color: root.line
  }

  // Guide button, top center.
  Rectangle {
    x: 150; y: 46; width: 20; height: 20; radius: 10
    color: root.dim; border.width: 1; border.color: root.line
  }

  // D-pad, lower-left inner.
  Rectangle {
    x: 112; y: 103.5; width: 38; height: 13
    color: root.hot(["left", "right"]) ? Color.accent : root.dim
    border.width: 1; border.color: root.line
  }
  Rectangle {
    x: 124.5; y: 91; width: 13; height: 38
    color: root.hot(["up", "down"]) ? Color.accent : root.dim
    border.width: 1; border.color: root.line
  }

  // Face diamond, upper-right: right=B, bottom=A, left=X, top=Y.
  Repeater {
    model: [
      { key: "a", dx: 18, dy: 0, cap: "B" },
      { key: "b", dx: 0, dy: 18, cap: "A" },
      { key: "y", dx: -18, dy: 0, cap: "X" },
      { key: "x", dx: 0, dy: -18, cap: "Y" }
    ]
    delegate: Item {
      required property var modelData
      x: 224 + modelData.dx - 10
      y: 74 + modelData.dy - 10
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
        font.pixelSize: 10
        font.family: Style.font.family
        font.bold: true
      }
    }
  }

  // Sticks: left upper-left, right lower-right inner.
  Repeater {
    model: [
      { keys: ["l_x_minus", "l_x_plus", "l_y_minus", "l_y_plus", "l3"], cx: 96, cy: 72, cap: "L3" },
      { keys: ["r_x_minus", "r_x_plus", "r_y_minus", "r_y_plus", "r3"], cx: 188, cy: 108, cap: "R3" }
    ]
    delegate: Item {
      required property var modelData
      x: modelData.cx - 14; y: modelData.cy - 14
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

  // View / Menu pills, either side of the guide.
  Rectangle {
    x: 128; y: 72; width: 20; height: 9; radius: 4
    color: root.hot(["select"]) ? Color.accent : root.dim
    border.width: 1; border.color: root.line
  }
  Rectangle {
    x: 172; y: 72; width: 20; height: 9; radius: 4
    color: root.hot(["start"]) ? Color.accent : root.dim
    border.width: 1; border.color: root.line
  }
}
