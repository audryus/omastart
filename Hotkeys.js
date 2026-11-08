// Hotkey read/merge/write for the omarchy Lua bindings.
//
// `hyprctl binds` is the source of truth for WHICH binds exist: it alone knows
// loop-generated binds (workspaces, panels), helper binds (toggles, holds), and
// what the user's config unbound. It reports Lua binds as an opaque `__lua`, so
// /usr/share/omarchy/default/hypr/bindings/*.lua and ~/.config/hypr/bindings.lua
// are parsed to recover each bind's command. The user file carries ONE managed
// block (MARK_BEGIN/MARK_END) owned by this UI; everything outside it is
// preserved verbatim.

var MARK_BEGIN = "-- omastart hotkeys:begin (managed — do not hand-edit)"
var MARK_END = "-- omastart hotkeys:end"

var MOD_ORDER = ["SUPER", "SHIFT", "ALT", "CTRL"]
var MOD_ALIASES = { META: "SUPER", CONTROL: "CTRL", SUPER: "SUPER", SHIFT: "SHIFT", ALT: "ALT", CTRL: "CTRL" }
var MOD_BITS = [[64, "SUPER"], [1, "SHIFT"], [8, "ALT"], [4, "CTRL"]]

var FILE_MARK = "-- @omastart-file "
var LIVE_MARK = "-- @omastart-live"

var CATEGORY_ORDER = ["Custom", "Your config", "Navigation", "Windows", "Applications", "Clipboard", "Media", "Utilities", "Input"]
var FILE_CATEGORY = {
  applications: "Applications", clipboard: "Clipboard", dictation: "Input",
  "input-method": "Input", jis: "Input", media: "Media", tiling: "Windows", utilities: "Utilities"
}
var NAVIGATION = /^(Focus on|Switch to (workspace|group)|(Next|Previous) (workspace|window)|Former workspace|Scroll active|Move grouped window focus)/i

// Hyprland binds the physical digit row, and a few symbols, by keycode.
var KEY_NAMES = {
  "code:10": "1", "code:11": "2", "code:12": "3", "code:13": "4", "code:14": "5",
  "code:15": "6", "code:16": "7", "code:17": "8", "code:18": "9", "code:19": "0",
  "code:20": "-", "code:21": "=", "code:34": "[", "code:35": "]",
  "mouse:272": "Left click", "mouse:273": "Right click", "mouse:274": "Middle click",
  mouse_down: "Scroll down", mouse_up: "Scroll up", mouse_left: "Scroll left", mouse_right: "Scroll right",
  LEFT: "←", RIGHT: "→", UP: "↑", DOWN: "↓",
  COMMA: ",", PERIOD: ".", SLASH: "/", MINUS: "-", EQUAL: "=", GRAVE: "`",
  SEMICOLON: ";", APOSTROPHE: "'", BACKSLASH: "\\", BRACKETLEFT: "[", BRACKETRIGHT: "]"
}

// A lone modifier can never fire (the mod is not active yet on its own
// press, and this Hyprland Lua API has no hl.bindr). The editor blocks
// saving them instead.
function isBareMod(normKey) {
  return MOD_ORDER.indexOf(normKey) >= 0
}

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

// o.bind_toggle("KEYS", "Label", "name"[, opts]) runs omarchy-toggle-<name>.
function parseToggleLine(line) {
  var m = String(line || "").match(/^\s*o\.bind_toggle\(\s*"((?:[^"\\]|\\.)*)"\s*,\s*"((?:[^"\\]|\\.)*)"\s*,\s*"((?:[^"\\]|\\.)*)"/)
  if (!m) return null
  return { key: unescapeLua(m[1]), label: unescapeLua(m[2]), action: "omarchy-toggle-" + unescapeLua(m[3]), actionKind: "string" }
}

function parseUnbindLine(line) {
  var m = String(line || "").match(/^\s*hl\.unbind\(\s*"((?:[^"\\]|\\.)*)"\s*\)/)
  return m ? unescapeLua(m[1]) : null
}



function parseFile(text) {
  var binds = []
  var unbinds = []
  var lines = String(text || "").split("\n")
  var file = ""
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].indexOf(FILE_MARK) === 0) { file = lines[i].substring(FILE_MARK.length).trim(); continue }
    var b = parseBindLine(lines[i]) || parseToggleLine(lines[i])
    if (b) { b.file = file; binds.push(b); continue }
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
      continue
    }
    // Hyprland's code:/mouse prefixes are case-sensitive; key names are not.
    var name = /^(code:|mouse[:_])/i.test(part) ? part.toLowerCase() : part.toUpperCase()
    key = key ? key + "+" + name : name
  }
  mods.sort(function(a, b) { return MOD_ORDER.indexOf(a) - MOD_ORDER.indexOf(b) })
  if (!key) return mods.join(" + ")
  return (mods.length > 0 ? mods.join(" + ") + " + " : "") + key
}

