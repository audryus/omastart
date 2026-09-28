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

  // Trident: left prong, center grip, right prong.
  Rectangle {
    x: 60; y: 50; width: 44; height: 120; radius: 20
    color: root.dim; border.width: 1; border.color: root.line
  }
  Rectangle {
    x: 138; y: 40; width: 44; height: 130; radius: 20
    color: root.dim; border.width: 1; border.color: root.line
  }
  Rectangle {
    x: 216; y: 50; width: 44; height: 120; radius: 20
    color: root.dim; border.width: 1; border.color: root.line
  }
  // Top bar joining the prongs.
  Rectangle {
    x: 60; y: 40; width: 200; height: 34; radius: 16
    color: root.dim; border.width: 1; border.color: root.line
  }

  // D-pad on the left prong.
  Rectangle {
    x: 66; y: 100; width: 32; height: 12
    color: root.hot(["left", "right"]) ? Color.accent : root.dim
    border.width: 1; border.color: root.line
  }
  Rectangle {
    x: 76; y: 90; width: 12; height: 32
    color: root.hot(["up", "down"]) ? Color.accent : root.dim
    border.width: 1; border.color: root.line
  }

  // Analog stick, center grip.
  Rectangle {
    x: 138; y: 88; width: 44; height: 44; radius: 22
    color: root.hot(["l_x_minus", "l_x_plus", "l_y_minus", "l_y_plus"]) ? Color.accent : root.dim
    border.width: 1; border.color: root.line
  }
  Rectangle {
    x: 149; y: 99; width: 22; height: 22; radius: 11
    color: Util.alpha(Color.foreground, 0.25)
  }
  Text {
    x: 138; y: 136; width: 44; horizontalAlignment: Text.AlignHCenter
    text: "Stick"; color: Color.foreground; opacity: 0.6
    font.pixelSize: 9; font.family: Style.font.family
  }

  // A / B on the right prong.
  Repeater {
    model: [
      { key: "b", dy: 0, cap: "A" },
      { key: "y", dy: 30, cap: "B" }
    ]
    delegate: Item {
      required property var modelData
      x: 227; y: 92 + modelData.dy
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

  // C-buttons cluster, middle right.
  Repeater {
    model: [
      { key: "r_x_plus", dx: 16, dy: 0 },
      { key: "r_x_minus", dx: -16, dy: 0 },
      { key: "r_y_minus", dx: 0, dy: -16 },
      { key: "r_y_plus", dx: 0, dy: 16 }
    ]
    delegate: Rectangle {
      required property var modelData
      x: 176 + modelData.dx - 7
      y: 100 + modelData.dy - 7
      width: 14; height: 14; radius: 7
      color: root.hot([modelData.key]) ? Color.accent : Qt.rgba(0.9, 0.75, 0.1, 0.35)
      border.width: 1; border.color: root.line
    }
  }
  Text {
    x: 156; y: 122; width: 64; horizontalAlignment: Text.AlignHCenter
    text: "C"; color: Color.foreground; opacity: 0.6
    font.pixelSize: 9; font.family: Style.font.family
  }

  // L / R shoulders + Z trigger + Start.
  Rectangle {
    x: 70; y: 30; width: 34; height: 10; radius: 5
    color: root.hot(["l"]) ? Color.accent : root.dim
    border.width: 1; border.color: root.line
  }
  Rectangle {
    x: 216; y: 30; width: 34; height: 10; radius: 5
    color: root.hot(["r"]) ? Color.accent : root.dim
    border.width: 1; border.color: root.line
  }
  Rectangle {
    x: 70; y: 172; width: 34; height: 10; radius: 5
    color: root.hot(["l2"]) ? Color.accent : root.dim
    border.width: 1; border.color: root.line
  }
  Text {
    x: 62; y: 16; width: 50; horizontalAlignment: Text.AlignHCenter
    text: "L"; color: Color.foreground; opacity: 0.6
    font.pixelSize: 9; font.family: Style.font.family
  }
  Text {
    x: 208; y: 16; width: 50; horizontalAlignment: Text.AlignHCenter
    text: "R"; color: Color.foreground; opacity: 0.6
    font.pixelSize: 9; font.family: Style.font.family
  }
  Rectangle {
    x: 145; y: 52; width: 30; height: 12; radius: 6
    color: root.hot(["start"]) ? Color.accent : root.dim
    border.width: 1; border.color: root.line
  }
  Text {
    x: 140; y: 66; width: 40; horizontalAlignment: Text.AlignHCenter
    text: "Start"; color: Color.foreground; opacity: 0.6
    font.pixelSize: 9; font.family: Style.font.family
  }
}
