import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

// General section of the settings window. First block: favorite folders —
// picked with zenity (same as audryus.wallweave), persisted as a JSON array
// by the menu root. `menu` is the BarWidget root: menu.favorites,
// menu.addFavorite(path), menu.removeFavorite(path).
Item {
  id: root

  property var menu: null
  readonly property var favorites: menu ? menu.favorites : []
  // True while the zenity picker runs: the settings window drops behind
  // and releases keys so the dialog stays usable.
  readonly property bool picking: folderPickerProc.running

  // Folder picker: zenity directory chooser, like wallweave's Library.qml.
  Process {
    id: folderPickerProc
    command: ["zenity", "--file-selection", "--directory", "--title=Pick a favorite folder"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var p = String(text || "").trim()
        if (p.length > 0 && root.menu) root.menu.addFavorite(p)
      }
    }
  }

  Column {
    anchors.fill: parent
    spacing: Style.space(10)

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: "Favorite folders"
      color: Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.heading
      font.weight: Font.Medium
    }

    Button {
      width: parent.width
      text: "Add folder"
      bordered: true
      onClicked: folderPickerProc.running = true
    }

    Flickable {
      width: parent.width
      height: Math.min(favCol.implicitHeight, Style.space(300))
      contentWidth: width
      contentHeight: favCol.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height

      Column {
        id: favCol
        width: parent.width
        spacing: Style.space(6)

        Repeater {
          model: root.favorites
          delegate: BorderSurface {
            required property var modelData
            required property int index
            width: favCol.width
            height: Math.max(Style.space(34), favLabel.implicitHeight + Style.space(12))
            radius: Style.cornerRadius
            color: "transparent"
            borderSpec: Border.controlSpec("normal", Color.foreground, Color.accent)

            Text {
              id: favLabel
              anchors.left: parent.left
              anchors.right: removeButton.left
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(8)
              textFormat: Text.PlainText
              text: String(modelData)
              color: Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              elide: Text.ElideMiddle
            }

            Button {
              id: removeButton
              anchors.right: parent.right
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              text: "Remove"
              onClicked: if (root.menu) root.menu.removeFavorite(String(modelData))
            }
          }
        }

        Text {
          visible: root.favorites.length === 0
          width: parent.width
          textFormat: Text.PlainText
          text: "No favorites yet. Pick a folder above."
          color: Color.foreground
          opacity: 0.55
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}
