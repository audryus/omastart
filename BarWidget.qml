import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "audryus.omastart"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  property string filterText: ""
  property bool menuOpen: false
  property bool settingsOpen: false

  readonly property bool opened: menuOpen
  readonly property var coordinatorKey: root
  // Toggle the popup on left/middle click (right click is ignored).
  function open() { menuOpen = true }
  function close() { menuOpen = false }
  function toggle() { menuOpen = !menuOpen }

  // Bar button: shows the wallpaper icon and opens/closes the popup.
  BarIconButton {
    id: button
    bar: root.bar
    // omarchy logo glyph (same as official omarchy.menu)
    text: "\ue900"
    fontFamily: "omarchy"
    tooltipText: "Start Menu"
    // Left/middle click toggles the popup; right click does nothing.
    onPressed: function(b) { if (b === Qt.RightButton) return; root.toggle() }
  }

  Timer {
    id: focusTimer
    interval: 50
    repeat: true
    onTriggered: {
      search.forceActiveFocus()
      if (search.activeFocus) stop()
    }
  }

  // Floating settings window (same dir, no import needed). The widget
  // closes itself when Settings is picked, leaving only this open.
  Settings {
    id: settingsWindow
    open: root.settingsOpen
    bar: root.bar
    menu: root
    onRequestClose: root.settingsOpen = false
  }

  // Favorite folders (General section + right pane): JSON array of
  // absolute paths. Owned here because Settings/General shares it.
  property var favorites: []
  readonly property string favoritesPath: Quickshell.env("HOME") + "/.local/state/omarchy/settings/omastart-favorites.json"

  function loadFavorites(text) {
    var next = []
    try {
      var parsed = JSON.parse(String(text || ""))
      var list = Array.isArray(parsed) ? parsed : []
      for (var i = 0; i < list.length; i++) {
        if (typeof list[i] === "string" && list[i]) next.push(list[i])
      }
    } catch (e) { }
    root.favorites = next
  }

  function saveFavorites() {
    var json = JSON.stringify(Array.isArray(root.favorites) ? root.favorites : [])
    var dir = Quickshell.env("HOME") + "/.local/state/omarchy/settings"
    Util.execDetached("mkdir -p " + Util.shellQuote(dir) + " && printf '%s' " + Util.shellQuote(json) + " > " + Util.shellQuote(root.favoritesPath))
  }

  function addFavorite(path) {
    var p = String(path || "").trim()
    if (!p) return
    var favs = Array.isArray(root.favorites) ? root.favorites.slice() : []
    if (favs.indexOf(p) >= 0) return
    favs.push(p)
    root.favorites = favs
    root.saveFavorites()
  }

  function removeFavorite(path) {
    var favs = Array.isArray(root.favorites) ? root.favorites : []
    root.favorites = favs.filter(function(p) { return p !== path })
    root.saveFavorites()
  }

  FileView {
    id: favoritesFile
    path: root.favoritesPath
    watchChanges: true
    printErrors: false
    onLoaded: root.loadFavorites(text())
    onLoadFailed: root.favorites = []
    onFileChanged: reload()
  }

  function resetMenu() {
    root.filterText = ""
    leftPane.resetNav()
    leftPane.refreshUpdate()
  }

  // NOTE: era PopupCard (xdg-popup), mas com follow_mouse=1 o Hyprland so
  // entrega o teclado a janela sob o cursor — o cursor fica na barra, a barra
  // tem keyboardFocus None, e o digitado se perdia (so funcionava com o mouse
  // em cima do popup). PanelWindow com Exclusive puxa o foco independente do
  // mouse, igual ao Menu.qml oficial.
  PanelWindow {
    id: panel
    visible: root.menuOpen
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omastart-menu"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    onVisibleChanged: {
      if (visible) {
        root.resetMenu()
        focusTimer.restart()
        if (root.bar) root.bar.requestPopout(root.coordinatorKey)
      } else {
        focusTimer.stop()
        if (root.bar && root.bar.activePopout === root.coordinatorKey) root.bar.releasePopout(root.coordinatorKey)
      }
    }

    // Click outside closes.
    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    BorderSurface {
      id: card
      width: Math.min(Style.space(642), panel.width - Style.gapsOut * 2)
      height: Style.space(726)
      //height: content.implicitHeight + contentTopInset + contentBottomInset
      // Anchored to the button like PopupCard: centered on it, clamped to
      // the screen. The bar strip and this fullscreen overlay share the same
      // screen origin, so the button's x inside the bar window maps 1:1.
      x: {
        var cx = panel.width / 2
        var win = button.QsWindow.window
        if (win && win.contentItem) {
          var p = button.mapToItem(win.contentItem, button.width / 2, 0)
          cx = p.x
        }
        return Math.max(Style.gapsOut, Math.min(cx - width / 2, panel.width - width - Style.gapsOut))
      }
      y: {
        if (root.bar && root.bar.position === "bottom") return panel.height - height - root.barSize - Style.gapsOut
        if (root.bar && (root.bar.position === "left" || root.bar.position === "right")) {
          var winY = button.QsWindow.window
          var cy = panel.height / 2
          if (winY && winY.contentItem) cy = button.mapToItem(winY.contentItem, 0, button.height / 2).y
          return Math.max(Style.gapsOut, Math.min(cy - height / 2, panel.height - height - Style.gapsOut))
        }
        return root.barSize + Style.gapsOut
      }
      color: Color.popups.background
      borderSpec: Border.localOrSurfaceSpec("popups", "border", Color.popups.border, Color.popups.border, Math.max(1, Style.space(2)))
      padding: Style.spacing.popupPadding
      radius: Style.cornerRadius

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: content
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset

        TextField {
          id: search
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          focus: true
          activeFocusOnTab: true
          placeholderText: "Buscar..."
          text: root.filterText
          onTextEdited: if (text !== root.filterText) root.filterText = text
          onAccepted: console.log("buscar:", text)
          Keys.onEscapePressed: root.close()
          onVisibleChanged: if (visible) Qt.callLater(function() { forceActiveFocus() })
        }


        MenuFooter {
          id: footer
          bar: root.bar
          onCloseRequested: root.close()
          onSettingsRequested: {
            root.close()
            root.settingsOpen = true
          }
        }
        // Middle section between search and footer (siblings, so all
        // anchors stay parent-or-sibling).
        Item {
          id: body
          anchors.top: search.bottom
          anchors.topMargin: Style.space(14)
          anchors.bottom: footer.top
          anchors.bottomMargin: Style.space(14)
          anchors.left: parent.left
          anchors.right: parent.right

          MenuLeftPane {
            id: leftPane
            bar: root.bar
            filterText: root.filterText
            onCloseRequested: root.close()
          }
          MenuRightPane {
            bar: root.bar
            favorites: root.favorites
            onCloseRequested: root.close()
          }
        }
      }
    }
  }

}