import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Floating settings window for audryus.menu. The bar widget closes itself
// and flips `open`; only this window stays on screen until the X (or
// outside click / Esc) emits requestClose.
Item {
  id: root

  property bool open: false
  property var bar: null
  // Injected by BarWidget: favorites array + persistence helpers.
  property var menu: null

  property string section: "general"
  onSectionChanged: if (section === "defaults") { defaultsPage.refresh(); defaultsPage.focusSearch() }
  readonly property var sections: [
    { id: "general", label: "General" },
    { id: "defaults", label: "Defaults" },
    { id: "printers", label: "Printers" }
  ]

  signal requestClose()

  function show() { open = true }
  function hide() { open = false }

  // While the folder picker runs, this overlay would cover zenity (a
  // plain toplevel) and swallow its keys — and a click meant for zenity
  // would hit our scrim and close us. Same while printer discovery (its
  // own overlay) is open. So drop behind and yield focus until they go
  // away. Esc/X still close otherwise.
  readonly property bool picking: generalPage.picking || printersPage.discoveryOpen

  PanelWindow {
    id: window
    visible: root.open
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "audryus-settings"
    WlrLayershell.layer: root.picking ? WlrLayer.Bottom : WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.picking ? WlrKeyboardFocus.None : WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    onVisibleChanged: {
      if (visible) Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    }

    // Click outside closes.
    MouseArea {
      anchors.fill: parent
      onClicked: root.requestClose()
    }

    BorderSurface {
      id: card
      width: Math.min(Style.space(560), window.width - Style.gapsOut * 2)
      height: Math.min(Style.space(480), window.height - Style.gapsOut * 2)
      anchors.centerIn: parent
      color: Color.popups.background
      borderSpec: Border.localOrSurfaceSpec("popups", "border", Color.popups.border, Color.popups.border, Math.max(1, Style.space(2)))
      padding: Style.spacing.popupPadding
      radius: Style.cornerRadius

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: root.requestClose()
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: Style.space(12)

        // Top row: title left, X right.
        Item {
          id: header
          width: parent.width
          height: Style.space(32)

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "Settings"
            color: root.bar ? root.bar.barForeground : Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            font.weight: Font.Medium
          }

          Text {
            id: closeGlyph
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(30)
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            text: "\uf00d"
            color: root.bar ? root.bar.barForeground : Color.foreground
            opacity: closeMouse.containsMouse ? 1.0 : 0.6
            font.family: Style.font.family
            font.pixelSize: Style.font.iconLarge

            MouseArea {
              id: closeMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.requestClose()
            }
          }
        }

        Rectangle {
          width: parent.width
          height: 1
          color: Util.alpha(root.bar ? root.bar.barForeground : Color.foreground, 0.15)
        }

        Row {
          width: parent.width
          height: parent.height - header.height - Style.space(12) - 1
          spacing: 0

          // Left: section menu.
          Column {
            id: sectionMenu
            width: Style.space(150)
            height: parent.height
            spacing: Style.space(2)

            Repeater {
              model: root.sections
              delegate: Item {
                required property var modelData
                readonly property bool current: modelData.id === root.section
                width: sectionMenu.width
                height: Style.space(32)

                Rectangle {
                  anchors.fill: parent
                  radius: Style.cornerRadius
                  color: current
                    ? Style.selectedFillFor(root.bar ? root.bar.barForeground : Color.foreground, Color.accent)
                    : (sectionMouse.containsMouse
                      ? Style.hoverFillFor(root.bar ? root.bar.barForeground : Color.foreground, Color.accent)
                      : "transparent")
                }

                Text {
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(10)
                  textFormat: Text.PlainText
                  text: modelData.label
                  color: root.bar ? root.bar.barForeground : Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.weight: current ? Font.Medium : Font.Normal
                  elide: Text.ElideRight
                }

                MouseArea {
                  id: sectionMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.section = modelData.id
                }
              }
            }
          }

          Rectangle {
            width: 1
            height: parent.height
            color: Util.alpha(root.bar ? root.bar.barForeground : Color.foreground, 0.15)
          }

          // Right: section content (General open by default).
          Item {
            width: parent.width - sectionMenu.width - 1 - Style.space(12)
            height: parent.height
            anchors.topMargin: 0

            General {
              id: generalPage
              anchors.fill: parent
              anchors.leftMargin: Style.space(12)
              visible: root.section === "general"
              menu: root.menu
            }

            Defaults {
              id: defaultsPage
              anchors.fill: parent
              anchors.leftMargin: Style.space(12)
              visible: root.section === "defaults"
              menu: root.menu
              onCloseRequested: root.requestClose()
            }

            Printers {
              id: printersPage
              anchors.fill: parent
              anchors.leftMargin: Style.space(12)
              visible: root.section === "printers"
            }
          }
        }
      }
    }
  }
}
