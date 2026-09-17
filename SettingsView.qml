import QtQuick
import qs.Commons
import qs.Ui

// Graphical settings for the Claude usage widget. Every control binds to the
// live value the panel reads from shell.json and writes back through
// panel.saveSetting(), so the bar updates the moment a control changes and
// the form never holds state of its own.
Column {
  id: view

  property var panel: null

  readonly property color foreground: panel ? panel.foreground : Color.foreground
  readonly property color dim: panel ? panel.dim : Qt.darker(Color.foreground, 1.55)
  readonly property string fontFamily: panel ? panel.fontFamily : Style.font.family

  // While one of these owns the keyboard the panel's key catcher stands back.
  readonly property bool editing: intervalDropdown.popupOpen
    || iconRow.editing || warningRow.editing || criticalRow.editing
    || rightClickRow.editing || commandRow.editing

  spacing: Style.space(12)

  function save(key, value) {
    if (panel) panel.saveSetting(key, value)
  }

  // ------------------------------------------------------------------- bar

  PanelSectionHeader {
    text: "Bar"
    foreground: view.foreground
    fontFamily: view.fontFamily
  }

  ChoiceRow {
    width: parent.width
    label: "Shows"
    options: [
      { value: "highest", label: "Highest" },
      { value: "all", label: "All" },
      { value: "icon", label: "Icon only" }
    ]
    value: view.panel ? view.panel.barMode : "highest"
    onChanged: function(v) { view.save("barMode", v) }
  }

  ChoiceRow {
    width: parent.width
    label: "Style"
    options: [
      { value: "text", label: "Text" },
      { value: "bars", label: "Bars" }
    ]
    value: view.panel ? view.panel.barStyle : "text"
    onChanged: function(v) { view.save("barStyle", v) }
  }

  PanelSectionHeader {
    text: "Windows in bar"
    foreground: view.foreground
    fontFamily: view.fontFamily
  }

  Toggle {
    width: parent.width
    label: "Session (5h)"
    description: "The rolling five-hour window."
    foreground: view.foreground
    fontFamily: view.fontFamily
    checked: view.panel ? view.panel.showSession : true
    onClicked: view.save("showSession", !checked)
  }

  Toggle {
    width: parent.width
    label: "Weekly (all models)"
    description: "The seven-day window across every model."
    foreground: view.foreground
    fontFamily: view.fontFamily
    checked: view.panel ? view.panel.showWeekly : true
    onClicked: view.save("showWeekly", !checked)
  }

  Toggle {
    width: parent.width
    label: "Weekly per model"
    description: "Model-scoped seven-day windows, e.g. Fable."
    foreground: view.foreground
    fontFamily: view.fontFamily
    checked: view.panel ? view.panel.showScoped : true
    onClicked: view.save("showScoped", !checked)
  }

  // ------------------------------------------------------------ thresholds

  PanelSectionHeader {
    text: "Thresholds"
    foreground: view.foreground
    fontFamily: view.fontFamily
  }

  SliderRow {
    width: parent.width
    label: "Warning from"
    value: view.panel ? view.panel.warnPercent : 70
    onCommitted: function(v) { view.save("warnPercent", v) }
  }

  SliderRow {
    width: parent.width
    label: "Critical from"
    value: view.panel ? view.panel.criticalPercent : 90
    onCommitted: function(v) { view.save("criticalPercent", v) }
  }

  // --------------------------------------------------------------- refresh

  PanelSectionHeader {
    text: "Refresh"
    foreground: view.foreground
    fontFamily: view.fontFamily
  }

  Dropdown {
    id: intervalDropdown
    width: Style.spacing.dropdownWidth
    label: "Interval"
    fontFamily: view.fontFamily
    options: [
      { value: "30", label: "30 seconds" },
      { value: "60", label: "1 minute" },
      { value: "120", label: "2 minutes" },
      { value: "300", label: "5 minutes" },
      { value: "900", label: "15 minutes" },
      { value: "1800", label: "30 minutes" }
    ]
    value: view.panel ? String(view.panel.refreshIntervalSec) : "120"
    onChanged: function(v) { view.save("refreshIntervalSec", parseInt(v, 10)) }
  }

  // ------------------------------------------------------------ appearance

  PanelSectionHeader {
    text: "Appearance"
    foreground: view.foreground
    fontFamily: view.fontFamily
  }

  TextRow {
    id: iconRow
    width: parent.width
    label: "Bar icon (Nerd Font glyph, empty hides it)"
    current: view.panel ? view.panel.icon : ""
    onCommitted: function(v) { view.save("icon", v) }
  }

  TextRow {
    id: warningRow
    width: parent.width
    label: "Warning colour (hex, empty keeps the theme foreground)"
    placeholder: "#f67400"
    current: view.panel ? view.panel.warningColor : ""
    onCommitted: function(v) { view.save("warningColor", v) }
  }

  TextRow {
    id: criticalRow
    width: parent.width
    label: "Critical colour (hex, empty uses the theme's urgent colour)"
    placeholder: "theme urgent"
    current: view.panel ? view.panel.criticalColor : ""
    onCommitted: function(v) { view.save("criticalColor", v) }
  }

  // --------------------------------------------------------------- actions

  PanelSectionHeader {
    text: "Actions"
    foreground: view.foreground
    fontFamily: view.fontFamily
  }

  TextRow {
    id: rightClickRow
    width: parent.width
    label: "Right-click command"
    placeholder: "omarchy-launch-or-focus-tui claude"
    current: view.panel ? view.panel.rightClickCommand : ""
    onCommitted: function(v) { view.save("onRightClick", v) }
  }

  TextRow {
    id: commandRow
    width: parent.width
    label: "claude-usage script (empty runs the bundled copy)"
    placeholder: "~/.local/bin/claude-usage"
    current: view.panel ? view.panel.commandSetting : ""
    onCommitted: function(v) { view.save("command", v) }
  }

  Text {
    textFormat: Text.PlainText
    visible: view.panel && view.panel.saveError !== ""
    width: parent.width
    text: view.panel ? view.panel.saveError : ""
    color: view.panel ? view.panel.urgent : Color.urgent
    font.family: view.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  Row {
    spacing: Style.spacing.controlGap
    anchors.right: parent.right

    Button {
      text: "Reset to defaults"
      bordered: true
      foreground: view.foreground
      fontFamily: view.fontFamily
      onClicked: if (view.panel) view.panel.resetSettings()
    }

    Button {
      text: "Done"
      bordered: true
      selected: true
      foreground: view.foreground
      fontFamily: view.fontFamily
      onClicked: if (view.panel) view.panel.settingsOpen = false
    }
  }

  // ------------------------------------------------------------ components

  // Label on the left, mutually exclusive chips on the right.
  component ChoiceRow: Item {
    id: choiceRow
    property string label: ""
    property var options: []
    property string value: ""
    signal changed(string value)

    implicitHeight: Math.max(choiceLabel.implicitHeight, choiceGroup.implicitHeight)

    Text {
      id: choiceLabel
      textFormat: Text.PlainText
      text: choiceRow.label
      color: view.foreground
      font.family: view.fontFamily
      font.pixelSize: Style.font.body
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
    }

    ButtonGroup {
      id: choiceGroup
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      options: choiceRow.options
      value: choiceRow.value
      foreground: view.foreground
      fontFamily: view.fontFamily
      focusable: false
      onChanged: function(v) { choiceRow.changed(v) }
    }
  }

  // Percent slider with its value next to the label; saves on release so a
  // drag does not write shell.json on every pixel.
  component SliderRow: Column {
    id: sliderRow
    property string label: ""
    property int value: 0
    signal committed(int value)

    spacing: Style.space(6)

    Item {
      width: parent.width
      implicitHeight: sliderLabel.implicitHeight

      Text {
        id: sliderLabel
        textFormat: Text.PlainText
        text: sliderRow.label
        color: view.foreground
        font.family: view.fontFamily
        font.pixelSize: Style.font.body
        anchors.left: parent.left
      }

      Text {
        textFormat: Text.PlainText
        text: Math.round(slider.dragging ? slider.liveValue : sliderRow.value) + "%"
        color: view.foreground
        font.family: view.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        anchors.right: parent.right
      }
    }

    PanelSlider {
      id: slider
      width: parent.width
      bar: view.panel ? view.panel.bar : null
      minimum: 0
      maximum: 100
      step: 5
      integer: true
      value: sliderRow.value
      onReleased: function(v) { sliderRow.committed(Math.round(v)) }
    }
  }

  // Caption plus a text field. The field mirrors the stored value until the
  // user starts typing, then hands the text back on Enter or focus loss.
  component TextRow: Column {
    id: textRow
    property string label: ""
    property string placeholder: ""
    property string current: ""
    readonly property bool editing: field.activeFocus
    signal committed(string value)

    spacing: Style.space(6)

    onCurrentChanged: if (!field.activeFocus) field.text = current
    Component.onCompleted: field.text = current

    Text {
      textFormat: Text.PlainText
      width: parent.width
      text: textRow.label
      color: view.dim
      font.family: view.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }

    TextField {
      id: field
      width: parent.width
      placeholderText: textRow.placeholder
      foreground: view.foreground
      font.family: view.fontFamily
      font.pixelSize: Style.font.body
      onEditingFinished: {
        if (text !== textRow.current) textRow.committed(text)
      }
      Keys.onEscapePressed: function(event) {
        text = textRow.current
        focus = false
        event.accepted = true
      }
    }
  }
}