// Blocks of `hyprctl binds`. Plain text on purpose: Hyprland 0.56.0 emits
// invalid JSON for binds, and -j leaves the key of code: binds empty. Binds
// with no description are internal and the code:201 Copilot key only mirrors
// another bind; the official keybindings menu hides both too.
function parseLiveBinds(text) {
  var out = []
  var seen = {}
  var current = null
  function flush() {
    if (!current || !current.description) return
    var last = String(current.key || "").split(" + ").pop()
    if (!last && current.keycode && current.keycode !== "0") last = "code:" + current.keycode
    if (!last || last === "code:201") return
    var mask = parseInt(current.modmask, 10) || 0
    var parts = []
    for (var i = 0; i < MOD_BITS.length; i++) {
      if (mask & MOD_BITS[i][0]) parts.push(MOD_BITS[i][1])
    }
    parts.push(last)
    var key = normalizeKey(parts.join(" + "))
    var id = key + "\n" + current.description
    if (seen[id]) return
    seen[id] = true
    out.push({ key: key, label: current.description })
  }
  var lines = String(text || "").split("\n")
  for (var l = 0; l < lines.length; l++) {
    if (/^bind[a-z]*\s*$/.test(lines[l])) { flush(); current = {}; continue }
    var field = lines[l].match(/^\t([a-z]+): ?(.*)$/)
    if (current && field) current[field[1]] = field[2]
  }
  flush()
  return out
}

function splitDefaultsOutput(text) {
  var value = String(text || "")
  var at = value.indexOf(LIVE_MARK)
  if (at < 0) return { files: value, live: "" }
  return { files: value.substring(0, at), live: value.substring(at + LIVE_MARK.length) }
}

function categoryFor(row) {
  if (row.origin === "config") return "Your config"
  if (NAVIGATION.test(row.label || "")) return "Navigation"
  if (FILE_CATEGORY[row.file]) return FILE_CATEGORY[row.file]
  if (/window|workspace|group/i.test(row.label || "")) return "Windows"
  if (/dictation/i.test(row.label || "")) return "Input"
  return "Utilities"
}

function stripManaged(text) {
  var out = String(text || "")
  var blocks = extractBlocks(out)
  for (var i = 0; i < blocks.length; i++) out = out.replace(blocks[i], "")
  return out
}

// Non-managed rows: what Hyprland has live, with commands recovered from the
// Lua sources. Binds from the managed block are left to their custom rows.
// Without hyprctl output (no live session) the Omarchy files are the fallback.
function buildDefaults(liveBinds, fileBinds, configBinds, userRows) {
  function id(key, label) { return normalizeKey(key) + "\n" + label }
  var sources = {}
  var managed = {}
  var i
  for (i = 0; i < fileBinds.length; i++) {
    sources[id(fileBinds[i].key, fileBinds[i].label)] = { bind: fileBinds[i], origin: "omarchy" }
  }
  for (i = 0; i < configBinds.length; i++) {
    sources[id(configBinds[i].key, configBinds[i].label)] = { bind: configBinds[i], origin: "config" }
  }
  for (i = 0; i < userRows.length; i++) managed[id(userRows[i].key, userRows[i].label)] = true

  var binds = liveBinds.length > 0 ? liveBinds : fileBinds
  var out = []
  for (i = 0; i < binds.length; i++) {
    var rowId = id(binds[i].key, binds[i].label)
    if (managed[rowId]) continue
    var source = sources[rowId]
    var row = {
      key: normalizeKey(binds[i].key), label: binds[i].label,
      action: source ? source.bind.action : "",
      actionKind: source ? source.bind.actionKind : "string",
      file: source ? source.bind.file : "",
      origin: source ? source.origin : "omarchy"
    }
    row.category = categoryFor(row)
    out.push(row)
  }
  return out
}

