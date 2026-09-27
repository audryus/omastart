// Hotkey read/merge/write for the omarchy Lua bindings.
//
// Sources: /usr/share/omarchy/default/hypr/bindings/*.lua (read-only) and
// ~/.config/hypr/bindings.lua (user file). The user file carries ONE managed
// block (MARK_BEGIN/MARK_END) owned by this UI; everything outside it is
// preserved verbatim. Loop-generated binds (workspaces, panels) cannot be
// parsed statically and are skipped — they keep working, just unlisted.

var MARK_BEGIN = "-- omastart hotkeys:begin (managed — do not hand-edit)"
var MARK_END = "-- omastart hotkeys:end"

var MOD_ORDER = ["SUPER", "SHIFT", "ALT", "CTRL"]
var MOD_ALIASES = { META: "SUPER", CONTROL: "CTRL", SUPER: "SUPER", SHIFT: "SHIFT", ALT: "ALT", CTRL: "CTRL" }

function unescapeLua(value) {
  return String(value || "").replace(/\\(.)/g, "$1")
}

function escapeLua(value) {
  return String(value || "").replace(/\\/g, "\\\\").replace(/"/g, "\\\"")
}

// One literal o.bind(...) per line. Multiline/dynamic calls are skipped.
function parseBindLine(line) {
  var m = String(line || "").match(/^\s*o\.bind\(\s*"((?:[^"\\]|\\.)*)"\s*,\s*(nil|"((?:[^"\\]|\\.)*)")\s*,\s*(.+?)\s*\)\s*$/)
  if (!m) return null
  var actionRaw = m[4]
  var kind = "expr"
  var action = actionRaw
  var str = actionRaw.match(/^"([\s\S]*)"$/)
  if (str) { kind = "string"; action = unescapeLua(str[1]) }
  else if (/^\{[\s\S]*\}$/.test(actionRaw)) { kind = "table"; action = actionRaw }
  return { key: unescapeLua(m[1]), label: m[3] !== undefined ? unescapeLua(m[3]) : "", action: action, actionKind: kind }
}

function parseUnbindLine(line) {
  var m = String(line || "").match(/^\s*hl\.unbind\(\s*"((?:[^"\\]|\\.)*)"\s*\)/)
  return m ? unescapeLua(m[1]) : null
}

function parseFile(text) {
  var binds = []
  var unbinds = []
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var b = parseBindLine(lines[i])
    if (b) { binds.push(b); continue }
    var u = parseUnbindLine(lines[i])
    if (u) unbinds.push(u)
  }
  return { binds: binds, unbinds: unbinds }
}

function normalizeKey(seq) {
  var mods = []
  var key = ""
  // Split on runs of space/plus: sources mix "SUPER + X" and "SUPER SHIFT + X".
  var parts = String(seq || "").split(/[\s+]+/)
  for (var i = 0; i < parts.length; i++) {
    var part = parts[i]
    if (!part) continue
    var alias = MOD_ALIASES[part.toUpperCase()]
    if (alias) {
      if (mods.indexOf(alias) < 0) mods.push(alias)
    } else if (!key) {
      key = part.toUpperCase()
    } else {
      key += "+" + part.toUpperCase()
    }
  }
  mods.sort(function(a, b) { return MOD_ORDER.indexOf(a) - MOD_ORDER.indexOf(b) })
  if (!key) return mods.join(" + ")
  return (mods.length > 0 ? mods.join(" + ") + " + " : "") + key
}

// Display rows: defaults overlaid with user state.
function mergeView(defaultBinds, userRows) {
  var replacedBy = {}
  for (var u = 0; u < userRows.length; u++) {
    var reps = userRows[u].replaces || []
    for (var r = 0; r < reps.length; r++) replacedBy[normalizeKey(reps[r])] = userRows[u]
  }
  var rows = []
  for (var i = 0; i < defaultBinds.length; i++) {
    var entry = defaultBinds[i]
    var norm = normalizeKey(entry.key)
    var over = replacedBy[norm]
    rows.push({
      key: norm, label: entry.label, action: entry.action, actionKind: entry.actionKind,
      source: "default", modifiedBy: over || null
    })
  }
  for (var j = 0; j < userRows.length; j++) {
    rows.push({
      key: normalizeKey(userRows[j].key), label: userRows[j].label,
      action: userRows[j].action, actionKind: userRows[j].actionKind || "string",
      source: "user", replaces: userRows[j].replaces || []
    })
  }
  return rows
}

function actionSource(row) {
  if (row.actionKind === "string") return "\"" + escapeLua(row.action) + "\""
  return row.action
}

function serializeBlock(userRows) {
  var lines = [MARK_BEGIN]
  for (var i = 0; i < userRows.length; i++) {
    var row = userRows[i]
    var reps = row.replaces || []
    for (var r = 0; r < reps.length; r++) lines.push("hl.unbind(\"" + escapeLua(reps[r]) + "\")")
    lines.push("o.bind(\"" + escapeLua(row.key) + "\", \"" + escapeLua(row.label) + "\", " + actionSource(row) + ")")
  }
  lines.push(MARK_END)
  return lines.join("\n") + "\n"
}

function extractBlocks(text) {
  var found = []
  var rest = String(text || "")
  var start = rest.indexOf(MARK_BEGIN)
  while (start >= 0) {
    var end = rest.indexOf(MARK_END, start)
    if (end < 0) break
    found.push(rest.substring(start, end + MARK_END.length))
    rest = rest.substring(end + MARK_END.length)
    start = rest.indexOf(MARK_BEGIN)
  }
  return found
}

function extractBlock(text) {
  var blocks = extractBlocks(text)
  return blocks.length > 0 ? blocks[0] : null
}

function replaceBlock(text, block) {
  // Consolidate: drop every stale managed block, keep one.
  var cleaned = String(text || "")
  var blocks = extractBlocks(cleaned)
  for (var i = 0; i < blocks.length; i++) {
    cleaned = cleaned.replace(blocks[i], "")
  }
  var trimmed = cleaned.replace(/\s+$/, "")
  return trimmed + "\n\n" + block
}

// User rows back out of our own managed block(s): pending hl.unbind
// lines attach to the bind that follows them.
function parseUserRows(text) {
  var blocks = extractBlocks(text)
  if (blocks.length === 0) return []
  var rows = []
  var pending = []
  var lines = blocks.join("\n").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line || line.indexOf("--") === 0) continue
    var u = parseUnbindLine(lines[i])
    if (u) { pending.push(u); continue }
    var b = parseBindLine(lines[i])
    if (b) {
      rows.push({
        key: normalizeKey(b.key), label: b.label, action: b.action,
        actionKind: b.actionKind, replaces: pending.slice()
      })
      pending = []
    }
  }
  return rows
}

if (typeof module !== "undefined") {
  module.exports = {
    parseFile: parseFile,
    normalizeKey: normalizeKey,
    mergeView: mergeView,
    serializeBlock: serializeBlock,
    extractBlock: extractBlock,
    extractBlocks: extractBlocks,
    replaceBlock: replaceBlock,
    parseUserRows: parseUserRows
  }
}
