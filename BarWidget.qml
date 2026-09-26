import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "MenuModel.js" as MenuModel
import "System.js" as System

BarWidget {
  id: root
  moduleName: "audryus.menu"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  property string filterText: ""
  property bool menuOpen: false
  property bool settingsOpen: false
  onFilterTextChanged: root.updateMenu()
  onActiveMenuChanged: root.updateMenu()

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

  // Favorite folders (General section): JSON array of absolute paths.
  property var favorites: []
  readonly property string favoritesPath: Quickshell.env("HOME") + "/.local/state/omarchy/settings/audryus-menu-favorites.json"

  // Last path segment only (e.g. valid8); full path goes to the tooltip.
  function shortFavorite(path) {
    var parts = String(path || "").split("/").filter(function(p) { return p.length > 0 })
    if (parts.length === 0) return String(path || "")
    return parts[parts.length - 1]
  }

  // Static places + divider + favorites. Favorites behave like Work:
  // left = file manager, middle = default agent, right = terminal.
  readonly property var placesWithFavorites: {
    var out = root.places.slice()
    var favs = Array.isArray(root.favorites) ? root.favorites : []
    if (favs.length > 0) {
      out.push({ divider: true })
      for (var i = 0; i < favs.length; i++) {
        out.push({
          label: root.shortFavorite(favs[i]),
          dir: favs[i],
          icon: "\uf07b",
          tip: true,
          agent: true
        })
      }
    }
    return out
  }

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

  // Places for the right pane. Left click = default file manager
  // (nautilus), right click = default terminal, middle click only on
  // Work = default agent in a terminal at ~/Work.
  readonly property string homeDir: Quickshell.env("HOME")
  readonly property var places: [
    { label: "My Computer", dir: homeDir, icon: "\uf015" },
    { divider: true },
    { label: "Projects", dir: homeDir + "/Projects", icon: "\uf121 " },
    { label: "Work", dir: homeDir + "/Work", special: "work", icon: "\uf0b1" },
    { divider: true },
    { label: "Documents", dir: homeDir + "/Documents", icon: "\uf15c" },
    { label: "Downloads", dir: homeDir + "/Downloads", icon: "\uf019" },
    { label: "Games", dir: homeDir + "/Games", icon: "\uf11b " },
    { divider: true },
    { label: "Music", dir: homeDir + "/Music", icon: "\uf001" },
    { label: "Pictures", dir: homeDir + "/Pictures", icon: "\uf03e" },
    { label: "Videos", dir: homeDir + "/Videos", icon: "\uf008" },
  ]

  // Default file manager via XDG (inode/directory MIME): honors nautilus,
  // strata, flea, or whatever the user set — unlike omarchy-launch-nautilus.
  function openFm(dir) { Util.execDetached('xdg-open "' + dir + '"') }
  function openTerm(dir) { Util.execDetached('uwsm-app -- xdg-terminal-exec --dir="' + dir + '"') }
  function openAgent(dir) { Util.execDetached('uwsm-app -- xdg-terminal-exec --dir="' + dir + '" $(omarchy-default-agent)') }

  // System footer sources: default + user extension, merged like Menu.qml.
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
    root.updateMenu()
  }

  // Win7-style tree for the left pane (setup/system hidden: they live in
  // the footer). filterText switches the column to flat search results.
  property string activeMenu: ""
  property var navStack: []
  property var menuRows: []

  function menuMerged() {
    return MenuModel.mergeMenuSources(root.defaultSystemItems, root.userSystemItems)
  }

  function appValues() {
    try {
      var apps = DesktopEntries.applications.values
      return apps ? apps : []
    } catch (e) { return [] }
  }

  function appIconSource(icon) {
    var v = String(icon || "")
    if (!v) return Quickshell.iconPath("application-x-executable", true)
    if (v.indexOf("file://") === 0 || v.indexOf("image://") === 0) return v
    if (v.charAt(0) === "/") return "file://" + v
    var themed = ""
    try { themed = Quickshell.iconPath(v, true) } catch (e) { themed = "" }
    if (themed && themed.length > 0) return themed
    return Quickshell.iconPath("application-x-executable", true)
  }

  function launchApp(appId, label) {
    if (!appId) return
    root.close()
    Util.execDetached("uwsm-app -- gtk-launch " + Util.shellQuote(appId + ".desktop"))
  }

  // Row 2 (tree) never shows apps; row 3 lists them directly and is the
  // only list the search filters.
  property var appRowsList: []

  function updateMenu() {
    var merged = root.menuMerged()
    var q = root.filterText.trim()
    var rows
    if (!root.activeMenu) rows = System.treeRows(merged.items, merged.itemOrder)
    else rows = System.childRows(merged.items, merged.itemOrder, root.activeMenu)
    root.menuRows = rows
    var vals = root.appValues()
    root.appRowsList = q
      ? System.searchApps(vals, q)
      : System.appRows(vals)
  }

  // Row 1: same update checks as omarchy.system-update.
  property bool updateAvailable: false
  property bool updateChecked: false
  property string lastUpdate: ""

  function refreshUpdate() {
    if (!updateCheckProc.running) {
      root.updateChecked = false
      updateCheckProc.running = true
    }
    if (!lastUpdateProc.running) {
      lastUpdateProc.collected = ""
      lastUpdateProc.running = true
    }
  }

  function runUpdate() {
    var cmd = "omarchy-launch-floating-terminal-with-presentation omarchy-update"
    root.close()
    if (root.bar) root.bar.run(cmd)
    else Util.execDetached(cmd)
  }

  Process {
    id: updateCheckProc
    command: ["bash", "-lc", "omarchy-update-available"]
    onExited: function(exitCode) {
      root.updateAvailable = exitCode === 0
      root.updateChecked = true
    }
  }

  Process {
    id: lastUpdateProc
    property string collected: ""
    // Last full-system upgrade from the pacman log (YYYY-MM-DD).
    command: ["bash", "-lc", "tac /var/log/pacman.log 2>/dev/null | grep -m1 'starting full system upgrade' | sed 's/^\\[//;s/T.*//'"]
    stdout: SplitParser {
      onRead: function(data) { lastUpdateProc.collected += data }
    }
    onExited: {
      root.lastUpdate = lastUpdateProc.collected.trim()
    }
  }

  function openOfficial(menuId) {
    var cmd = "omarchy-shell shell toggle omarchy.menu '{\"menu\":\"" + menuId + "\"}'"
    root.close()
    Util.execDetached(cmd)
  }

  function drillTo(id) {
    root.navStack = root.navStack.concat([root.activeMenu])
    root.activeMenu = id
  }

  function openMenuRow(row) {
    if (!row) return
    if (row.kind === "app") { root.launchApp(row.appId, row.label); return }
    // Provider-backed submenus (e.g. fonts) load on demand in the official
    // menu: hand off instead of showing an empty level here.
    if (row.provider) { root.openOfficial(row.id); return }
    if (row.kind === "action") {
      root.close()
      if (row.action) Util.execDetached(row.action)
      return
    }
    var target = row.kind === "link" && row.target ? row.target : row.id
    if (!target) return
    root.navStack = root.navStack.concat([root.activeMenu])
    root.activeMenu = target
  }

  function goBack() {
    if (root.navStack.length > 0) {
      var s = root.navStack
      root.activeMenu = s[s.length - 1]
      root.navStack = s.slice(0, s.length - 1)
    } else {
      root.activeMenu = ""
    }
  }

  function resetMenu() {
    root.activeMenu = ""
    root.navStack = []
    root.filterText = ""
    root.updateMenu()
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
    WlrLayershell.namespace: "audryus-menu"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    onVisibleChanged: {
      if (visible) {
        root.resetMenu()
        root.refreshUpdate()
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


        Rectangle {
          id: footer
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: Style.space(32)
          radius: Style.cornerRadius
          color: "transparent"

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
                      root.close()
                      root.settingsOpen = true
                      return
                    }
                    var cmd = action
                    root.close()
                    if (cmd) Util.execDetached(cmd)
                  }
                }
              }
            }
          }
        }
        // Spacer do meio (futura lista): ocupa tudo entre busca e footer.
        Item {
          id: body
          anchors.top: search.bottom
          anchors.topMargin: Style.space(14)
          anchors.bottom: footer.top
          anchors.bottomMargin: Style.space(14)
          anchors.left: parent.left
          anchors.right: parent.right

          Rectangle {
            id: leftPane
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            width: parent.width * 0.7
            radius: Style.cornerRadius
            color: "transparent"

            // Row 1: all apps, grouped A-Z. Search filters only this list.
            Item {
              id: appsBox
              anchors.top: parent.top
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.topMargin: Style.space(8)
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              height: parent.height * 0.6

              Text {
                id: appsHeader
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                textFormat: Text.PlainText
                text: "Apps" + (root.filterText.trim() !== "" ? " — " + appsList.count + " found" : "")
                color: root.bar ? root.bar.barForeground : Color.foreground
                opacity: 0.6
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
                elide: Text.ElideRight
              }

              ListView {
                id: appsList
                anchors.top: appsHeader.bottom
                anchors.topMargin: Style.space(4)
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                clip: true
                spacing: Style.space(2)
                model: root.appRowsList
                boundsBehavior: Flickable.StopAtBounds

                section.property: "section"
                section.criteria: ViewSection.FullString
                section.delegate: Item {
                  required property string section
                  width: appsList.width
                  height: Style.space(20)

                  Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: section
                    color: root.bar ? root.bar.barForeground : Color.foreground
                    opacity: 0.45
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                }

                delegate: Item {
                  required property var modelData
                  width: appsList.width
                  height: Style.space(32)

                  Image {
                    id: appRowIcon
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(22)
                    height: Style.space(22)
                    fillMode: Image.PreserveAspectFit
                    sourceSize.width: width * Screen.devicePixelRatio
                    sourceSize.height: height * Screen.devicePixelRatio
                    source: root.appIconSource(modelData.appIcon)
                    asynchronous: true
                  }

                  Text {
                    anchors.left: appRowIcon.right
                    anchors.leftMargin: Style.space(8)
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: modelData.label || ""
                    color: root.bar ? root.bar.barForeground : Color.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                  }

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.launchApp(modelData.appId, modelData.label)
                  }
                }
              }

              Text {
                anchors.centerIn: parent
                visible: appsList.count === 0
                textFormat: Text.PlainText
                text: "Nenhum aplicativo"
                color: root.bar ? root.bar.barForeground : Color.foreground
                opacity: 0.5
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }
            }

            // Row 3: system update status (same checks as omarchy.system-update).
            Item {
              id: updateBox
              anchors.bottom: parent.bottom
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottomMargin: Style.space(8)
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              height: Style.space(56)

              Text {
                id: updateIcon
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(30)
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                text: root.updateAvailable ? "" : ""
                color: root.bar ? root.bar.barForeground : Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.iconLarge
              }

              Column {
                anchors.left: updateIcon.right
                anchors.right: updateButton.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: !root.updateChecked ? "Checking updates…"
                    : (root.updateAvailable ? "Updates available" : "System up to date")
                  color: root.bar ? root.bar.barForeground : Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.heading
                  font.weight: Font.Medium
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: "Last update: " + (root.lastUpdate || "…")
                  color: root.bar ? root.bar.barForeground : Color.foreground
                  opacity: 0.55
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }

              Button {
                id: updateButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "Update"
                bordered: true
                onClicked: root.runUpdate()
              }
            }


            Rectangle {
              id: divBottom
              anchors.bottom: updateBox.top
              anchors.bottomMargin: Style.space(6)
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              height: 1
              color: Util.alpha(root.bar ? root.bar.barForeground : Color.foreground, 0.15)
            }



            Rectangle {
              id: divTop
              anchors.top: appsBox.bottom
              anchors.topMargin: Style.space(6)
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              height: 1
              color: Util.alpha(root.bar ? root.bar.barForeground : Color.foreground, 0.15)
            }


            // Row 2: menu tree (Learn / Trigger / Style).
            Item {
              id: menuBox
              anchors.top: divTop.bottom
              anchors.topMargin: Style.space(6)
              anchors.bottom: divBottom.top
              anchors.bottomMargin: Style.space(6)
              anchors.left: parent.left
              anchors.right: parent.right

            Item {
              id: backRow
              anchors.top: parent.top
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              height: root.activeMenu !== "" ? Style.space(28) : 0
              visible: height > 0

              Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: "‹ " + System.rowLabel(root.menuMerged().items, root.activeMenu)
                color: root.bar ? root.bar.barForeground : Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.heading
                font.weight: Font.Medium
                elide: Text.ElideRight
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.goBack()
              }
            }

            ListView {
              id: menuList
              anchors.top: backRow.bottom
              anchors.bottom: parent.bottom
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.topMargin: Style.space(4)
              anchors.bottomMargin: Style.space(8)
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              clip: true
              spacing: Style.space(2)
              model: root.menuRows
              boundsBehavior: Flickable.StopAtBounds

              delegate: Item {
                required property var modelData
                readonly property bool isApp: modelData.kind === "app"
                width: menuList.width
                height: modelData.detail ? Style.space(46) : Style.space(34)

                Item {
                  id: menuIconSlot
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(30)
                  height: parent.height

                  Text {
                    anchors.centerIn: parent
                    visible: !parent.parent.isApp
                    textFormat: Text.PlainText
                    text: modelData.icon || ""
                    color: root.bar ? root.bar.barForeground : Color.foreground
                    font.family: modelData.iconFont || Style.font.family
                    font.pixelSize: Style.font.iconLarge
                  }

                  Image {
                    anchors.centerIn: parent
                    visible: parent.parent.isApp
                    width: Style.space(22)
                    height: Style.space(22)
                    fillMode: Image.PreserveAspectFit
                    sourceSize.width: width * Screen.devicePixelRatio
                    sourceSize.height: height * Screen.devicePixelRatio
                    source: parent.parent.isApp ? root.appIconSource(modelData.appIcon) : ""
                    asynchronous: true
                  }
                }

                Text {
                  anchors.left: menuIconSlot.right
                  anchors.right: chevron.left
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.verticalCenterOffset: modelData.detail ? -8 : 0
                  textFormat: Text.PlainText
                  text: modelData.label || ""
                  color: root.bar ? root.bar.barForeground : Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.heading
                  font.weight: Font.Medium
                  elide: Text.ElideRight
                }

                Text {
                  id: chevron
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(16)
                  horizontalAlignment: Text.AlignHCenter
                  textFormat: Text.PlainText
                  text: (modelData.hasChildren && !modelData.action) ? "›" : ""
                  color: root.bar ? root.bar.barForeground : Color.foreground
                  opacity: 0.5
                  font.family: Style.font.family
                  font.pixelSize: Style.font.heading
                }

                Text {
                  visible: !!modelData.detail
                  anchors.left: menuIconSlot.right
                  anchors.right: chevron.left
                  anchors.bottom: parent.bottom
                  anchors.bottomMargin: 2
                  textFormat: Text.PlainText
                  text: modelData.detail || ""
                  color: root.bar ? root.bar.barForeground : Color.foreground
                  opacity: 0.5
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.openMenuRow(modelData)
                }
              }
            }

            Text {
              anchors.centerIn: parent
              visible: menuList.count === 0
              textFormat: Text.PlainText
              text: "Nenhum resultado"
              color: root.bar ? root.bar.barForeground : Color.foreground
              opacity: 0.5
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }
            } // menuBox
          }
          Rectangle {
            id: rightPane
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            width: parent.width * 0.3
            radius: Style.cornerRadius
            color: "transparent"

            Column {
              anchors.fill: parent
              anchors.margins: Style.space(8)
              spacing: Style.space(2)

              Repeater {
                model: root.placesWithFavorites
                delegate: Item {
                  required property var modelData
                  width: parent.width
                  height: modelData.divider ? Style.space(9) : Style.space(34)

                  Rectangle {
                    visible: !!modelData.divider
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: 1
                    color: Util.alpha(root.bar ? root.bar.barForeground : Color.foreground, 0.15)
                  }

                  Item {
                    visible: !modelData.divider
                    anchors.fill: parent

                    Text {
                      id: placeIcon
                      anchors.left: parent.left
                      anchors.verticalCenter: parent.verticalCenter
                      width: Style.space(30)
                      horizontalAlignment: Text.AlignHCenter
                      textFormat: Text.PlainText
                      text: modelData.icon || ""
                      color: root.bar ? root.bar.barForeground : Color.foreground
                      opacity: placeMouse.containsMouse ? 1.0 : 0.75
                      font.family: Style.font.family
                      font.pixelSize: Style.font.iconLarge
                    }

                    Text {
                      id: placeLabel
                      anchors.left: placeIcon.right
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      textFormat: Text.PlainText
                      text: modelData.label || ""
                      color: root.bar ? root.bar.barForeground : Color.foreground
                      opacity: placeMouse.containsMouse ? 1.0 : 0.75
                      font.family: Style.font.family
                      font.pixelSize: Style.font.heading
                      font.weight: Font.Medium
                      elide: Text.ElideRight
                    }

                    MouseArea {
                      id: placeMouse
                      anchors.fill: parent
                      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: function(mouse) {
                        var dir = modelData.dir
                        var special = modelData.special
                        root.close()
                        if (mouse.button === Qt.RightButton) root.openTerm(dir)
                        else if (mouse.button === Qt.MiddleButton) {
                          if (special === "work" || modelData.agent) root.openAgent(dir)
                        } else root.openFm(dir)
                      }
                    }

                    PanelToolTip {
                      visible: placeMouse.containsMouse && !!modelData.tip
                      text: modelData.dir || ""
                    }
                  }
                }
              }
            }
          }
          }
        }

      }
    }
  }
