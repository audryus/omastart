import QtQuick
import qs.Commons

// N64 trident schematic. Mapping follows the stock DragonRise_N64 profile:
// A->b, B->y, Z->l2, C-buttons on the right analog axes, stick on the left.
Item {
  id: root

  property string activeKey: ""
  property var buttons: [
    { key: "up", label: "D-Pad Up" },
    { key: "down", label: "D-Pad Down" },
    { key: "left", label: "D-Pad Left" },
    { key: "right", label: "D-Pad Right" },
    { key: "b", label: "A" },
    { key: "y", label: "B" },
    // Canonical duplicate (Hyperkin profile): press the SAME physical B
    // button again — it fills retropad A too, otherwise B does nothing
    // in-game and menu nav breaks.
    // dupOf: the core remap must leave this key alone, or the template's
    // own remap of it (btn_a -> C-Left) fires alongside B.
    { key: "a", label: "B (press again)", dupOf: "y" },
    { key: "l", label: "L" },
    { key: "r", label: "R" },
    { key: "l2", label: "Z" },
    { key: "start", label: "Start" },
    { key: "l_x_minus", label: "Stick Left" },
    { key: "l_x_plus", label: "Stick Right" },
    { key: "l_y_minus", label: "Stick Up" },
    { key: "l_y_plus", label: "Stick Down" },
    { key: "r_x_minus", label: "C-Left" },
    { key: "r_x_plus", label: "C-Right" },
    { key: "r_y_minus", label: "C-Up" },
    { key: "r_y_plus", label: "C-Down" }
  ]

  readonly property color line: Util.alpha(Color.foreground, 0.35)
  readonly property color dim: Util.alpha(Color.foreground, 0.06)

  implicitWidth: 320
  implicitHeight: 190

  function hot(keys) {
    return keys.indexOf(root.activeKey) >= 0
  }

  // L / R shoulders, behind the top bar.
  Rectangle {
    x: 38; y: 33; width: 44; height: 11; radius: 5
    color: root.hot(["l"]) ? Color.accent : root.dim
    border.width: 1; border.color: root.line
  }
  Rectangle {
    x: 238; y: 33; width: 44; height: 11; radius: 5
    color: root.hot(["r"]) ? Color.accent : root.dim
    border.width: 1; border.color: root.line
  }
  Text {
    x: 35; y: 20; width: 50; horizontalAlignment: Text.AlignHCenter
    text: "L"; color: Color.foreground; opacity: 0.6
    font.pixelSize: 9; font.family: Style.font.family
  }
  Text {
    x: 235; y: 20; width: 50; horizontalAlignment: Text.AlignHCenter
    text: "R"; color: Color.foreground; opacity: 0.6
    font.pixelSize: 9; font.family: Style.font.family
  }

  // Trident: three prongs hanging from a wide top bar. The fills are
  // translucent, so the prongs are clipped at the bar's straight bottom
  // edge instead of showing their tops through it.
  Item {
    x: 0; y: 105; width: 320; height: 85
    clip: true

    Repeater {
      model: [
        { x: 40, h: 92 }, { x: 134, h: 100 }, { x: 228, h: 92 }
      ]
      delegate: Rectangle {
        required property var modelData
        x: modelData.x; y: 80 - 105
        width: 52; height: modelData.h; radius: 24
        color: root.dim; border.width: 1; border.color: root.line
      }
    }
  }
  Rectangle {
    x: 24; y: 44; width: 272; height: 62; radius: 22
    color: root.dim; border.width: 1; border.color: root.line
  }

  // D-pad, top of the left prong.
  Rectangle {
    x: 46; y: 69; width: 38; height: 13
    color: root.hot(["left", "right"]) ? Color.accent : root.dim
    border.width: 1; border.color: root.line
  }
  Rectangle {
    x: 58.5; y: 56.5; width: 13; height: 38
    color: root.hot(["up", "down"]) ? Color.accent : root.dim
    border.width: 1; border.color: root.line
  }

  // Start, center of the top bar.
  Rectangle {
    x: 147; y: 54; width: 26; height: 11; radius: 5
    color: root.hot(["start"]) ? Color.accent : root.dim
    border.width: 1; border.color: root.line
  }
  Text {
    x: 135; y: 66; width: 50; horizontalAlignment: Text.AlignHCenter
    text: "Start"; color: Color.foreground; opacity: 0.6
    font.pixelSize: 9; font.family: Style.font.family
  }

  // Analog stick, center prong.
  Rectangle {
    x: 140; y: 90; width: 40; height: 40; radius: 20
    color: root.hot(["l_x_minus", "l_x_plus", "l_y_minus", "l_y_plus"]) ? Color.accent : root.dim
    border.width: 1; border.color: root.line
  }
  Rectangle {
    x: 150; y: 100; width: 20; height: 20; radius: 10
    color: Util.alpha(Color.foreground, 0.25)
  }
  Text {
    x: 135; y: 132; width: 50; horizontalAlignment: Text.AlignHCenter
    text: "Stick"; color: Color.foreground; opacity: 0.6
    font.pixelSize: 9; font.family: Style.font.family
  }

  // Z trigger sits under the center prong; drawn on its lower half.
  Rectangle {
    x: 146; y: 150; width: 28; height: 11; radius: 5
    color: root.hot(["l2"]) ? Color.accent : root.dim
    border.width: 1; border.color: root.line
  }
  Text {
    x: 135; y: 162; width: 50; horizontalAlignment: Text.AlignHCenter
    text: "Z"; color: Color.foreground; opacity: 0.6
    font.pixelSize: 9; font.family: Style.font.family
  }

  // A / B, lower-left of the right side.
  Repeater {
    model: [
      { key: "b", cx: 234, cy: 92, cap: "A" },
      { key: "y", cx: 210, cy: 74, cap: "B" }
    ]
    delegate: Item {
      required property var modelData
      x: modelData.cx - 11; y: modelData.cy - 11
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

  // C-buttons diamond, upper-right.
  Repeater {
    model: [
      { key: "r_x_plus", dx: 14, dy: 0 },
      { key: "r_x_minus", dx: -14, dy: 0 },
      { key: "r_y_minus", dx: 0, dy: -14 },
      { key: "r_y_plus", dx: 0, dy: 14 }
    ]
    delegate: Rectangle {
      required property var modelData
      x: 266 + modelData.dx - 7
      y: 70 + modelData.dy - 7
      width: 14; height: 14; radius: 7
      color: root.hot([modelData.key]) ? Color.accent : Qt.rgba(0.9, 0.75, 0.1, 0.35)
      border.width: 1; border.color: root.line
    }
  }
  Text {
    x: 259; y: 64; width: 14; horizontalAlignment: Text.AlignHCenter
    text: "C"; color: Color.foreground; opacity: 0.6
    font.pixelSize: 9; font.family: Style.font.family
  }
}
