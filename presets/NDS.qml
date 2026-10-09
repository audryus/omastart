import QtQuick
import qs.Commons

// Nintendo DS schematic (open clamshell; screens decorative). Retropad
// positions follow melonDS/DeSmuME: A->a, B->b, X->x, Y->y, L->l, R->r,
// Select->select, Start->start.
Item {
  id: root

  property string activeKey: ""
  property var buttons: [
    { key: "up", label: "D-Pad Up" },
    { key: "down", label: "D-Pad Down" },
    { key: "left", label: "D-Pad Left" },
    { key: "right", label: "D-Pad Right" },
    { key: "a", label: "A" },
    { key: "b", label: "B" },
    { key: "x", label: "X" },
    { key: "y", label: "Y" },
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

  // Lid with the top screen.
  Rectangle {
    x: 44; y: 4; width: 232; height: 46; radius: 10
    color: root.dim; border.width: 1; border.color: root.line
  }
  Rectangle {
    x: 120; y: 10; width: 80; height: 36; radius: 3
    color: Util.alpha(Color.foreground, 0.03); border.width: 1; border.color: root.line
  }

  // Shoulders, between the lid and the base.
  Rectangle {
    x: 26; y: 51; width: 54; height: 9; radius: 4
    color: root.hot(["l"]) ? Color.accent : root.dim
    border.width: 1; border.color: root.line
  }
  Rectangle {
    x: 240; y: 51; width: 54; height: 9; radius: 4
    color: root.hot(["r"]) ? Color.accent : root.dim
    border.width: 1; border.color: root.line
  }

  // Base with the touch screen.
  Rectangle {
    x: 20; y: 60; width: 280; height: 124; radius: 16
    color: root.dim; border.width: 1; border.color: root.line
  }
  Rectangle {
    x: 116; y: 68; width: 88; height: 66; radius: 3
    color: Util.alpha(Color.foreground, 0.03); border.width: 1; border.color: root.line
  }
  Text {
    x: 116; y: 136; width: 88; horizontalAlignment: Text.AlignHCenter
    text: "touch"; color: Color.foreground; opacity: 0.45
    font.pixelSize: 9; font.family: Style.font.family
  }
  Text {
    x: 26; y: 64; width: 54; horizontalAlignment: Text.AlignHCenter
    text: "L"; color: Color.foreground; opacity: 0.6
    font.pixelSize: 9; font.family: Style.font.family
  }
  Text {
    x: 240; y: 64; width: 54; horizontalAlignment: Text.AlignHCenter
    text: "R"; color: Color.foreground; opacity: 0.6
    font.pixelSize: 9; font.family: Style.font.family
  }

  // D-pad, left of the touch screen.
  Rectangle {
    x: 46; y: 101; width: 42; height: 14
    color: root.hot(["left", "right"]) ? Color.accent : root.dim
    border.width: 1; border.color: root.line
  }
  Rectangle {
    x: 60; y: 87; width: 14; height: 42
    color: root.hot(["up", "down"]) ? Color.accent : root.dim
    border.width: 1; border.color: root.line
  }

  // Face diamond: top=X, right=A, bottom=B, left=Y.
  Repeater {
    model: [
      { key: "x", dx: 0, dy: -17, cap: "X" },
      { key: "a", dx: 17, dy: 0, cap: "A" },
      { key: "b", dx: 0, dy: 17, cap: "B" },
      { key: "y", dx: -17, dy: 0, cap: "Y" }
    ]
    delegate: Item {
      required property var modelData
      x: 256 + modelData.dx - 10
      y: 108 + modelData.dy - 10
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

  // Start / Select, below the face buttons.
  Repeater {
    model: [
      { key: "start", x: 232, cap: "Start" },
      { key: "select", x: 258, cap: "Select" }
    ]
    delegate: Item {
      required property var modelData
      x: modelData.x; y: 146
      width: 22; height: 9

      Rectangle {
        anchors.fill: parent
        radius: 4
        color: root.hot([modelData.key]) ? Color.accent : root.dim
        border.width: 1; border.color: root.line
      }
      Text {
        anchors.top: parent.bottom
        anchors.topMargin: 2
        anchors.horizontalCenter: parent.horizontalCenter
        text: modelData.cap
        color: Color.foreground; opacity: 0.6
        font.pixelSize: 8; font.family: Style.font.family
      }
    }
  }
}
