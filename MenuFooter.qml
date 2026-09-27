import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "MenuModel.js" as MenuModel
import "System.js" as System

// Bottom system menu (Settings first, then the system submenu). Owns its
// data (default + user menu files) and only signals outward.
Rectangle {
  id: root

  property var bar: null

  signal closeRequested()
  signal settingsRequested()

  anchors.left: parent.left
  anchors.right: parent.right
  anchors.bottom: parent.bottom
  height: Style.space(32)
  radius: Style.cornerRadius
  color: "transparent"

  property var defaultSystemItems: []
  property var userSystemItems: []
  ListModel { id: systemModel }

  function rebuildSystem() {
    var merged = MenuModel.mergeMenuSources(root.defaultSystemItems, root.userSystemItems)
    var rows = System.systemRows(merged.items, merged.itemOrder)
    systemModel.clear()
    // NOTE: ListModel delegates have no modelData; `id` can't be a role
    // name either, so expose it as itemId.
    for (var i = 0; i < rows.length; i++) {
      systemModel.append({
        itemId: rows[i].id,
        label: rows[i].label,
        icon: rows[i].icon,
        action: rows[i].action
      })
    }
  }

  FileView {
    id: defaultSystemFile
    path: "/usr/share/omarchy/default/omarchy/omarchy-menu.jsonc"
    watchChanges: true
    printErrors: false
    onLoaded: { root.defaultSystemItems = MenuModel.parseMenuJsonc(text()); root.rebuildSystem() }
    onFileChanged: reload()
  }

  FileView {
    id: userSystemFile
    path: Quickshell.env("HOME") + "/.config/omarchy/extensions/omarchy-menu.jsonc"
    watchChanges: true
    printErrors: false
    onLoaded: { root.userSystemItems = MenuModel.parseMenuJsonc(text()); root.rebuildSystem() }
    onLoadFailed: { root.userSystemItems = []; root.rebuildSystem() }
    onFileChanged: reload()
  }

  Row {
    id: footerRow
    anchors.fill: parent
    anchors.leftMargin: Style.space(8)
    anchors.rightMargin: Style.space(8)

    Repeater {
      model: systemModel
      delegate: Item {
        required property string itemId
        required property string label
        required property string icon
        required property string action
        width: footerRow.width / Math.max(1, systemModel.count)
        height: footerRow.height

        Column {
          anchors.centerIn: parent
          spacing: 2
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            textFormat: Text.PlainText
            text: icon
            color: root.bar ? root.bar.barForeground : Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.iconLarge
          }
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            textFormat: Text.PlainText
            text: label
            color: root.bar ? root.bar.barForeground : Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (itemId === "settings") {
              root.settingsRequested()
              return
            }
            var cmd = action
            root.closeRequested()
            if (cmd) Util.execDetached(cmd)
          }
        }
      }
    }
  }
}
