import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Logic.js" as Logic

Panel {
  id: root

  moduleName: "io.github.richfeather-cpu.omarchy-opaque"
  ipcTarget: "io.github.richfeather-cpu.omarchy-opaque"
  manageIpc: false

  property string themeName: ""
  // themeOpacityPercent is the theme's UNFOCUSED opacity (the slider's
  // baseline); focused/fullscreen theme values are passed through unchanged.
  property real themeOpacityPercent: 100
  property real themeActivePercent: 98.5
  property real themeFullscreenPercent: 100
  property real opacityPercent: 100
  // Second slider for the FOCUSED window. Until it is
  // moved it follows the theme's focused value, so behaviour is unchanged.
  property real focusedPercent: 98.5
  property bool focusedCustomized: false
  property bool reapplyFocusedAfterBaseline: false
  property real reapplyFocusedPercent: 98.5
  property real pendingPercent: 100
  property bool customized: false
  property bool applyQueued: false
  property bool initialized: false
  property bool awaitingThemeBaseline: false
  property bool syncingSettings: false
  property bool cursorActive: false
  property bool persistAcrossThemes: false
  property bool reapplyAfterBaseline: false
  property real reapplyPercent: 100
  property string focusSection: "opacity"
  // The host assigns `settings` after creation. If
  // the theme-name file loads first, the saved values look empty and the
  // widget would reset to the theme and overwrite them. Wait for settings.
  property bool themeReadPending: false
  property bool settingsWaitExpired: false
  property real wheelAccumulator: 0
  property int baselineRetryDelay: 1500
  property string errorText: ""
  property bool themeNameChangedOnDisk: false
  property bool defaultLookLoaded: false
  property bool defaultRulesLoaded: false
  property bool themeConfigLoaded: false
  property string defaultLookSource: ""
  property string defaultRulesSource: ""
  property string themeConfigSource: ""

  readonly property string themeNamePath: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme.name"
  readonly property string currentThemePath: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme"
  readonly property string omarchyPath: String(Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy")
  readonly property string defaultLookPath: omarchyPath + "/default/hypr/looknfeel.lua"
  readonly property string defaultRulesPath: omarchyPath + "/default/hypr/windows.lua"
  readonly property string themeConfigPath: currentThemePath + "/hyprland.lua"
  readonly property string luaModulePath: Quickshell.env("HOME")
    + "/.config/omarchy/plugins/" + moduleName + "/Omapaque.lua"
  readonly property string savedTheme: String(setting("theme", ""))
  readonly property string savedMode: String(setting("mode", ""))
  readonly property real savedThemeOpacity: Logic.clampPercent(setting("themeOpacityPercent", 100))
  readonly property real savedPercent: Logic.clampPercent(setting("opacityPercent", 100))
  readonly property bool savedCustomized: setting("customized", false) === true
  readonly property bool savedUnfocused: setting("target", "") === "unfocused"
  readonly property real savedThemeActive: Logic.clampPercent(setting("themeActivePercent", 98.5))
  readonly property real savedThemeFullscreen: Logic.clampPercent(setting("themeFullscreenPercent", 100))
  readonly property real savedFocusedPercent: Logic.clampPercent(setting("focusedPercent", 98.5))
  readonly property bool savedFocusedCustomized: setting("focusedCustomized", false) === true
  readonly property bool anyCustomized: customized || focusedCustomized
  readonly property bool savedPersistAcrossThemes: setting("persistAcrossThemes", false) === true
  readonly property bool legacyState: settings && settings.themeActiveOpacity !== undefined
  readonly property string displayTheme: themeName === ""
    ? "CURRENT THEME"
    : themeName.replace(/-/g, " ").toUpperCase()

  function persistState() {
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry.theme = root.themeName
    entry.mode = "absolute"
    entry.target = "unfocused"
    entry.themeOpacityPercent = root.themeOpacityPercent
    entry.themeActivePercent = root.themeActivePercent
    entry.themeFullscreenPercent = root.themeFullscreenPercent
    entry.opacityPercent = root.opacityPercent
    entry.customized = root.customized
    entry.focusedPercent = root.focusedPercent
    entry.focusedCustomized = root.focusedCustomized
    entry.persistAcrossThemes = root.persistAcrossThemes
    delete entry.themeActiveOpacity
    delete entry.themeInactiveOpacity

    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  // Inline settings are shared by every monitor, while these display values
  // are local properties. Copy each committed change into the other widgets.
  function syncStateFromSettings() {
    if (!root.initialized || root.syncingSettings || root.awaitingThemeBaseline) return
    if (root.savedMode !== "absolute" || root.savedTheme !== root.themeName || !root.savedUnfocused) return

    root.syncingSettings = true
    root.themeOpacityPercent = root.savedThemeOpacity
    root.themeActivePercent = root.savedThemeActive
    root.themeFullscreenPercent = root.savedThemeFullscreen
    root.opacityPercent = root.savedPercent
    root.customized = root.savedCustomized
    root.focusedPercent = root.savedFocusedPercent
    root.focusedCustomized = root.savedFocusedCustomized
    root.persistAcrossThemes = root.savedPersistAcrossThemes
    root.awaitingThemeBaseline = false
    root.errorText = ""
    baselineDelay.stop()
    baselineRetry.stop()
    root.syncingSettings = false
  }

  // Each destroyed copy starts the same guarded command. A process lock keeps
  // only one, and the delayed enabled-state check distinguishes plugin removal
  // from monitor removal, source reload, and shell restart.
  function cleanupAfterUnload() {
    Quickshell.execDetached([
      "bash", "-c", Logic.renderUnloadCleanup(),
      "omapaque-cleanup", root.moduleName,
      Logic.renderLuaCall(root.luaModulePath, "cleanup")
    ])
  }

  function readThemeName(fileChanged) {
    var next = String(themeFile.text() || "").trim()
    if (next === "") return

    if (!root.initialized && !root.settingsWaitExpired
        && (!root.settings || root.settings.id === undefined)) {
      root.themeReadPending = true
      settingsWait.restart()
      return
    }
    root.themeReadPending = false
    settingsWait.stop()

    var changed = root.themeName !== "" && root.themeName !== next
    root.themeName = next

    if (!root.initialized) {
      root.initialized = true
      root.persistAcrossThemes = root.savedPersistAcrossThemes
      if (root.savedMode === "absolute" && root.savedTheme === next && root.savedUnfocused) {
        root.themeOpacityPercent = root.savedThemeOpacity
        root.themeActivePercent = root.savedThemeActive
        root.themeFullscreenPercent = root.savedThemeFullscreen
        root.opacityPercent = root.savedPercent
        root.customized = root.savedCustomized
        root.focusedPercent = root.savedFocusedPercent
        root.focusedCustomized = root.savedFocusedCustomized
        if (root.customized || root.focusedCustomized) {
          root.requestApply(root.opacityPercent)
          return
        }
        // Recover from a shell exit that may have interrupted a drag before
        // its temporary compositor rule was committed to settings.
        root.scheduleBaselineRead(250)
        return
      }
      // Settings saved by the all-windows version: re-read the theme
      // baseline, then keep the chosen value for unfocused windows.
      if (root.savedMode === "absolute" && root.savedCustomized && !root.savedUnfocused) {
        root.opacityPercent = root.savedPercent
        root.customized = true
        root.scheduleBaselineRead(250, true)
        return
      }
      if (root.savedMode === "absolute" && root.savedPersistAcrossThemes
          && (root.savedCustomized || root.savedFocusedCustomized)) {
        root.opacityPercent = root.savedPercent
        root.customized = root.savedCustomized
        root.focusedPercent = root.savedFocusedPercent
        root.focusedCustomized = root.savedFocusedCustomized
        root.scheduleBaselineRead(250, true)
        return
      }
      if (root.legacyState) {
        root.resetToTheme()
        return
      }
      root.scheduleBaselineRead(250)
      return
    }

    if (Logic.shouldRefreshTheme(changed, root.savedTheme, next, fileChanged))
      root.scheduleBaselineRead(2200, Logic.shouldCarryAcrossTheme(
        root.persistAcrossThemes, root.anyCustomized,
        root.reapplyAfterBaseline || root.reapplyFocusedAfterBaseline))
  }

  function scheduleBaselineRead(delay, reapplyCustom) {
    root.cancelPendingApply()
    root.themeConfigLoaded = false
    themeConfigFile.reload()
    if (reapplyCustom === true && !root.reapplyAfterBaseline && !root.reapplyFocusedAfterBaseline) {
      if (root.customized) {
        root.reapplyPercent = root.opacityPercent
        root.reapplyAfterBaseline = true
      }
      if (root.focusedCustomized) {
        root.reapplyFocusedPercent = root.focusedPercent
        root.reapplyFocusedAfterBaseline = true
      }
    }
    root.awaitingThemeBaseline = true
    root.customized = false
    root.focusedCustomized = false
    root.baselineRetryDelay = 1500
    baselineRetry.stop()
    baselineDelay.interval = delay
    baselineDelay.restart()
  }

  function scheduleBaselineRetry() {
    baselineRetry.interval = root.baselineRetryDelay
    baselineRetry.restart()
    root.baselineRetryDelay = Logic.nextRetryDelay(root.baselineRetryDelay)
  }

  function clearOverrideBeforeBaseline() {
    if (cleanupProc.running || reloadProc.running) return
    cleanupProc.command = [
      "hyprctl", "eval", Logic.renderLuaCall(root.luaModulePath, "cleanup")
    ]
    cleanupProc.running = true
  }

  function readBaseline() {
    if (!root.defaultLookLoaded || !root.defaultRulesLoaded || !root.themeConfigLoaded) {
      root.errorText = ""
      root.scheduleBaselineRetry()
      return
    }
    root.acceptBaseline(Logic.parseThemeUnfocusedSettings(
      root.defaultLookSource, root.defaultRulesSource, root.themeConfigSource))
  }

  function acceptBaseline(baseline) {
    if (baseline === null) {
      root.errorText = "Could not read the theme opacity settings"
      root.scheduleBaselineRetry()
      return
    }

    baselineRetry.stop()
    root.baselineRetryDelay = 1500
    root.themeOpacityPercent = baseline.inactive
    root.themeActivePercent = baseline.active
    root.themeFullscreenPercent = baseline.fullscreen
    if (root.reapplyAfterBaseline) {
      root.opacityPercent = root.reapplyPercent
      root.customized = true
      root.reapplyAfterBaseline = false
    } else {
      root.opacityPercent = baseline.inactive
      root.customized = false
    }
    if (root.reapplyFocusedAfterBaseline) {
      root.focusedPercent = root.reapplyFocusedPercent
      root.focusedCustomized = true
      root.reapplyFocusedAfterBaseline = false
    } else {
      root.focusedPercent = baseline.active
      root.focusedCustomized = false
    }
    if (root.customized || root.focusedCustomized) root.requestApply(root.opacityPercent)
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
    // Values not customized fall back to the theme (focused/unfocused) and
    // to Omarchy's browser defaults (focused 100%, unfocused 98.5%).
    evalProc.command = [
      "hyprctl", "eval",
      Logic.renderLuaApply(root.luaModulePath, Logic.applyValues(
        root.customized, root.opacityPercent, root.themeOpacityPercent,
        root.focusedCustomized, root.focusedPercent, root.themeActivePercent,
        root.themeFullscreenPercent))
    ]
    evalProc.running = true
  }

  function cancelPendingApply() {
    root.applyQueued = false
    if (evalProc.running) evalProc.running = false
  }

  function setOpacity(percent, commit) {
    if (!Logic.canSetOpacity(root.awaitingThemeBaseline)) return
    root.opacityPercent = Logic.clampPercent(percent)
    root.customized = true
    root.requestApply(root.opacityPercent)
    if (!commit) return
    root.persistState()
  }

  function setFocusedOpacity(percent, commit) {
    if (!Logic.canSetOpacity(root.awaitingThemeBaseline)) return
    root.focusedPercent = Logic.clampPercent(percent)
    root.focusedCustomized = true
    root.requestApply(root.opacityPercent)
    if (!commit) return
    root.persistState()
  }

  // Per-slider resets. When the other slider is also at its theme default
  // this is a full reset (drop the compositor rule, re-read the theme).
  function resetUnfocused() {
    if (root.awaitingThemeBaseline) return
    if (!root.focusedCustomized) { root.resetToTheme(); return }
    root.customized = false
    root.opacityPercent = root.themeOpacityPercent
    root.requestApply(root.opacityPercent)
    root.persistState()
  }

  function resetFocused() {
    if (root.awaitingThemeBaseline) return
    if (!root.customized) { root.resetToTheme(); return }
    root.focusedCustomized = false
    root.focusedPercent = root.themeActivePercent
    root.requestApply(root.opacityPercent)
    root.persistState()
  }

  function nudgeFocused(delta) {
    if (!Logic.canSetOpacity(root.awaitingThemeBaseline)) return
    root.cursorActive = true
    root.focusSection = "focused"
    root.setFocusedOpacity(root.focusedPercent + delta, true)
  }

  function resetToTheme() {
    if (root.awaitingThemeBaseline) return
    root.cancelPendingApply()
    root.themeConfigLoaded = false
    themeConfigFile.reload()
    root.reapplyAfterBaseline = false
    root.reapplyFocusedAfterBaseline = false
    root.awaitingThemeBaseline = true
    root.customized = false
    root.focusedCustomized = false
    root.errorText = ""
    root.clearOverrideBeforeBaseline()
  }

  function nudgeOpacity(delta) {
    if (!Logic.canSetOpacity(root.awaitingThemeBaseline)) return
    root.cursorActive = true
    root.focusSection = "opacity"
    root.setOpacity(root.opacityPercent + delta, true)
  }

  function setPersistAcrossThemes(enabled) {
    root.persistAcrossThemes = enabled === true
    if (!root.persistAcrossThemes) {
      root.reapplyAfterBaseline = false
      root.reapplyFocusedAfterBaseline = false
    }
    root.persistState()
  }

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: {
    if (opened) {
      root.cursorActive = false
      root.focusSection = "opacity"
      if (!root.initialized) themeFile.reload()
    }
  }
  onSettingsChanged: {
    if (root.themeReadPending && !root.initialized) {
      Qt.callLater(function() { root.readThemeName(false) })
      return
    }
    if (root.initialized && !root.syncingSettings)
      Qt.callLater(root.syncStateFromSettings)
  }
  Component.onDestruction: root.cleanupAfterUnload()

  FileView {
    id: themeFile
    path: root.themeNamePath
    watchChanges: true
    printErrors: false
    onLoaded: {
      var changed = root.themeNameChangedOnDisk
      root.themeNameChangedOnDisk = false
      root.readThemeName(changed)
    }
    onFileChanged: {
      root.themeNameChangedOnDisk = true
      reload()
    }
  }

  FileView {
    id: defaultLookFile
    path: root.defaultLookPath
    watchChanges: true
    printErrors: false
    onLoaded: {
      root.defaultLookSource = String(text() || "")
      root.defaultLookLoaded = true
    }
    onLoadFailed: {
      root.defaultLookSource = ""
      root.defaultLookLoaded = true
    }
    onFileChanged: {
      root.defaultLookLoaded = false
      reload()
    }
  }

  FileView {
    id: defaultRulesFile
    path: root.defaultRulesPath
    watchChanges: true
    printErrors: false
    onLoaded: {
      root.defaultRulesSource = String(text() || "")
      root.defaultRulesLoaded = true
    }
    onLoadFailed: {
      root.defaultRulesSource = ""
      root.defaultRulesLoaded = true
    }
    onFileChanged: {
      root.defaultRulesLoaded = false
      reload()
    }
  }

  FileView {
    id: themeConfigFile
    path: root.themeConfigPath
    watchChanges: false
    printErrors: false
    onLoaded: {
      root.themeConfigSource = String(text() || "")
      root.themeConfigLoaded = true
    }
    onLoadFailed: {
      root.themeConfigSource = ""
      root.themeConfigLoaded = true
    }
  }

  Timer {
    id: settingsWait
    interval: 1500
    onTriggered: {
      root.settingsWaitExpired = true
      if (root.themeReadPending) root.readThemeName(false)
    }
  }

  Timer {
    id: baselineDelay
    interval: 250
    onTriggered: root.clearOverrideBeforeBaseline()
  }

  Timer {
    id: postReloadDelay
    interval: 250
    onTriggered: root.readBaseline()
  }

  Timer {
    id: baselineRetry
    interval: 1500
    onTriggered: root.readBaseline()
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
    onExited: reloadProc.running = true
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
    function setFocused(percent: real): void { root.setFocusedOpacity(percent, true) }
    function resetUnfocused(): void { root.resetUnfocused() }
    function resetFocused(): void { root.resetFocused() }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󱡓"
    tooltipText: "Focused: " + (root.focusedCustomized ? Logic.formatPercent(root.focusedPercent) : "theme default")
      + " · Unfocused: " + (root.customized ? Logic.formatPercent(root.opacityPercent) : "theme default")
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton) root.resetToTheme()
      else root.toggle()
    }
    onWheelMoved: function(delta) {
      var wheel = Util.wheelSteps(root.wheelAccumulator, delta)
      root.wheelAccumulator = wheel.remainder
      if (wheel.steps === 0) return
      root.nudgeOpacity(wheel.steps * Logic.wheelStep(root.opacityPercent, wheel.steps))
    }
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
        if (dy !== 0) {
          var order = ["focused", "opacity", "persistence"]
          var index = Math.max(0, order.indexOf(root.focusSection))
          root.focusSection = order[Math.max(0, Math.min(order.length - 1, index + (dy > 0 ? 1 : -1)))]
          return
        }
        if (dx !== 0 && root.focusSection === "opacity") root.nudgeOpacity(dx)
        if (dx !== 0 && root.focusSection === "focused") root.nudgeFocused(dx)
      }
      onActivateRequested: {
        if (root.focusSection === "persistence")
          root.setPersistAcrossThemes(!root.persistAcrossThemes)
        else if (root.focusSection === "focused")
          root.resetFocused()
        else
          root.resetUnfocused()
      }
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
            text: "󱡓"
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

          Column {
            id: heroValue
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              anchors.right: parent.right
              text: "F " + Logic.formatPercent(focusedSlider.dragging ? focusedSlider.liveValue : root.focusedPercent)
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              anchors.right: parent.right
              text: "U " + Logic.formatPercent(opacitySlider.dragging ? opacitySlider.liveValue : root.opacityPercent)
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }
          }
        }

        PanelSeparator {
          foreground: root.bar.foreground
        }

        // FOCUSED WINDOW slider + presets (1/4, 1/2, Full,
        // Theme). Presets use the same setter as the slider's release, so
        // the slider follows and the value is committed to settings.
        // Right-click the slider or press Theme to reset just this slider.
        Column {
          width: parent.width
          spacing: Style.space(7)

          Item {
            width: parent.width
            implicitHeight: focusedSliderHeader.implicitHeight

            PanelSectionHeader {
              id: focusedSliderHeader
              anchors.left: parent.left
              text: "FOCUSED WINDOW"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
            }

            Text {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: (root.focusedCustomized ? "" : "theme · ") + Logic.formatPercent(focusedSlider.dragging ? focusedSlider.liveValue : root.focusedPercent)
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }

          CursorSurface {
            width: parent.width
            height: focusedSlider.implicitHeight + Style.spacing.controlGap
            hasCursor: root.cursorActive && root.focusSection === "focused"
            foreground: root.bar.foreground
            outline: true

            PanelSlider {
              id: focusedSlider
              bar: root.bar
              anchors.fill: parent
              anchors.leftMargin: Style.space(6)
              anchors.rightMargin: Style.space(6)
              minimum: 1
              maximum: 100
              step: 0.5
              value: root.focusedPercent
              enabled: !root.awaitingThemeBaseline
              integer: false
              tickCount: 5
              onMoved: function(value) { root.setFocusedOpacity(value, false) }
              onReleased: function(value) { root.setFocusedOpacity(value, true) }
              onRightClicked: root.resetFocused()
            }

            HoverHandler {
              onHoveredChanged: if (hovered) {
                root.cursorActive = true
                root.focusSection = "focused"
              }
            }
          }

          Row {
            id: focusedSliderPresets
            width: parent.width
            spacing: Style.spacing.xs

            readonly property var presets: [
              { label: "1/4", percent: 25 },
              { label: "1/2", percent: 50 },
              { label: "Full", percent: 100 },
              { label: "Theme", percent: -1 }
            ]
            readonly property real cellWidth: (width - spacing * (presets.length - 1)) / presets.length

            Repeater {
              model: focusedSliderPresets.presets

              Button {
                required property var modelData

                width: focusedSliderPresets.cellWidth
                text: modelData.label
                fontSize: Style.font.caption
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                bordered: true
                enabled: !root.awaitingThemeBaseline
                active: modelData.percent < 0
                  ? !root.focusedCustomized
                  : root.focusedCustomized && Math.abs(root.focusedPercent - modelData.percent) < 0.25
                onClicked: {
                  root.cursorActive = true
                  root.focusSection = "focused"
                  if (modelData.percent < 0) root.resetFocused()
                  else root.setFocusedOpacity(modelData.percent, true)
                }
              }
            }
          }

          Text {
            width: parent.width
            text: "Theme default: " + Logic.formatPercent(root.themeActivePercent) + " (browsers 100%)"
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        PanelSeparator {
          foreground: root.bar.foreground
        }

        // UNFOCUSED WINDOWS slider + presets (1/4, 1/2, Full,
        // Theme). Presets use the same setter as the slider's release, so
        // the slider follows and the value is committed to settings.
        // Right-click the slider or press Theme to reset just this slider.
        Column {
          width: parent.width
          spacing: Style.space(7)

          Item {
            width: parent.width
            implicitHeight: opacitySliderHeader.implicitHeight

            PanelSectionHeader {
              id: opacitySliderHeader
              anchors.left: parent.left
              text: "UNFOCUSED WINDOWS"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
            }

            Text {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: (root.customized ? "" : "theme · ") + Logic.formatPercent(opacitySlider.dragging ? opacitySlider.liveValue : root.opacityPercent)
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }

          CursorSurface {
            width: parent.width
            height: opacitySlider.implicitHeight + Style.spacing.controlGap
            hasCursor: root.cursorActive && root.focusSection === "opacity"
            foreground: root.bar.foreground
            outline: true

            PanelSlider {
              id: opacitySlider
              bar: root.bar
              anchors.fill: parent
              anchors.leftMargin: Style.space(6)
              anchors.rightMargin: Style.space(6)
              minimum: 1
              maximum: 100
              step: 0.5
              value: root.opacityPercent
              enabled: !root.awaitingThemeBaseline
              integer: false
              tickCount: 5
              onMoved: function(value) { root.setOpacity(value, false) }
              onReleased: function(value) { root.setOpacity(value, true) }
              onRightClicked: root.resetUnfocused()
            }

            HoverHandler {
              onHoveredChanged: if (hovered) {
                root.cursorActive = true
                root.focusSection = "opacity"
              }
            }
          }

          Row {
            id: opacitySliderPresets
            width: parent.width
            spacing: Style.spacing.xs

            readonly property var presets: [
              { label: "1/4", percent: 25 },
              { label: "1/2", percent: 50 },
              { label: "Full", percent: 100 },
              { label: "Theme", percent: -1 }
            ]
            readonly property real cellWidth: (width - spacing * (presets.length - 1)) / presets.length

            Repeater {
              model: opacitySliderPresets.presets

              Button {
                required property var modelData

                width: opacitySliderPresets.cellWidth
                text: modelData.label
                fontSize: Style.font.caption
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                bordered: true
                enabled: !root.awaitingThemeBaseline
                active: modelData.percent < 0
                  ? !root.customized
                  : root.customized && Math.abs(root.opacityPercent - modelData.percent) < 0.25
                onClicked: {
                  root.cursorActive = true
                  root.focusSection = "opacity"
                  if (modelData.percent < 0) root.resetUnfocused()
                  else root.setOpacity(modelData.percent, true)
                }
              }
            }
          }

          Text {
            width: parent.width
            text: "Theme default: " + Logic.formatPercent(root.themeOpacityPercent)
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        Text {
          width: parent.width
          visible: root.awaitingThemeBaseline || root.errorText !== ""
          text: root.errorText !== "" ? root.errorText : "Reading the theme opacity…"
          color: root.errorText !== "" ? root.bar.urgent : Qt.darker(root.bar.foreground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        PanelSeparator {
          foreground: root.bar.foreground
        }

        // Persistence toggle. Same kit pieces as Ui/Toggle
        // (BorderSurface row + ToggleSwitch, same hover/cursor/focus styling),
        // inlined so the row can show an On/Off word and tint the switch with
        // the theme accent when checked. The stock Toggle has no state text and
        // draws "checked" in the plain foreground, so the state was hard to read.
        Column {
          width: parent.width
          spacing: Style.space(7)

          BorderSurface {
            id: persistToggle
            width: parent.width

            property string label: "Keep across themes"
            property bool checked: root.persistAcrossThemes
            property bool hasCursor: root.cursorActive && root.focusSection === "persistence"
            property color foreground: root.bar.foreground
            property color accent: Color.accent
            property string fontFamily: root.bar.fontFamily
            readonly property color mutedForeground: Qt.darker(foreground, 1.4)

            signal clicked()
            signal hovered(bool isHovered)

            onHovered: function(isHovered) {
              if (!isHovered) return
              root.cursorActive = true
              root.focusSection = "persistence"
            }
            onClicked: root.setPersistAcrossThemes(!root.persistAcrossThemes)

            activeFocusOnTab: true
            Keys.onReturnPressed: persistToggle.clicked()
            Keys.onEnterPressed: persistToggle.clicked()
            Keys.onSpacePressed: persistToggle.clicked()

            implicitHeight: Math.max(54, persistRow.implicitHeight + Style.spacing.huge)
            radius: Style.cornerRadius

            readonly property bool _hot: hasCursor || persistMouse.containsMouse
            color: Style.controlFill(activeFocus, _hot, foreground, accent)
            borderSpec: Border.controlSpec(activeFocus ? "focus" : (_hot ? "hover-cursor" : "normal"), foreground, accent)

            Behavior on color { ColorAnimation { duration: 100 } }

            Row {
              id: persistRow
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: persistToggle.borderLeft + Style.spacing.rowPaddingX
              anchors.rightMargin: persistToggle.borderRight + Style.spacing.rowPaddingX
              spacing: Style.spacing.rowPaddingX

              Text {
                width: parent.width - persistState.width - persistSwitch.width - parent.spacing * 2
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: persistToggle.label
                color: persistToggle.foreground
                font.family: persistToggle.fontFamily
                font.pixelSize: Style.font.subtitle
                font.bold: true
                wrapMode: Text.WordWrap
              }

              // Fixed to the wider word so the switch does not shift on toggle.
              Text {
                id: persistState
                width: Math.ceil(persistStateMetrics.advanceWidth)
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                textFormat: Text.PlainText
                text: persistToggle.checked ? "On" : "Off"
                color: persistToggle.checked ? persistToggle.accent : persistToggle.mutedForeground
                font.family: persistToggle.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 0.6

                Behavior on color { ColorAnimation { duration: 120 } }

                TextMetrics {
                  id: persistStateMetrics
                  font: persistState.font
                  text: "Off"
                }
              }

              // Presentation only; the row owns the click. Same geometry as
              // Ui/ToggleSwitch, drawn here because that switch takes its
              // "checked" colour from the theme's selected-color (fixed on
              // some themes), which ignores the accent. Checked: accent
              // track tint, border and knob. Unchecked: muted foreground.
              Rectangle {
                id: persistSwitch
                readonly property int trackHeight: Math.max(22, Math.round(Style.spacing.controlHeight * 0.55))
                readonly property int knobSize: Math.max(6, Math.round(trackHeight * 0.72))
                readonly property int knobInset: Math.max(1, Math.round((trackHeight - knobSize) / 2))
                readonly property bool rounded: Style.cornerRadius > 0

                width: Math.round(trackHeight * 1.9)
                height: trackHeight
                anchors.verticalCenter: parent.verticalCenter
                radius: rounded ? height / 2 : 0
                color: persistToggle.checked
                  ? Util.alpha(persistToggle.accent, 0.25)
                  : Util.alpha(persistToggle.mutedForeground, 0.06)
                border.width: 1
                border.color: persistToggle.checked
                  ? persistToggle.accent
                  : Util.alpha(persistToggle.mutedForeground, 0.45)

                Behavior on color { ColorAnimation { duration: 120 } }
                Behavior on border.color { ColorAnimation { duration: 120 } }

                Rectangle {
                  width: persistSwitch.knobSize
                  height: persistSwitch.knobSize
                  radius: persistSwitch.rounded ? height / 2 : 0
                  x: persistToggle.checked ? persistSwitch.width - width - persistSwitch.knobInset : persistSwitch.knobInset
                  anchors.verticalCenter: parent.verticalCenter
                  color: persistToggle.checked ? persistToggle.accent : Qt.darker(persistToggle.foreground, 1.6)

                  Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                  Behavior on color { ColorAnimation { duration: 120 } }
                }
              }
            }

            MouseArea {
              id: persistMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: persistToggle.clicked()
            }

            HoverHandler {
              onHoveredChanged: persistToggle.hovered(hovered)
            }
          }

          Text {
            width: parent.width
            text: root.persistAcrossThemes
              ? "On: your values stay when you switch themes."
              : "Off: each theme sets its own opacity."
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }
}
