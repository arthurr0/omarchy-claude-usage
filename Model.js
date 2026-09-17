.pragma library

// Pure helpers for the Claude usage bar widget. Everything that can be
// reasoned about without a QML object lives here: parsing the JSON that
// bin/claude-usage prints, ordering and filtering the limit windows, and the
// text formatting shared by the bar pill, the tooltip and the popup.

var KIND_ORDER = { session: 0, weekly_all: 1, weekly_scoped: 2 }
var DAY_NAMES = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

function parseReport(raw) {
  var text = String(raw || "").trim()
  if (text === "") return null
  try {
    var parsed = JSON.parse(text)
    return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : null
  } catch (e) {
    return null
  }
}

function clampInt(value, lo, hi, fallback) {
  var n = parseInt(value, 10)
  if (isNaN(n)) n = fallback
  return Math.max(lo, Math.min(hi, n))
}

function clamp(value, lo, hi) {
  return Math.max(lo, Math.min(hi, value))
}

function stateOf(pct, warn, critical) {
  if (pct >= critical) return "critical"
  if (pct >= warn) return "warning"
  return "normal"
}

function longLabel(window) {
  if (window.label) return String(window.label)
  if (window.kind === "session") return "Session (5h)"
  if (window.kind === "weekly_all") return "Weekly (all models)"
  if (window.kind === "weekly_scoped") return "Weekly (" + (window.scope || "scoped") + ")"
  return String(window.key || "")
}

function shortLabel(window) {
  if (window.short_label) return String(window.short_label)
  if (window.kind === "session") return "5h"
  if (window.kind === "weekly_all") return "7d"
  if (window.kind === "weekly_scoped") return window.scope ? "7d " + window.scope : "7d scoped"
  return String(window.key || "")
}

// Normalised limit windows, sorted session → weekly → model-scoped weekly.
// Thresholds are applied here rather than trusted from the script so that a
// settings change recolours the bar without waiting for the next fetch.
function windows(report, warn, critical) {
  if (!report || !Array.isArray(report.windows)) return []
  var out = []
  for (var i = 0; i < report.windows.length; i++) {
    var raw = report.windows[i]
    if (!raw || typeof raw !== "object") continue
    var pct = Number(raw.pct)
    if (!isFinite(pct)) continue
    pct = clamp(pct, 0, 100)
    var resetsAt = Number(raw.resets_at)
    out.push({
      key: String(raw.key || raw.kind || ""),
      kind: String(raw.kind || ""),
      scope: raw.scope ? String(raw.scope) : "",
      pct: pct,
      resetsAtMs: isFinite(resetsAt) && resetsAt > 0 ? resetsAt * 1000 : 0,
      expired: raw.expired === true,
      label: longLabel(raw),
      shortLabel: shortLabel(raw),
      state: stateOf(pct, warn, critical)
    })
  }
  out.sort(function(a, b) {
    var oa = KIND_ORDER[a.kind] === undefined ? 9 : KIND_ORDER[a.kind]
    var ob = KIND_ORDER[b.kind] === undefined ? 9 : KIND_ORDER[b.kind]
    if (oa !== ob) return oa - ob
    return a.scope < b.scope ? -1 : (a.scope > b.scope ? 1 : 0)
  })
  return out
}

// `show` maps a kind to a boolean; kinds missing from the map stay visible.
function filterKinds(list, show) {
  var out = []
  for (var i = 0; i < list.length; i++) {
    var allowed = show[list[i].kind]
    if (allowed === undefined || allowed) out.push(list[i])
  }
  return out
}

function highest(list) {
  var best = null
  for (var i = 0; i < list.length; i++) {
    if (!best || list[i].pct > best.pct) best = list[i]
  }
  return best
}

function compactText(list) {
  var parts = []
  for (var i = 0; i < list.length; i++) {
    parts.push(list[i].shortLabel + " " + Math.round(list[i].pct) + "%")
  }
  return parts.join(" · ")
}

function pad2(n) {
  return (n < 10 ? "0" : "") + n
}

function formatClock(ms, nowMs) {
  var date = new Date(ms)
  var now = new Date(nowMs)
  var text = pad2(date.getHours()) + ":" + pad2(date.getMinutes())
  var sameDay = date.getFullYear() === now.getFullYear()
    && date.getMonth() === now.getMonth()
    && date.getDate() === now.getDate()
  return sameDay ? text : DAY_NAMES[date.getDay()] + " " + text
}

function formatCountdown(ms, nowMs) {
  var diff = Math.round((ms - nowMs) / 1000)
  if (diff <= 0) return "now"
  var days = Math.floor(diff / 86400)
  var hours = Math.floor((diff % 86400) / 3600)
  var minutes = Math.floor((diff % 3600) / 60)
  if (days > 0) return days + "d " + hours + "h"
  if (hours > 0) return hours + "h " + minutes + "m"
  return Math.max(1, minutes) + "m"
}

function resetText(window, nowMs) {
  if (!window) return ""
  if (!window.resetsAtMs) return "no reset information"
  if (window.expired || window.resetsAtMs <= nowMs) return "window renewed"
  return "resets in " + formatCountdown(window.resetsAtMs, nowMs) + " (" + formatClock(window.resetsAtMs, nowMs) + ")"
}

function detailLines(list, nowMs) {
  var lines = []
  for (var i = 0; i < list.length; i++) {
    lines.push(list[i].label + ": " + Math.round(list[i].pct) + "%, " + resetText(list[i], nowMs))
  }
  return lines
}

function footerText(report, nowMs, statusText) {
  var parts = []
  var updatedAt = report ? Number(report.updated_at) : 0
  if (isFinite(updatedAt) && updatedAt > 0) parts.push("updated " + formatClock(updatedAt * 1000, nowMs))
  if (report && report.source_name) parts.push("source: " + report.source_name)
  if (statusText) parts.push(statusText)
  return parts.join(" · ")
}

function expandPath(path, home) {
  var value = String(path || "").trim()
  if (value === "") return ""
  if (value === "~") return home
  if (value.indexOf("~/") === 0) return home + value.substring(1)
  if (value.indexOf("$HOME/") === 0) return home + value.substring(5)
  return value
}

// Qt.resolvedUrl gives a file:// URL; Process wants a plain path.
function localPath(url) {
  var text = String(url || "")
  if (text.indexOf("file://") === 0) text = text.substring(7)
  return decodeURIComponent(text)
}
