import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Claude usage for the Omarchy bar: a pill showing the busiest limit window
// (or every window) and a popup with a meter and reset countdown per window,
// plus a settings page. The numbers come from bin/claude-usage, the script
// shared with claude-plasma-widget's Waybar, Polybar and Plasma variants, so
// the bar, the Claude Code statusline and the popup always agree.
Panel {
  id: root
  moduleName: "io.github.arthurr0.claude-usage"
  ipcTarget: "claude-usage"
  manageIpc: false

  // ------------------------------------------------------------------ theme

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color track: Style.selectedFillFor(foreground, Color.accent)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool vertical: bar ? bar.vertical : false

  // --------------------------------------------------------------- settings
  // Inline on the widget's shell.json layout entry; see manifest.json.

  readonly property int refreshIntervalSec: Math.max(30, Model.clampInt(setting("refreshIntervalSec", 120), 30, 86400, 120))
  readonly property int warnPercent: Model.clampInt(setting("warnPercent", 70), 0, 100, 70)
  readonly property int criticalPercent: Model.clampInt(setting("criticalPercent", 90), 0, 100, 90)
  readonly property string barMode: String(setting("barMode", "highest"))
  readonly property string barStyle: String(setting("barStyle", "text"))
  readonly property bool showSession: setting("showSession", true) !== false
  readonly property bool showWeekly: setting("showWeekly", true) !== false
  readonly property bool showScoped: setting("showScoped", true) !== false
  readonly property string icon: String(setting("icon", "󰚩"))
  readonly property string warningColor: String(setting("warningColor", "#f67400"))
  readonly property string criticalColor: String(setting("criticalColor", ""))
  readonly property string commandSetting: String(setting("command", ""))
  readonly property string rightClickCommand: String(setting("onRightClick", ""))

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || home + "/.cache") + "/claude-usage"
  readonly property string bundledScript: Model.localPath(Qt.resolvedUrl("bin/claude-usage"))

  // ------------------------------------------------------------------- data

  property var report: null
  property string errorText: ""
  property string stderrText: ""
  property bool gotOutput: false
  property string pendingKind: ""
  property double lastFetchMs: 0
  property double nowMs: Date.now()

  readonly property var allWindows: Model.windows(report, warnPercent, criticalPercent)
  readonly property var barWindows: Model.filterKinds(allWindows, {
    session: showSession,
    weekly_all: showWeekly,
    weekly_scoped: showScoped
  })
  readonly property var highest: Model.highest(barWindows)
  readonly property var compactItems: barMode === "icon" ? [] : (barMode === "all" ? barWindows : (highest ? [highest] : []))
  readonly property bool hasData: allWindows.length > 0
  readonly property bool alarming: !!highest && highest.state === "critical"
  readonly property bool busy: fetchProc.running
  readonly property string planName: report && report.plan ? String(report.plan) : ""
  readonly property string sourceName: report && report.source_name ? String(report.source_name) : ""
  readonly property string statusText: errorText !== "" ? errorText : (report && report.error ? String(report.error) : "")
  readonly property string compactText: vertical
    ? (highest ? Math.round(highest.pct) + "%" : "")
    : Model.compactText(compactItems)
  readonly property string tooltipText: hasData
    ? Model.detailLines(allWindows, nowMs).join("\n")
    : (statusText !== "" ? "Claude usage: " + statusText : "Claude usage: fetching limits")
  readonly property string heroMeta: {
    var parts = []
    if (planName !== "") parts.push(planName)
    if (sourceName !== "") parts.push("via " + sourceName)
    return parts.join(" · ")
  }

  // ------------------------------------------------------------- settings
  //
  // The popup doubles as the settings dialog. Writes go through the shell's
  // own setBarWidget IPC (what `omarchy bar set` calls), so shell.json is
  // the only store and the widget re-reads its settings like any other edit.

  property bool settingsOpen: false
  property var saveQueue: []
  property string saveError: ""

  readonly property var settingDefaults: ({
    barMode: "highest",
    barStyle: "text",
    showSession: true,
    showWeekly: true,
    showScoped: true,
    refreshIntervalSec: 120,
    warnPercent: 70,
    criticalPercent: 90,
    warningColor: "#f67400",
    criticalColor: "",
    icon: "󰚩",
    command: "",
    onRightClick: ""
  })

  function saveSetting(key, value) {
    saveQueue = saveQueue.concat([{ key: key, value: value }])
    pumpSaves()
  }

  function resetSettings() {
    for (var key in settingDefaults) saveSetting(key, settingDefaults[key])
  }

  function pumpSaves() {
    if (saveProc.running || saveQueue.length === 0) return
    var next = saveQueue[0]
    saveQueue = saveQueue.slice(1)
    saveProc.command = ["omarchy-shell", "shell", "setBarWidget", moduleName, next.key, JSON.stringify(next.value), "{}"]
    saveProc.running = true
  }

  Process {
    id: saveProc
    running: false

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var reply = String(text || "").trim()
        root.saveError = reply === "ok" || reply === "" ? "" : reply
      }
    }

    onExited: function(exitCode, exitStatus) {
      if (exitCode !== 0 && root.saveError === "") root.saveError = "saving failed (omarchy-shell exit " + exitCode + ")"
      root.pumpSaves()
    }
  }

  function stateColor(state) {
    if (state === "critical") return criticalColor !== "" ? criticalColor : urgent
    if (state === "warning") return warningColor !== "" ? warningColor : foreground
    return foreground
  }

  // ---------------------------------------------------------------- fetching
  //
  // kind: "normal" honours the script's own cache (--min-interval), "force"
  // always asks the API, "cache" only re-reads what is already on disk (used
  // when the Claude Code statusline hook writes a fresh snapshot).

  function fetchCommand(kind) {
    var args = ["--format", "json"]
    if (kind === "force") args.push("--min-interval", "0")
    if (kind === "cache") args.push("--no-api")
    if (commandSetting !== "") return [Model.expandPath(commandSetting, home)].concat(args)
    return ["python3", bundledScript].concat(args)
  }

  function runFetch(kind) {
    if (fetchProc.running) {
      if (kind === "force" || pendingKind === "") pendingKind = kind
      return
    }
    gotOutput = false
    stderrText = ""
    fetchProc.command = fetchCommand(kind)
    fetchProc.running = true
  }

  function refresh() { runFetch("normal") }
  function refreshNow() { runFetch("force") }

  function applyOutput(text) {
    var parsed = Model.parseReport(text)
    if (!parsed) {
      if (String(text || "").trim() !== "") errorText = "unreadable claude-usage output"
      return
    }
    gotOutput = true
    report = parsed
    errorText = ""
    nowMs = Date.now()
  }

  Process {
    id: fetchProc
    running: false

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyOutput(text)
    }

    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.stderrText = String(text || "").trim()
    }

    onExited: function(exitCode, exitStatus) {
      root.lastFetchMs = Date.now()
      if (!root.gotOutput) {
        var lines = root.stderrText.split("\n")
        root.errorText = root.stderrText !== "" ? lines[lines.length - 1] : "claude-usage failed (exit " + exitCode + ")"
      }
      if (root.pendingKind !== "") {
        var kind = root.pendingKind
        root.pendingKind = ""
        root.runFetch(kind)
      }
    }
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // The statusline helper drops a snapshot every time Claude Code redraws
  // its status line, and the script itself refreshes the API cache; either
  // write is a reason to re-read the cache instead of waiting for the timer.
  FileView {
    path: root.cacheDir + "/statusline.json"
    watchChanges: true
    printErrors: false
    onFileChanged: cacheRefresh.restart()
  }

  FileView {
    path: root.cacheDir + "/api.json"
    watchChanges: true
    printErrors: false
    onFileChanged: cacheRefresh.restart()
  }

  Timer {
    id: cacheRefresh
    interval: 1500
    repeat: false
    onTriggered: {
      // Our own API fetch just rewrote api.json; that data is already shown.
      if (Date.now() - root.lastFetchMs < 3000) return
      root.runFetch("cache")
    }
  }

  // Keeps "resets in" honest while the popup is open.
  Timer {
    interval: 30000
    running: root.opened
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  onOpenedChanged: if (opened) {
    nowMs = Date.now()
    settingsOpen = false
    saveError = ""
    if (panelFlick) panelFlick.contentY = 0
    refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function toggleSettings() {
    settingsOpen = !settingsOpen
    if (panelFlick) panelFlick.contentY = 0
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refreshNow(); return "ok" }
    function settings(): void { root.open(); root.settingsOpen = true }
    function text(): string { return root.compactText }
  }

  // -------------------------------------------------------------------- bar

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    dimmed: !root.hasData
    active: root.alarming
    tooltipText: root.tooltipText
    fixedWidth: root.vertical ? -1 : Math.ceil(content.implicitWidth + button.scaledHorizontalMargin * 2)
    fixedHeight: root.vertical ? Math.ceil(content.implicitHeight + button.scaledVerticalPadding * 2) : -1

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton) root.refreshNow()
      else if (buttonCode === Qt.RightButton && root.rightClickCommand !== "" && root.bar) root.bar.run(root.rightClickCommand)
      else root.toggle()
    }

    Grid {
      id: content
      anchors.centerIn: parent
      columns: root.vertical ? 1 : 3
      rows: root.vertical ? 3 : 1
      columnSpacing: Style.space(6)
      rowSpacing: Style.space(3)
      verticalItemAlignment: Grid.AlignVCenter
      horizontalItemAlignment: Grid.AlignHCenter

      Text {
        textFormat: Text.PlainText
        text: root.icon
        visible: root.icon !== ""
        color: root.alarming ? root.stateColor("critical") : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.bar.iconFont
        renderType: Text.NativeRendering
      }

      Text {
        textFormat: Text.PlainText
        visible: root.barStyle !== "bars" && root.compactText !== ""
        text: root.compactText
        color: root.highest ? root.stateColor(root.highest.state) : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        renderType: Text.NativeRendering

        Behavior on color {
          ColorAnimation { duration: 160 }
        }
      }

      Column {
        visible: root.barStyle === "bars" && root.compactItems.length > 0
        spacing: Style.space(2)

        Repeater {
          model: root.barStyle === "bars" ? root.compactItems : []

          Item {
            id: miniMeter
            required property var modelData
            width: root.vertical ? Style.space(16) : Style.space(20)
            height: Style.space(3)

            Rectangle {
              anchors.fill: parent
              radius: height / 2
              color: root.track
            }

            Rectangle {
              width: Math.max(height, parent.width * Model.clamp(miniMeter.modelData.pct, 0, 100) / 100)
              height: parent.height
              radius: height / 2
              color: root.stateColor(miniMeter.modelData.state)

              Behavior on width {
                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
              }
            }
          }
        }
      }
    }
  }

  // ------------------------------------------------------------------ popup

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.settingsOpen && settingsView.editing
      onCloseRequested: root.settingsOpen ? root.toggleSettings() : root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "r" && !root.settingsOpen) root.refreshNow()
        else if (text === "s") root.toggleSettings()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: panelColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height

      Column {
        id: panelColumn
        width: panelFlick.width
        spacing: Style.space(14)

        PanelHero {
          width: parent.width
          title: "Claude Usage"
          meta: root.settingsOpen ? "Settings" : root.heroMeta
          detail: root.settingsOpen || !root.highest ? "" : Math.round(root.highest.pct) + "%"
          foreground: root.foreground
          fontFamily: root.fontFamily

          iconComponent: Component {
            Text {
              textFormat: Text.PlainText
              text: root.icon !== "" ? root.icon : "󰚩"
              color: root.alarming ? root.stateColor("critical") : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }

          trailingControl: Component {
            Row {
              spacing: Style.spacing.sm

              PanelActionButton {
                iconText: "󰑐"
                tooltipText: root.busy ? "Refreshing…" : "Refresh (r)"
                foreground: root.foreground
                fontFamily: root.fontFamily
                enabled: !root.busy
                visible: !root.settingsOpen
                onClicked: root.refreshNow()
              }

              PanelActionButton {
                iconText: root.settingsOpen ? "󰅖" : "󰒓"
                tooltipText: root.settingsOpen ? "Close settings (Esc)" : "Settings (s)"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.toggleSettings()
              }
            }
          }
        }

        PanelSeparator {
          foreground: root.foreground
        }

        SettingsView {
          id: settingsView
          visible: root.settingsOpen
          width: parent.width
          panel: root
        }

        Repeater {
          model: root.settingsOpen ? [] : root.allWindows

          LimitRow {
            required property var modelData
            width: panelColumn.width
            window: modelData
          }
        }

        Column {
          visible: !root.hasData && !root.settingsOpen
          width: parent.width
          spacing: Style.space(4)

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: root.statusText !== "" ? "No usage data" : "Fetching limits"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: root.statusText !== ""
              ? root.statusText
              : "Start Claude Code once so the OAuth token and the statusline cache exist."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        Text {
          textFormat: Text.PlainText
          visible: text !== "" && !root.settingsOpen
          width: parent.width
          text: Model.footerText(root.report, root.nowMs, root.statusText)
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
      }
    }
  }

  // One limit window: label and percentage, meter, reset countdown.
  component LimitRow: Column {
    id: limitRow
    property var window: null

    readonly property color valueColor: root.stateColor(window ? window.state : "normal")
    readonly property real thickness: Math.max(Style.space(4), Math.round(Style.spacing.controlHeight * 0.14))

    spacing: Style.space(6)

    Item {
      width: parent.width
      implicitHeight: Math.max(limitLabel.implicitHeight, limitValue.implicitHeight)

      Text {
        id: limitLabel
        textFormat: Text.PlainText
        text: limitRow.window ? limitRow.window.label : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
        anchors.left: parent.left
        anchors.right: limitValue.left
        anchors.rightMargin: Style.spacing.sm
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: limitValue
        textFormat: Text.PlainText
        text: limitRow.window ? Math.round(limitRow.window.pct) + "%" : "—"
        color: limitRow.valueColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    Item {
      width: parent.width
      implicitHeight: limitRow.thickness

      Rectangle {
        id: meterTrack
        anchors.fill: parent
        radius: height / 2
        color: root.track
      }

      Rectangle {
        anchors.left: meterTrack.left
        anchors.verticalCenter: meterTrack.verticalCenter
        height: meterTrack.height
        radius: meterTrack.radius
        width: Math.max(height, meterTrack.width * (limitRow.window ? limitRow.window.pct : 0) / 100)
        color: limitRow.valueColor

        Behavior on width {
          NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }
      }
    }

    Text {
      textFormat: Text.PlainText
      width: parent.width
      text: Model.resetText(limitRow.window, root.nowMs)
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }
}
