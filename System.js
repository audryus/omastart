// System footer rows for audryus.omastart.
//
// Pure logic (no imports): the caller parses + merges with MenuModel.js and
// hands the merged maps in:
//
//   System.systemRows(MenuModel.mergeMenuSources(def, usr).items, ...itemOrder)
//
// Returns an array of {id,label,icon,action} with Settings at position zero
// followed by the children of the "system" submenu, in menu order.

function settingsRow() {
  return {
    id: "settings",
    label: "Settings",
    icon: "\ue615",
    action: "omarchy-shell shell toggle omarchy.menu '{\"menu\":\"setup\"}'"
  }
}

function systemRows(items, itemOrder) {
  var rows = [settingsRow()]
  var order = Array.isArray(itemOrder) ? itemOrder : []
  for (var i = 0; i < order.length; i++) {
    var entry = items ? items[order[i]] : null
    if (!entry || entry.parent !== "system") continue
    rows.push({
      id: entry.id,
      label: entry.label || entry.id,
      icon: entry.icon || "",
      action: entry.action || ""
    })
  }
  return rows
}

// ---- Tree navigation for the left pane (Win7-style) --------------------
// Row 2 shows this tree; row 3 lists every app directly, so apps is not a
// tree root here. Setup (Settings) and system live in the footer instead.
var TOP_ROOTS = ["apps", "learn", "trigger", "style"]
var TREE_ROOTS = ["learn", "trigger", "style"]

function topSegment(id) {
  return String(id || "").split(".")[0]
}

function inHiddenSubtree(id) {
  return TOP_ROOTS.indexOf(topSegment(id)) < 0 && topSegment(id) !== "root"
}

function hasChildren(items, itemOrder, id) {
  var target = id
  var entry = items ? items[id] : null
  if (entry && entry.kind === "link" && entry.target) target = entry.target
  var order = Array.isArray(itemOrder) ? itemOrder : []
  for (var i = 0; i < order.length; i++) {
    var child = items ? items[order[i]] : null
    if (child && child.parent === target) return true
  }
  return false
}

function toRow(items, itemOrder, entry) {
  return {
    id: entry.id,
    label: entry.label || entry.id,
    icon: entry.icon || "",
    iconFont: entry.iconFont || "",
    kind: entry.kind || "menu",
    action: entry.action || "",
    target: entry.target || "",
    provider: entry.provider || "",
    // apps children come from DesktopEntries at render time, not JSONC.
    hasChildren: entry.id === "apps" || hasChildren(items, itemOrder, entry.id)
  }
}

function topRows(items, itemOrder) {
  var rows = []
  for (var i = 0; i < TOP_ROOTS.length; i++) {
    var entry = items ? items[TOP_ROOTS[i]] : null
    if (!entry || entry.id === "root") continue
    rows.push(toRow(items, itemOrder, entry))
  }
  return rows
}

function treeRows(items, itemOrder) {
  var rows = []
  for (var i = 0; i < TREE_ROOTS.length; i++) {
    var entry = items ? items[TREE_ROOTS[i]] : null
    if (!entry || entry.id === "root") continue
    rows.push(toRow(items, itemOrder, entry))
  }
  return rows
}

// ---- Installed applications (same DesktopEntries source as the menu) ----

function appName(entry) {
  return String((entry && (entry.name || entry.id)) || "")
}

function appSubtext(entry) {
  return String((entry && (entry.genericName || entry.comment)) || "")
}

function appSection(label) {
  var first = String(label || "").charAt(0).toUpperCase()
  if (first >= "0" && first <= "9") return "0-9"
  if (first >= "A" && first <= "Z") return first
  return "#"
}

function appRow(entry) {
  var desktopId = String((entry && entry.id) || "")
  var label = appName(entry) || desktopId
  return {
    id: "apps." + desktopId,
    kind: "app",
    label: label,
    detail: appSubtext(entry),
    section: appSection(label),
    icon: "",
    appIcon: String((entry && entry.icon) || ""),
    appId: desktopId,
    action: "",
    hasChildren: false
  }
}