// A readable line for what a bind does.
function describeAction(row) {
  var action = String(row.action || "")
  if (!action) return "Built-in Omarchy action"
  if (row.actionKind === "string") return "Runs " + action
  if (row.actionKind === "table") {
    var field = action.match(/(\w+)\s*=\s*"([^"]*)"/)
    if (field) {
      var verbs = { menu: "Opens the " + field[2] + " menu", panel: "Toggles the " + field[2] + " panel",
        omarchy: "Runs omarchy-launch-" + field[2], launch: "Launches " + field[2], tui: "Opens " + field[2] + " in a terminal",
        webapp: "Opens " + field[2], focus: "Focuses or launches " + field[2],
        audio: "Audio output: " + field[2], brightness: "Display brightness: " + field[2], ipc: "Shell action " + field[2] }
      if (verbs[field[1]]) return verbs[field[1]]
    }
    return action
  }
  var direction = action.match(/^hl\.dsp\.focus\(\{\s*direction\s*=\s*"([lrud])"/)
  if (direction) {
    var names = { l: "left", r: "right", u: "up", d: "down" }
    return "Moves focus " + names[direction[1]] + " and, on a scrolling workspace, scrolls to that column"
  }
  return action
}

// Key caps for display, one entry per modifier/key.
function keyCaps(normKey) {
  var parts = String(normKey || "").split(" + ")
  for (var i = 0; i < parts.length; i++) {
    if (KEY_NAMES[parts[i]]) parts[i] = KEY_NAMES[parts[i]]
    else parts[i] = parts[i].replace(/^XF86/i, "")
  }
  return parts
}

function searchText(row) {
  var words = [row.key, keyCaps(row.key).join(" "), row.label, row.action, describeAction(row), row.category]
  if (/ \+ (LEFT|RIGHT|UP|DOWN)$|^(LEFT|RIGHT|UP|DOWN)$/.test(row.key)) words.push("arrow arrows seta setas")
  if (/^hl\.dsp\.focus\(\{\s*direction/.test(String(row.action || ""))) words.push("scroll scrolling column navigation")
  return words.join(" ").toLowerCase()
}

// Every whitespace/plus-separated term must match, in any order, so
// "super left" finds SUPER + LEFT.
function matchesQuery(row, query) {
  var terms = String(query || "").toLowerCase().split(/[\s+]+/)
  var text = searchText(row)
  var caps = keyCaps(row.key).join(" ").toLowerCase().split(" ")
  for (var i = 0; i < terms.length; i++) {
    if (!terms[i]) continue
    // One character means a key: "1" must not match "m+1" or "workspace 10".
    if (terms[i].length === 1 ? caps.indexOf(terms[i]) < 0 : text.indexOf(terms[i]) < 0) return false
  }
  return true
}

// Rows flattened in category order, with a header row before each category.
function groupRows(rows) {
  var buckets = {}
  var i
  for (i = 0; i < rows.length; i++) {
    var name = rows[i].category
    if (!buckets[name]) buckets[name] = []
    buckets[name].push(rows[i])
  }
  var out = []
  for (i = 0; i < CATEGORY_ORDER.length; i++) {
    var bucket = buckets[CATEGORY_ORDER[i]]
    if (!bucket) continue
    out.push({ header: CATEGORY_ORDER[i], count: bucket.length })
    out = out.concat(bucket)
  }
  return out
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
      source: "default", origin: entry.origin || "omarchy",
      category: entry.category || categoryFor(entry), modifiedBy: over || null
    })
  }
  for (var j = 0; j < userRows.length; j++) {
    rows.push({
      key: normalizeKey(userRows[j].key), label: userRows[j].label,
      action: userRows[j].action, actionKind: userRows[j].actionKind || "string",
      source: "user", category: "Custom", replaces: userRows[j].replaces || []
    })
  }
  return rows
}

function actionSource(row) {
  if (row.actionKind === "string") return "\"" + escapeLua(row.action) + "\""
  return row.action
}

function serializeRow(row) {
  return "o.bind(\"" + escapeLua(row.key) + "\", \"" + escapeLua(row.label) + "\", " + actionSource(row) + ")"
}

function serializeBlock(userRows) {
  var lines = [MARK_BEGIN]
  for (var i = 0; i < userRows.length; i++) {
    var row = userRows[i]
    var reps = row.replaces || []
    for (var r = 0; r < reps.length; r++) lines.push("hl.unbind(\"" + escapeLua(reps[r]) + "\")")
    lines.push(serializeRow(row))
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
    FILE_MARK: FILE_MARK,
    LIVE_MARK: LIVE_MARK,
    normalizeKey: normalizeKey,
    parseLiveBinds: parseLiveBinds,
    splitDefaultsOutput: splitDefaultsOutput,
    stripManaged: stripManaged,
    buildDefaults: buildDefaults,
    describeAction: describeAction,
    keyCaps: keyCaps,
    matchesQuery: matchesQuery,
    groupRows: groupRows,
    isBareMod: isBareMod,
    mergeView: mergeView,
    serializeBlock: serializeBlock,
    extractBlock: extractBlock,
    extractBlocks: extractBlocks,
    replaceBlock: replaceBlock,
    parseUserRows: parseUserRows
  }
}
