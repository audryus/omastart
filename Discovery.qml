import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Network printer discovery window: lists printers found on the network
// that are NOT installed yet, each with an Install button (not wired yet).
// No X here: outside click or Esc closes.
Item {
  id: root

  property bool open: false
  property var installed: []

  signal requestClose()
  signal installLaunched()

  property var found: []
  property bool scanning: false

  // Shared with Printers.qml Refresh (same scan, parsed the same way).
  readonly property string scanCommand: "echo '@@DRV'; driverless list 2>/dev/null; for t in _ipp._tcp _ipps._tcp _printer._tcp _pdl-datastream._tcp; do echo \"@@AVAHI $t\"; timeout 8 avahi-browse -rt \"$t\" 2>/dev/null; done"

  function refresh() {
    if (scanProc.running) return
    root.scanning = true
    root.found = []
    scanProc.collected = ""
    scanProc.running = true
  }

  function installedUris() {
    var set = {}
    var list = Array.isArray(root.installed) ? root.installed : []
    for (var i = 0; i < list.length; i++) {
      if (list[i].uri) set[String(list[i].uri)] = true
      if (list[i].name) set["name:" + String(list[i].name)] = true
    }
    return set
  }

  // TXT comes as quoted groups: "product=(X Y)" "rp=auto" .... Values may
  // carry spaces, so match per group instead of a flat regex.
  function txtField(txt, key) {
    var groups = String(txt || "").match(/"([^"]*)"/g) || []
    for (var i = 0; i < groups.length; i++) {
      var g = groups[i].slice(1, -1)
      if (g.charAt(g.length - 1) === ")" && g.indexOf(key + "=(") === 0)
        return g.slice(key.length + 2, -1)
      if (g.indexOf(key + "=") === 0) return g.slice(key.length + 1)
    }
    return ""
  }

  // avahi-browse `=` records need hostname/address/port/rp to build a URI:
  // _ipp._tcp -> ipp://addr:port/rp, _ipps._tcp -> ipps://..., _printer._tcp
  // (LPD, e.g. old Epsons with no IPP at all) -> lpd://addr/queue,
  // _pdl-datastream._tcp (JetDirect) -> socket://addr:port.
  function avahiUri(type, rec) {
    // Prefer the .local hostname: it survives DHCP IP changes, plain IPs
    // go stale (which is what Refresh is for).
    var host = rec.hostname || rec.address
    if (!host) return ""
    if (type === "_ipp._tcp") return "ipp://" + host + ":" + (rec.port || "631") + "/" + (txtField(rec.txt, "rp") || "ipp/print")
    if (type === "_ipps._tcp") return "ipps://" + host + ":" + (rec.port || "631") + "/" + (txtField(rec.txt, "rp") || "ipp/print")
    if (type === "_printer._tcp") return "lpd://" + host + "/" + (txtField(rec.txt, "rp") || "auto")
    if (type === "_pdl-datastream._tcp") return "socket://" + host + ":" + (rec.port || "9100")
    return ""
  }

  // CUPS queue name: letters/digits/_/-, unique among installed printers.
  function suggestName(want, taken) {
    var base = String(want || "printer").replace(/[^A-Za-z0-9_-]/g, "_").replace(/^[^A-Za-z]+/, "")
    if (!base) base = "printer"
    var name = base
    var n = 2
    while (taken[name]) { name = base + "-" + n; n += 1 }
    return name
  }

  function takenNames() {
    var set = {}
    var list = Array.isArray(root.installed) ? root.installed : []
    for (var i = 0; i < list.length; i++) set[String(list[i].name)] = true
    return set
  }

  // Traditional pattern (install.*): privileged work runs in a floating
  // terminal so sudo prompts there. ipp/ipps get the driverless model,
  // anything else a raw queue.
  function install(row) {
    if (!row || !row.uri) return
    var queue = suggestName(row.name, root.takenNames())
    var model = (row.uri.indexOf("ipp://") === 0 || row.uri.indexOf("ipps://") === 0) ? "everywhere" : "raw"
    var cmd = "omarchy-launch-floating-terminal-with-presentation "
      + Util.shellQuote("sudo lpadmin -p " + Util.shellQuote(queue) + " -E -v " + Util.shellQuote(row.uri) + " -m " + model)
    installingUri = row.uri
    // Our overlays sit above the floating terminal: get out of the way
    // first (handled up the chain), then launch the installer.
    root.installLaunched()
    Util.execDetached(cmd)
  }

  function avahiName(rec) {
    return txtField(rec.txt, "ty") || txtField(rec.txt, "product") || rec.svc
  }

  function parseDiscovery(text) {
    var rows = []
    var seen = {}
    var section = ""
    var rec = null
    function flush() {
      if (rec && rec.type) {
        var uri = rec.drv || avahiUri(rec.type, rec)
        var name = rec.drvName || avahiName(rec)
        if (uri && !seen[uri]) {
          seen[uri] = true
          rows.push({ name: name || uri, uri: uri })
        }
      }
      rec = null
    }
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      var mSec = line.match(/^@@(\S+)(?:\s+(.*))?$/)
      if (mSec) {
        flush()
        section = mSec[1] === "AVAHI" ? mSec[2] : "DRV"
        continue
      }
      if (!line) continue
      if (section === "DRV") {
        var uri = line.split(/\s+/)[0]
        if (uri.indexOf("ipp://") !== 0 && uri.indexOf("ipps://") !== 0) continue
        var quoted = line.match(/"([^"]*)"/)
        flush()
        rec = { type: "DRV", drv: uri, drvName: quoted ? quoted[1] : "" }
        flush()
        continue
      }
      if (line.charAt(0) === "=") {
        flush()
        rec = { type: section, svc: line.substring(1).trim(), txt: "" }
        continue
      }
      if (!rec) continue
      var mH = line.match(/^hostname\s*=\s*\[(.*)\]/)
      if (mH) { rec.hostname = mH[1]; continue }
      var mA = line.match(/^address\s*=\s*\[(.*)\]/)
      if (mA) { rec.address = mA[1]; continue }
      var mP = line.match(/^port\s*=\s*\[(.*)\]/)
      if (mP) { rec.port = mP[1]; continue }
      var mT = line.match(/^txt\s*=\s*\[(.*)\]/)
      if (mT) { rec.txt = mT[1]; continue }
    }
    flush()
    return rows
  }

  function applyScan() {
    var known = root.installedUris()
    var all = root.parseDiscovery(scanProc.collected)
    var rows = []
    for (var i = 0; i < all.length; i++) {
      if (known[all[i].uri] || known["name:" + all[i].name]) continue
      rows.push(all[i])
    }
    root.found = rows
    root.scanning = false
    if (root.installingUri && !rows.some(function(r) { return r.uri === root.installingUri })) root.installingUri = ""
  }

  property string installingUri: ""

  Process {
    id: scanProc
    property string collected: ""
    command: ["bash", "-lc", root.scanCommand]
    stdout: SplitParser {
      onRead: function(data) { scanProc.collected += data + "\n" }
    }
    onExited: root.applyScan()
  }

  PanelWindow {
    id: window
    visible: root.open
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "audryus-printer-discovery"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
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
      width: Math.min(Style.space(520), window.width - Style.gapsOut * 2)
      height: Math.min(Style.space(420), window.height - Style.gapsOut * 2)
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
        spacing: Style.space(10)

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "Network printers" + (root.scanning ? " — scanning…" : " — " + foundList.count + " found")
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.heading
          font.weight: Font.Medium
          elide: Text.ElideRight
        }

        ListView {
          id: foundList
          width: parent.width
          height: parent.height - Style.space(10) - Style.font.heading - Style.space(8)
          clip: true
          spacing: Style.space(6)
          model: root.found
          boundsBehavior: Flickable.StopAtBounds

          delegate: BorderSurface {
            required property var modelData
            width: foundList.width
            height: Math.max(Style.space(44), foundLabel.implicitHeight + Style.space(14))
            radius: Style.cornerRadius
            color: "transparent"
            borderSpec: Border.controlSpec("normal", Color.foreground, Color.accent)

            Text {
              id: foundLabel
              anchors.left: parent.left
              anchors.right: installButton.left
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(8)
              textFormat: Text.PlainText
              text: modelData.name + "\n" + modelData.uri
              color: Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
              maximumLineCount: 2
            }

            Button {
              id: installButton
              anchors.right: parent.right
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              text: root.installingUri === modelData.uri ? "Installing…" : "Install"
              bordered: true
              enabled: root.installingUri === "" || root.installingUri === modelData.uri
              onClicked: root.install(modelData)
            }
          }
        }

        Text {
          width: parent.width
          visible: !root.scanning && foundList.count === 0
          textFormat: Text.PlainText
          text: "No new printers found on the network."
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
