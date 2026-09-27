import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "MenuModel.js" as MenuModel
import "System.js" as System

// Left column: apps (A-Z, search-filtered), update status, and the
// Learn/Trigger/Style tree. Owns its navigation state, menu data and
// update checks; filter text arrives via property, actions leave via
// closeRequested.
Rectangle {
  id: root

  property var bar: null
  property string filterText: ""

  signal closeRequested()

  anchors.top: parent.top
  anchors.bottom: parent.bottom
  anchors.left: parent.left
  width: parent.width * 0.65
  radius: Style.cornerRadius
  color: "transparent"

  onFilterTextChanged: root.updateMenu()
  onActiveMenuChanged: root.updateMenu()

  // System menu sources (default + user extension), merged like Menu.qml.
  property var defaultSystemItems: []
  property var userSystemItems: []

  // Win7-style tree state.
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
    root.closeRequested()
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

  // Same update checks as omarchy.system-update.
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
    root.closeRequested()
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
    root.closeRequested()
    Util.execDetached(cmd)
  }

  function openMenuRow(row) {
    if (!row) return
    if (row.kind === "app") { root.launchApp(row.appId, row.label); return }
    // Install lives in the traditional menu: hand off straight to it.
    if (row.id === "install") { root.openOfficial("install"); return }
    // Provider-backed submenus (e.g. fonts) load on demand in the official
    // menu: hand off instead of showing an empty level here.
    if (row.provider) { root.openOfficial(row.id); return }
    if (row.kind === "action") {
      root.closeRequested()
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

  function resetNav() {
    root.activeMenu = ""
    root.navStack = []
    root.updateMenu()
  }

  FileView {
    id: defaultSystemFile
    path: "/usr/share/omarchy/default/omarchy/omarchy-menu.jsonc"
    watchChanges: true
    printErrors: false
    onLoaded: { root.defaultSystemItems = MenuModel.parseMenuJsonc(text()); root.rebuildReferences() }
    onFileChanged: reload()
  }

  FileView {
    id: userSystemFile
    path: Quickshell.env("HOME") + "/.config/omarchy/extensions/omarchy-menu.jsonc"
    watchChanges: true
    printErrors: false
    onLoaded: { root.userSystemItems = MenuModel.parseMenuJsonc(text()); root.rebuildReferences() }
    onLoadFailed: { root.userSystemItems = []; root.rebuildReferences() }
    onFileChanged: reload()
  }

  function rebuildReferences() {
    root.updateMenu()
  }

  // Row 1: all apps, grouped A-Z. Search filters only this list.
    Item {
      id: appsBox
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.topMargin: Style.space(8)
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      height: parent.height * 0.58

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
      text: root.updateAvailable ? "\uf021" : "\uf00c"
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
