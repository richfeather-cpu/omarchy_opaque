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
  property real themeOpacityPercent: 100
  property real opacityPercent: 100
  property real pendingPercent: 100
  property bool customized: false
  property bool applyQueued: false
  property bool initialized: false
  property bool awaitingThemeBaseline: false
  property bool cursorActive: false
  property string errorText: ""
  property string cleanupAction: ""

  readonly property string themeNamePath: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme.name"
  readonly property string savedTheme: String(setting("theme", ""))
  readonly property string savedMode: String(setting("mode", ""))
  readonly property real savedThemeOpacity: Logic.clampPercent(setting("themeOpacityPercent", 100))
  readonly property real savedPercent: Logic.clampPercent(setting("opacityPercent", 100))
  readonly property bool savedCustomized: setting("customized", false) === true
  readonly property bool legacyState: settings && settings.themeActiveOpacity !== undefined
  readonly property string displayTheme: themeName === ""
    ? "CURRENT THEME"
    : themeName.replace(/-/g, " ").toUpperCase()

  function persistState() {
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry.theme = root.themeName
    entry.mode = "absolute"
    entry.themeOpacityPercent = root.themeOpacityPercent
    entry.opacityPercent = root.opacityPercent
    entry.customized = root.customized
    delete entry.themeActiveOpacity
    delete entry.themeInactiveOpacity

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
      if (root.savedMode === "absolute" && root.savedTheme === next) {
        root.themeOpacityPercent = root.savedThemeOpacity
        root.opacityPercent = root.savedPercent
        root.customized = root.savedCustomized
        if (root.customized) root.requestApply(root.opacityPercent)
        return
      }
      if (root.legacyState) {
        root.resetToTheme()
        return
      }
      root.scheduleBaselineRead(250)
      return
    }

    if (changed || root.savedTheme !== next) root.scheduleBaselineRead(2200)
  }

  function scheduleBaselineRead(delay) {
    root.awaitingThemeBaseline = true
    root.customized = false
    baselineDelay.interval = delay
    baselineDelay.restart()
  }

  function startCleanup(action) {
    if (cleanupProc.running || reloadProc.running) return
    root.cleanupAction = action
    cleanupProc.command = ["hyprctl", "eval", Logic.renderCleanup()]
    cleanupProc.running = true
  }

  function readBaseline() {
    if (baselineProc.running) return
    root.errorText = ""
    baselineProc.command = [
      "hyprctl", "-j", "--batch",
      "getoption decoration:active_opacity ; getprop tag:default-opacity opacity ; getprop tag:default-opacity opacity_override"
    ]
    baselineProc.running = true
  }

  function acceptBaseline(raw) {
    var baseline = Logic.parseThemeOpacity(raw)
    if (baseline === null) {
      root.awaitingThemeBaseline = false
      root.errorText = "Could not read Hyprland's opacity"
      return
    }

    root.themeOpacityPercent = baseline
    root.opacityPercent = baseline
    root.customized = false
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
      Logic.renderAbsoluteOpacity(root.pendingPercent)
    ]
    evalProc.running = true
  }

  function setOpacity(percent, commit) {
    root.opacityPercent = Logic.clampPercent(percent)
    root.customized = true
    root.requestApply(root.opacityPercent)
    if (!commit) return
    if (Math.abs(root.opacityPercent - root.themeOpacityPercent) < 0.01) root.resetToTheme()
    else root.persistState()
  }

  function resetToTheme() {
    if (root.awaitingThemeBaseline) return
    root.awaitingThemeBaseline = true
    root.customized = false
    root.errorText = ""
    root.startCleanup("reload")
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
    onTriggered: root.startCleanup("baseline")
  }

  Timer {
    id: postReloadDelay
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

  Process {
    id: cleanupProc
    onExited: {
      if (root.cleanupAction === "reload") reloadProc.running = true
      else root.readBaseline()
      root.cleanupAction = ""
    }
  }

  Process {
    id: reloadProc
    command: ["hyprctl", "reload"]
    onExited: postReloadDelay.restart()
  }

  IpcHandler {
    target: root.moduleName

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function reset(): void { root.resetToTheme() }
    function set(percent: real): void { root.setOpacity(percent, true) }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "◐"
    active: root.customized
    tooltipText: !root.customized
      ? "Window opacity: theme default"
      : "Window opacity: " + Logic.formatPercent(root.opacityPercent)
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton) root.resetToTheme()
      else root.toggle()
    }
    onWheelMoved: function(delta) { root.nudgeOpacity(delta > 0 ? 2.5 : -2.5) }
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
        if (dx !== 0) root.nudgeOpacity(dx)
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
            text: Logic.formatPercent(opacitySlider.dragging ? opacitySlider.liveValue : root.opacityPercent)
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
            text: "WINDOW OPACITY"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Text {
            width: parent.width
            text: "This is the exact compositor opacity. 100% is fully opaque."
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
              step: 0.5
              value: root.opacityPercent
              integer: false
              tickCount: 6
              onMoved: function(value) { root.setOpacity(value, false) }
              onReleased: function(value) { root.setOpacity(value, true) }
              onRightClicked: root.resetToTheme()
            }

            HoverHandler {
              onHoveredChanged: if (hovered) root.cursorActive = true
            }
          }

          Text {
            width: parent.width
            text: "Theme default: " + Logic.formatPercent(root.themeOpacityPercent)
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
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