// DesktopEntries.applications.values is array-like but NOT a JS Array,
// so iterate by length instead of Array.isArray (which dropped all 63).
function asList(values) {
  if (!values || typeof values.length !== "number") return []
  var out = []
  for (var i = 0; i < values.length; i++) out.push(values[i])
  return out
}

function appEntries(values) {
  var list = asList(values)
  var out = []
  for (var i = 0; i < list.length; i++) {
    if (list[i] && list[i].noDisplay) continue
    if (!appName(list[i])) continue
    out.push(list[i])
  }
  out.sort(function(a, b) {
    var x = appName(a).toLowerCase(), y = appName(b).toLowerCase()
    return x < y ? -1 : (x > y ? 1 : 0)
  })
  return out
}

function appRows(values) {
  var rows = []
  var entries = appEntries(values)
  for (var i = 0; i < entries.length; i++) rows.push(appRow(entries[i]))
  return rows
}

function searchApps(values, query) {
  var terms = String(query || "").toLowerCase().trim().split(/\s+/)
  var rows = []
  var entries = appEntries(values)
  for (var i = 0; i < entries.length; i++) {
    var entry = entries[i]
    var kw = ""
    try {
      if (entry.keywords && typeof entry.keywords.join === "function") kw = entry.keywords.join(" ")
    } catch (e) { }
    var hay = [appName(entry), appSubtext(entry), kw].join(" ").toLowerCase()
    var ok = true
    for (var t = 0; t < terms.length; t++) {
      if (!terms[t]) continue
      if (hay.indexOf(terms[t]) < 0) { ok = false; break }
    }
    if (ok) rows.push(appRow(entry))
  }
  return rows
}

function childRows(items, itemOrder, parentId) {
  var rows = []
  var order = Array.isArray(itemOrder) ? itemOrder : []
  for (var i = 0; i < order.length; i++) {
    var entry = items ? items[order[i]] : null
    if (!entry || entry.parent !== parentId) continue
    if (inHiddenSubtree(entry.id)) continue
    rows.push(toRow(items, itemOrder, entry))
  }
  return rows
}

function rowLabel(items, id) {
  var entry = items ? items[id] : null
  return entry ? (entry.label || entry.id) : ""
}

function parentPath(items, id) {
  var labels = []
  var current = items ? items[id] : null
  if (current) current = items[current.parent]
  var guard = 0
  while (current && current.id !== "root" && guard < 32) {
    labels.unshift(current.label || current.id)
    current = items[current.parent]
    guard += 1
  }
  return labels.join(" › ")
}

// Flat search across the visible subtrees (mirrors MenuModel.matchesQuery:
// every term must appear in name text or as whole words in description).
function searchRows(items, itemOrder, query) {
  var terms = String(query || "").toLowerCase().trim().split(/\s+/)
  var rows = []
  var order = Array.isArray(itemOrder) ? itemOrder : []
  for (var i = 0; i < order.length; i++) {
    var entry = items ? items[order[i]] : null
    if (!entry || entry.id === "root") continue
    if (inHiddenSubtree(entry.id)) continue
    var aliases = Array.isArray(entry.aliases) ? entry.aliases.join(" ") : ""
    var leaf = String(entry.id || "").split(".").pop()
    var nameText = [entry.label, leaf, aliases].join(" ").toLowerCase()
    var descText = String(entry.description || "").toLowerCase()
    var descWords = descText.split(/\s+/)
    var ok = true
    for (var t = 0; t < terms.length; t++) {
      if (!terms[t]) continue
      if (nameText.indexOf(terms[t]) >= 0) continue
      if (descWords.indexOf(terms[t]) >= 0) continue
      ok = false
      break
    }
    if (!ok) continue
    var row = toRow(items, itemOrder, entry)
    row.detail = parentPath(items, entry.id)
    rows.push(row)
  }
  return rows
}

if (typeof module !== "undefined") {
  module.exports = {
    settingsRow: settingsRow,
    systemRows: systemRows,
    topRows: topRows,
    treeRows: treeRows,
    childRows: childRows,
    searchRows: searchRows,
    rowLabel: rowLabel,
    parentPath: parentPath,
    appRows: appRows,
    searchApps: searchApps
  }
}
