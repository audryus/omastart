import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Printers section: installed CUPS printers plus network discovery.
// Discovery opens its own window (outside click / Esc closes, no X);
// install buttons are listed but not wired yet.
Item {
  id: root

  property var installed: []
  property bool discoveryOpen: false

  // Bubbled up so Settings closes itself for the installer terminal.
  signal installStarted()

  // Reachability per queue name (network printers only). Unknown until the
  // first probe lands; polling runs only while this page is visible.
  property var onlineMap: ({})
  property string refreshingName: ""

  readonly property var netSchemes: ["ipp", "ipps", "lpd", "socket", "http", "https"]

  function isNetwork(uri) {
    var m = String(uri || "").match(/^([a-z]+):\/\//)
    return m ? root.netSchemes.indexOf(m[1]) >= 0 : false
  }

  function targetFor(uri) {
    var m = String(uri || "").match(/^([a-z]+):\/\/([^/:]+)(?::(\d+))?/)
    if (!m) return null
    var defaults = { ipp: 631, ipps: 631, lpd: 515, socket: 9100, http: 80, https: 443 }
    return { host: m[2], port: m[3] ? Number(m[3]) : (defaults[m[1]] || 0) }
  }

  // USB (cable) printers: hp:/usb included. Presence = make/model words
  // showing up in lsusb (no stable device node to probe instead).
  function isUsb(uri) {
    var u = String(uri || "")
    return u.indexOf("usb://") === 0 || u.indexOf("hp:/usb") === 0
  }

  function usbTokens(uri) {
    var u = String(uri || "")
    var m = u.match(/^usb:\/\/([^?]*)/) || u.match(/^hp:\/usb\/([^?]*)/)
    var words = m ? decodeURIComponent(m[1]).split(/[^A-Za-z0-9]+/) : []
    var out = []
    for (var i = 0; i < words.length; i++) {
      if (words[i].length >= 4) out.push(words[i].toLowerCase())
    }
    return out
  }

  // hp:/net/Model?ip=1.2.3.4 behaves like a network printer on 9100.
  function hpNetTarget(uri) {
    var m = String(uri || "").match(/^hp:\/net\/[^?]*\?.*ip=([^&]*)/)
    if (m && m[1]) return { host: m[1], port: 9100 }
    return null
  }

  function netPrinters() {
    var out = []
    var list = Array.isArray(root.installed) ? root.installed : []
    for (var i = 0; i < list.length; i++) {
      var t = null
      if (root.isNetwork(list[i].uri)) t = root.targetFor(list[i].uri)
      else if (String(list[i].uri || "").indexOf("hp:/net") === 0) t = root.hpNetTarget(list[i].uri)
      if (!t || !t.host || !t.port) continue
      out.push({ name: String(list[i].name), host: t.host, port: t.port })
    }
    return out
  }

  function usbPrinters() {
    var out = []
    var list = Array.isArray(root.installed) ? root.installed : []
    for (var i = 0; i < list.length; i++) {
      if (!root.isUsb(list[i].uri)) continue
      out.push({ name: String(list[i].name), tokens: root.usbTokens(list[i].uri) })
    }
    return out
  }

  function probeAll() {
    if (probeProc.running) return
    var targets = root.netPrinters()
    var usbs = root.usbPrinters()
    if (targets.length === 0 && usbs.length === 0) return
    probeTargets = targets
    probeUsbs = usbs
    // NOTE: bash /dev/tcp does not resolve .local (no mDNS on its lookup
    // path), so resolve via getent first and TCP-check the resulting IP.
    var script = ""
    for (var i = 0; i < targets.length; i++) {
      script += "{ ip=$(getent ahosts '" + targets[i].host + "' 2>/dev/null | awk '{print $1; exit}');"
        + " if [ -n \"$ip\" ]; then timeout 2 bash -c \"</dev/tcp/$ip/" + targets[i].port + "\" >/dev/null 2>&1 && echo 'T" + i + ":1' || echo 'T" + i + ":0';"
        + " else echo 'T" + i + ":0'; fi; }; "
    }
    script += "echo '@@USB'; lsusb 2>/dev/null; echo '@@END'"
    probeProc.command = ["bash", "-lc", script]
    probeProc.collected = ""
    probeProc.running = true
  }

  function applyProbe() {
    var next = {}
    for (var k in root.onlineMap) next[k] = root.onlineMap[k]
    var inUsb = false
    var usbText = ""
    var lines = probeProc.collected.split("\n")
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (line === "@@USB") { inUsb = true; continue }
      if (line === "@@END") { inUsb = false; continue }
      if (inUsb) { usbText += " " + line.toLowerCase(); continue }
      var parts = line.split(":")
      if (parts.length !== 2 || parts[0].charAt(0) !== "T") continue
      var t = probeTargets[Number(parts[0].substring(1))]
      if (t) next[t.name] = parts[1] === "1"
    }
    for (var j = 0; j < probeUsbs.length; j++) {
      var u = probeUsbs[j]
      var hit = false
      for (var k2 = 0; k2 < u.tokens.length; k2++) {
        if (usbText.indexOf(u.tokens[k2]) >= 0) { hit = true; break }
      }
      // No tokens to match on (odd URI) counts as unknown, not offline.
      next[u.name] = u.tokens.length > 0 ? hit : undefined
    }
    root.onlineMap = next
  }

  // Reachable = anything with an indicator (network or USB).
  function hasIndicator(uri) {
    return root.isNetwork(uri) || root.isUsb(uri)
      || String(uri || "").indexOf("hp:/net") === 0
  }

  readonly property bool hasOffline: {
    var list = Array.isArray(root.installed) ? root.installed : []
    for (var i = 0; i < list.length; i++) {
      if (root.hasIndicator(list[i].uri) && root.onlineMap[String(list[i].name)] === false) return true
    }
    return false
  }

  // Refresh: re-run discovery for one queue (its IP may have changed) and
  // point CUPS at the new URI. Matches on normalized names since queue
  // names are sanitized at install time.
  function normName(value) {
    return String(value || "").toLowerCase().replace(/[^a-z0-9]/g, "")
  }

  function refreshPrinter(name) {
    if (refreshProc.running || !name) return
    root.refreshingName = name
    refreshProc.collected = ""
    refreshProc.command = ["bash", "-lc", discovery.scanCommand]
    refreshProc.running = true
  }

  function applyRefresh() {
    var name = root.refreshingName
    root.refreshingName = ""
    if (!name) return
    var rows = []
    try { rows = discovery.parseDiscovery(refreshProc.collected) } catch (e) { rows = [] }
    var want = root.normName(name)
    var hit = null
    for (var i = 0; i < rows.length; i++) {
      var got = root.normName(rows[i].name)
      if (got === want || got.indexOf(want) >= 0 || want.indexOf(got) >= 0) { hit = rows[i]; break }
    }
    if (!hit) return
    var current = ""
    var list = Array.isArray(root.installed) ? root.installed : []
    for (var j = 0; j < list.length; j++) {
      if (String(list[j].name) === name) current = String(list[j].uri || "")
    }
    if (hit.uri && hit.uri !== current) {
      // Admin op: graphical polkit prompt, no terminal needed.
      Util.execDetached("pkexec lpadmin -p " + Util.shellQuote(name) + " -v " + Util.shellQuote(hit.uri))
    }
    // Converges on the fast offline ticks once the change lands.
    root.refreshInstalled()
    root.probeAll()
  }

  Process {
    id: probeProc
    property string collected: ""
    stdout: SplitParser {
      onRead: function(data) { probeProc.collected += data + "\n" }
    }
    onExited: {
      root.applyProbe()
      root.refreshInstalled()
    }
  }

  property var probeTargets: []
  property var probeUsbs: []

  Process {
    id: refreshProc
    property string collected: ""
    stdout: SplitParser {
      onRead: function(data) { refreshProc.collected += data + "\n" }
    }
    onExited: root.applyRefresh()
  }

  // Fast ticks while anything is offline, slow ones when all reachable.
  // Bound to visibility: leaving the page stops the pinging.
  Timer {
    id: probeTimer
    interval: root.hasOffline ? 5000 : 30000
    repeat: true
    running: root.visible
    triggeredOnStart: true
    onTriggered: root.probeAll()
  }

  function refreshInstalled() {
    if (!installedProc.running) {
      installedProc.collected = ""
      installedProc.running = true
    }
  }

  // `lpstat -p` lines look like: `printer NAME is idle. enabled since ...`
  // `lpstat -v` lines look like: `device for NAME: URI`
  // `lpstat -d` line looks like: `system default destination: NAME`
  function applyInstalled() {
    var uris = {}
    var states = []
    var fallback = "no system default destination"
    var lines = installedProc.collected.split("\n")
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      // CUPS names carry no spaces; \S+ avoids the greedy match eating
      // the colons inside ipp:// URIs.
      var mDev = line.match(/^device for (\S+):\s*(\S+)/)
      if (mDev) { uris[mDev[1]] = mDev[2]; continue }
      var mPr = line.match(/^printer (\S+)\s+(.*)$/)
      if (mPr) { states.push({ name: mPr[1], state: mPr[2] }); continue }
      var mDef = line.match(/destination:\s*(.+)$/)
      if (mDef) fallback = mDef[1].trim()
    }
    var rows = []
    for (var j = 0; j < states.length; j++) {
      rows.push({
        name: states[j].name,
        state: states[j].state,
        uri: uris[states[j].name] || "",
        isDefault: states[j].name === fallback
      })
    }
    root.installed = rows
  }

  Process {
    id: installedProc
    property string collected: ""
    command: ["bash", "-lc", "lpstat -p 2>/dev/null; lpstat -v 2>/dev/null; lpstat -d 2>/dev/null"]
    stdout: SplitParser {
      onRead: function(data) { installedProc.collected += data + "\n" }
    }
    onExited: root.applyInstalled()
  }

  Component.onCompleted: root.refreshInstalled()

  Column {
    anchors.fill: parent
    spacing: Style.space(10)

    Text {
      id: heading
      width: parent.width
      textFormat: Text.PlainText
      text: "Printers"
      color: Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.heading
      font.weight: Font.Medium
    }

    Button {
      id: findButton
      width: parent.width
      text: "Find network printers"
      bordered: true
      onClicked: {
        root.discoveryOpen = true
        discovery.refresh()
      }
    }

    Flickable {
      width: parent.width
      height: parent.height - heading.height - findButton.height - Style.space(10) * 2
      contentWidth: width
      contentHeight: installedCol.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height

      Column {
        id: installedCol
        width: parent.width
        spacing: Style.space(6)

        Repeater {
          model: root.installed
          delegate: BorderSurface {
            required property var modelData
            readonly property bool net: root.hasIndicator(modelData.uri)
            readonly property bool refreshable: root.isNetwork(modelData.uri)
              || String(modelData.uri || "").indexOf("hp:/net") === 0
            // undefined until the first probe lands.
            readonly property var online: root.onlineMap[String(modelData.name)]
            width: installedCol.width
            height: Math.max(Style.space(40), printerTexts.implicitHeight + (net ? Style.space(26) : 0) + Style.space(14))
            radius: Style.cornerRadius
            color: "transparent"
            borderSpec: Border.controlSpec("normal", Color.foreground, Color.accent)

            Column {
              id: printerTexts
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(10)
              spacing: 2

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: modelData.name + (modelData.isDefault ? "  ·  default" : "")
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.weight: Font.Medium
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                visible: (modelData.uri || modelData.state) !== ""
                textFormat: Text.PlainText
                text: [modelData.state, modelData.uri].filter(function(p) { return p }).join("  ·  ")
                color: Color.foreground
                opacity: 0.55
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }

              // Reachability (network + USB) + Refresh for network
              // printers when offline, in case its IP moved.
              Item {
                visible: net
                width: parent.width
                height: Style.space(24)

                Rectangle {
                  id: statusDot
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(8)
                  height: Style.space(8)
                  radius: width / 2
                  color: online === true ? Color.accent : (online === false ? Color.urgent : Color.foreground)
                  opacity: online === undefined ? 0.4 : 1.0
                }

                Text {
                  anchors.left: statusDot.right
                  anchors.leftMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: online === true ? "Online" : (online === false ? "Offline" : "Checking…")
                  color: Color.foreground
                  opacity: 0.75
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }

                Button {
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  // Shown while checking too: manual path even if the
                  // automatic probe stalls.
                  visible: refreshable && online !== true
                  text: root.refreshingName === modelData.name ? "Searching…" : "Refresh"
                  enabled: root.refreshingName === ""
                  onClicked: root.refreshPrinter(String(modelData.name))
                }
              }
            }
          }
        }

        Text {
          visible: root.installed.length === 0
          width: parent.width
          textFormat: Text.PlainText
          text: "No printers installed."
          color: Color.foreground
          opacity: 0.55
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          wrapMode: Text.WordWrap
        }
      }
    }
  }

  // ---- Network discovery window (no X; outside click / Esc closes) ----
  Discovery {
    id: discovery
    open: root.discoveryOpen
    installed: root.installed
    onRequestClose: root.discoveryOpen = false
    onInstallLaunched: {
      root.discoveryOpen = false
      root.installStarted()
      root.refreshInstalled()
    }
  }
}
