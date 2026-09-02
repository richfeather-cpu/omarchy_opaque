import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Logic.js" as Logic

Panel {
  id: root

  moduleName: "tomrplummer.omapaque"
  ipcTarget: "tomrplummer.omapaque"
  manageIpc: false

  property string themeName: ""
  property real themeActiveOpacity: 1
  property real themeInactiveOpacity: 1
  property int opacityPercent: 100
  property int pendingPercent: 100
  property bool applyQueued: false
  property bool initialized: false
  property bool awaitingThemeBaseline: false
  property bool cursorActive: false
  property string errorText: ""

  readonly property string themeNamePath: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme.name"
  readonly property string savedTheme: String(setting("theme", ""))
  readonly property real savedActiveOpacity: Number(setting("themeActiveOpacity", 1))
  readonly property real savedInactiveOpacity: Number(setting("themeInactiveOpacity", 1))
  readonly property int savedPercent: Logic.clampPercent(setting("opacityPercent", 100))
  readonly property string displayTheme: themeName === ""
    ? "CURRENT THEME"
    : themeName.replace(/-/g, " ").toUpperCase()

  function persistState() {
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry.theme = root.themeName
    entry.themeActiveOpacity = root.themeActiveOpacity
    entry.themeInactiveOpacity = root.themeInactiveOpacity
    entry.opacityPercent = root.opacityPercent

    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function readThemeName() {
    var next = String(themeFile.text() || "").trim()
    if (next === "") return

    var changed = root.themeName !== "" && root.themeName !== next
    root.themeName = next

    if (!root.initialized) {
      root.initialized = true
      if (root.savedTheme === next
          && isFinite(root.savedActiveOpacity)
          && isFinite(root.savedInactiveOpacity)) {
        root.themeActiveOpacity = root.savedActiveOpacity
        root.themeInactiveOpacity = root.savedInactiveOpacity
        root.opacityPercent = root.savedPercent
        root.requestApply(root.opacityPercent)
        return
      }
      root.scheduleBaselineRead(250)
      return
    }

    if (changed || root.savedTheme !== next) root.scheduleBaselineRead(2200)
  }

  function scheduleBaselineRead(delay) {
    root.awaitingThemeBaseline = true
    root.opacityPercent = 100
    baselineDelay.interval = delay
    baselineDelay.restart()
  }

  function readBaseline() {
    if (baselineProc.running) return
    root.errorText = ""
    baselineProc.command = [
      "hyprctl", "-j", "--batch",
      "getoption decoration:active_opacity ; getoption decoration:inactive_opacity"
    ]
    baselineProc.running = true
  }

  function acceptBaseline(raw) {
    var baseline = Logic.parseOpacityOptions(raw)
    if (!baseline) {
      root.awaitingThemeBaseline = false
      root.errorText = "Could not read Hyprland's opacity"
      return
    }

    root.themeActiveOpacity = baseline.active
    root.themeInactiveOpacity = baseline.inactive
    root.opacityPercent = 100
    root.awaitingThemeBaseline = false
    root.persistState()
  }

  function requestApply(percent) {
    root.pendingPercent = Logic.clampPercent(percent)
    if (evalProc.running) {
      root.applyQueued = true
      return
    }

    root.applyQueued = false
    evalProc.command = [
      "hyprctl", "eval",
      Logic.renderOpacityConfig(root.themeActiveOpacity, root.themeInactiveOpacity, root.pendingPercent)
    ]
    evalProc.running = true
  }

  function setOpacity(percent, commit) {
    root.opacityPercent = Logic.clampPercent(percent)
    root.requestApply(root.opacityPercent)
    if (commit) root.persistState()
  }

  function resetToTheme() {
    root.setOpacity(100, true)
  }

  function nudgeOpacity(delta) {
    root.cursorActive = true
    root.setOpacity(root.opacityPercent + delta, true)
  }

  function open() {
    root.controller.show()
    root.cursorActive = false
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened && !root.initialized) themeFile.reload()

  FileView {
    id: themeFile
    path: root.themeNamePath
    watchChanges: true
    printErrors: false
    onLoaded: root.readThemeName()
    onFileChanged: reload()
  }

  Timer {
    id: baselineDelay
    interval: 250
    onTriggered: root.readBaseline()
  }

  Process {
    id: baselineProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.acceptBaseline(text)
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var message = String(text || "").trim()
        if (message !== "") root.errorText = message
      }
    }
  }

  Process {
    id: evalProc
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var message = String(text || "").trim()
        root.errorText = message
      }
    }
    onExited: {
      if (!root.applyQueued) return
      root.applyQueued = false
      Qt.callLater(function() { root.requestApply(root.pendingPercent) })
    }
  }

  IpcHandler {
    target: root.moduleName

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function reset(): void { root.resetToTheme() }
    function set(percent: int): void { root.setOpacity(percent, true) }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "◐"
    active: root.opacityPercent < 100
    tooltipText: root.opacityPercent === 100
      ? "Window opacity: theme default"
      : "Window opacity: " + root.opacityPercent + "% of theme"
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton) root.resetToTheme()
      else root.toggle()
    }
    onWheelMoved: function(delta) { root.nudgeOpacity(delta > 0 ? 5 : -5) }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        root.cursorActive = true
        if (dx !== 0) root.nudgeOpacity(dx * 2)
      }
      onActivateRequested: root.resetToTheme()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, heroValue.implicitHeight)

          Text {
            id: heroIcon
            text: "◐"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: heroValue.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              width: parent.width
              text: "Window opacity"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              text: root.displayTheme
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
            }
          }

          Text {
            id: heroValue
            text: Math.round(opacitySlider.dragging ? opacitySlider.liveValue : root.opacityPercent) + "%"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.displayLarge
            font.bold: true
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        PanelSeparator {
          foreground: root.bar.foreground
        }

        Column {
          width: parent.width
          spacing: Style.space(7)

          PanelSectionHeader {
            text: "THEME OPACITY"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Text {
            width: parent.width
            text: "100% keeps the theme's opacity. Lower values add transparency."
            color: Qt.darker(root.bar.foreground, 1.25)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          CursorSurface {
            width: parent.width
            height: opacitySlider.implicitHeight + Style.spacing.controlGap
            hasCursor: root.cursorActive
            foreground: root.bar.foreground
            outline: true

            PanelSlider {
              id: opacitySlider
              bar: root.bar
              anchors.fill: parent
              anchors.leftMargin: Style.space(6)
              anchors.rightMargin: Style.space(6)
              minimum: 50
              maximum: 100
              step: 1
              value: root.opacityPercent
              integer: true
              tickCount: 6
              onMoved: function(value) { root.setOpacity(value, false) }
              onReleased: function(value) { root.setOpacity(value, true) }
              onRightClicked: root.resetToTheme()
            }

            HoverHandler {
              onHoveredChanged: if (hovered) root.cursorActive = true
            }
          }
        }

        Text {
          width: parent.width
          visible: root.awaitingThemeBaseline || root.errorText !== ""
          text: root.errorText !== "" ? root.errorText : "Reading the new theme's opacity…"
          color: root.errorText !== "" ? Color.urgent : Qt.darker(root.bar.foreground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}
