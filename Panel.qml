import QtQuick
import QtQuick.Controls as QQC
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The clock's calendar popup: a month grid with ISO week numbers, built to
// sit beside the weather panel. The header doubles as a title bar with a
// gear that swaps the whole body between the calendar and a settings sheet,
// so everything the widget knows how to display is reachable without editing
// shell.json by hand.
//
// The grid is a read-out rather than a picker: today is the only marked
// day, and the only thing that moves is which month is on screen —
// chevrons, the scroll wheel, and the arrow keys all step it.
//
// BarWidget.qml owns the bar label and hands this panel the button to
// anchor against.
Panel {
  id: root
  moduleName: "omarchy.clock"
  ipcTarget: "omarchy.clock"
  manageIpc: false

  property var anchorItem: null

  // The bar tracks the widget mounted in its slot — BarWidget.qml — not this
  // nested panel. Everything the bar identifies a panel by has to be that
  // widget: the popout coordinator (and with it the open-panel dot under the
  // pill) compares against `slot.activeItem`, and switchPanelFrom looks the
  // slot up the same way.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // ---- Today. SystemClock keeps this honest across midnight so the
  //      highlight rolls over without the panel being reopened.
  property date today: new Date()
  readonly property string todayKey: Model.keyForDate(today)

  // The month on screen. Stepping moves this and nothing else: the grid is
  // a read-out, not a picker, so there is no per-day cursor to keep in sync.
  property int viewYear: today.getFullYear()
  property int viewMonth: today.getMonth()

  readonly property date viewDate: new Date(viewYear, viewMonth, 1)
  readonly property bool viewingCurrentMonth: viewYear === today.getFullYear() && viewMonth === today.getMonth()

  // Pinned to today, not to the month being browsed — stepping through the
  // calendar does not change how much of the year is gone.
  readonly property real yearDone: Model.yearProgress(today.getFullYear(), today.getMonth(), today.getDate())
  readonly property int yearDonePercent: Model.yearProgressPercent(today.getFullYear(), today.getMonth(), today.getDate())

  // Memento mori, for anyone who goes looking: double-tapping the year bar
  // asks for a birth year and a life expectancy, and a second bar tracks one
  // against the other. A birth year rather than an age, so it keeps counting
  // on its own. Without one the bar stays hidden.
  readonly property int birthYear: Model.parseBirthYear(setting("birthYear", 0), today.getFullYear())
  readonly property int age: Model.ageFromBirthYear(birthYear, today.getFullYear())
  readonly property int lifeExpectancy: Model.parseLifeExpectancy(setting("lifeExpectancy", 0))
  readonly property real lifeDone: Model.lifeProgress(age, lifeExpectancy)
  readonly property int lifeDonePercent: Model.lifeProgressPercent(age, lifeExpectancy)
  property bool editingLife: false

  // Unset falls through to the locale's own first day, so a fresh install
  // starts out matching the rest of the desktop rather than a hardcoded
  // convention. Clicking the grid's "W" heading writes the choice back to
  // shell.json.
  readonly property int weekStart: Model.normalizedWeekStart(setting("weekStartDay", null), Qt.locale().firstDayOfWeek)
  // The interface is English throughout, so day names are not taken from the
  // system locale. Where the week starts still is: that is a regional
  // convention rather than a translation, and it stays overridable above.
  readonly property var labelLocale: Qt.locale("en_US")
  readonly property string nextWeekStartLabel: labelLocale.dayName(Model.toggledWeekStart(weekStart), Locale.LongFormat)
  readonly property var weekdays: Model.weekdayOrder(weekStart)
  readonly property var weeks: Model.monthGrid(viewYear, viewMonth, weekStart, todayKey)

  // ---- World clock, climate, holidays, events. Same plain settings as
  //      the bars above; empty values simply hide their blocks.
  readonly property var places: Model.parsePlaces(setting("places", ""))
  readonly property var worldRows: Model.worldClockRows(setting("places", ""), root.today)

  // The report is the same current-conditions shape the model's parser
  // keeps ({temperature_2m, apparent_temperature, weather_code, is_day});
  // a missing or unusable one just hides the line. Shared omarchy unit
  // convention: metric unless the unit setting says imperial.
  readonly property bool celsius: String(setting("unit", "")).toLowerCase() !== "imperial"
  readonly property var climate: Model.climateFromReport(root.weatherReport())

  // The Easter long weekend is the one holiday table the model ships, and
  // the country filter is the panel's own, so dots and the upcoming list
  // only mark the countries actually configured. The dots follow the month
  // being browsed; the upcoming list follows today.
  readonly property var easterHolidays: Model.easterHolidaysForYear(viewYear)
  readonly property var upcomingList: Model.upcomingHolidays(Model.easterHolidaysForYear(today.getFullYear()), 5, todayKey)

  // ---- Settings view. The gear in the header swaps the popup between the
  //      calendar and a form. Nothing here writes shell.json directly; it
  //      funnels through persistSettings() exactly like the calendar's own
  //      inline editors, so hot changes survive reopens.
  property bool showingSettings: false
  readonly property bool settingsVertical: root.hostWidget
    ? root.hostWidget.vertical === true : false
  readonly property string formatKey: root.settingsVertical ? "verticalFormat" : "format"
  readonly property string activeClockFormat: setting(root.formatKey, "")
  readonly property string weekStartChoice: {
    var stored = setting("weekStartDay", null)
    return stored === null ? "default" : String(stored).toLowerCase()
  }
  readonly property string unitChoice: String(setting("unit", "metric")).toLowerCase()
  readonly property string headerMeta: Qt.formatDate(root.today, "HH:mm")
    + "  \u00b7  ISO W" + Model.isoWeekLiteral(root.today.getFullYear(), root.today.getMonth() + 1, root.today.getDate())
    + "  \u00b7  day " + Model.dayOfYear(root.today.getFullYear(), root.today.getMonth() + 1, root.today.getDate())
    + "/365"

  // The format picker lists the presets for the current orientation plus the
  // configured format when it is a hand-written one, so whatever is active
  // is always selectable.
  readonly property var displayFormatOptions: {
    var presets = Model.clockFormats(root.settingsVertical)
    var out = []
    for (var i = 0; i < presets.length; i++)
      out.push({ format: presets[i], selected: presets[i] === root.activeClockFormat })
    var active = root.activeClockFormat
    if (active !== "") {
      var known = false
      for (var j = 0; j < out.length; j++) {
        if (out[j].format === active) { known = true; break }
      }
      if (!known) out.push({ format: active, selected: true })
    }
    return out
  }

  // Guarded so the widget renders before the bar is injected (the bar-widget
  // contract instantiates it bare).
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property int cellWidth: Style.space(52)
  readonly property int cellHeight: Style.space(34)
  readonly property int cellSpacing: Style.space(2)
  readonly property int weekColumnWidth: Style.space(32)
  readonly property int gutterWidth: Style.space(14)

  function open() {
    refresh()
    root.controller.show()
    // Set after showing, not before: showing hands the popout coordinator
    // over, which closes whichever panel was open, and that close clears the
    // shared flag. Deferring means the panel taking over always wins, while
    // a handoff to a panel that does not manage the flag still leaves it
    // cleared rather than stuck on.
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    // Dismissing the panel mid-edit would otherwise leave the inputs up,
    // waiting behind a closed popup for the next time it opens.
    if (root.editingLife) root.cancelEditingLife()
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  // Summoning by hotkey moves no pointer, so a hover the bar was still
  // holding must not keep the center indicators revealed behind the panel.
  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(value)
    else if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  function refresh() {
    root.today = new Date()
    root.goToToday()
  }

  function goToToday() {
    root.viewYear = today.getFullYear()
    root.viewMonth = today.getMonth()
  }

  function moveMonth(delta) {
    var next = Model.stepMonth(viewYear, viewMonth, delta)
    root.viewYear = next.year
    root.viewMonth = next.month
  }

  function moveYear(delta) {
    moveMonth(delta * 12)
  }

  // ---- Settings view actions. Every toggle below is a whole-config write
  //      through persistSettings(), the same path the inline editors take.

  function toggleSettings() {
    // Leaving the sheet folds any half-typed edits in; the fields' own blur
    // commit already covers most exits, this catches the gear click itself.
    if (root.showingSettings) {
      if (placesEditor) root.commitPlacesText(placesEditor.text)
      if (countryField) root.commitHolidayCountry(countryField.text)
    }
    root.showingSettings = !root.showingSettings
  }

  function setClockFormat(format) {
    if (!format || format === root.activeClockFormat) return
    var values = {}
    values[root.formatKey] = format
    root.persistSettings(values)
  }

  // "default" restores the system locale's first day of the week; anything
  // else is a weekday name the model already understands as a choice.
  function setWeekStartChoice(value) {
    if (value === "default") {
      root.persistSettings({ weekStartDay: null })
      return
    }
    root.setWeekStart(Model.normalizedWeekStart(value, 1))
  }

  function setUnit(value) {
    if (value !== root.unitChoice) root.persistSettings({ unit: value })
  }

  // Free-text editors commit on blur so typing never throttles the config
  // write. Whitespace-only input is stored empty, which simply hides the
  // affected surface.
  function commitPlacesText(text) {
    var cleaned = String(text).replace(/[\r\n]+/g, "\n").replace(/\s+$/g, "")
    if (cleaned === root.setting("places", "")) return
    root.persistSettings({ places: cleaned })
  }

  function commitHolidayCountry(text) {
    var cleaned = String(text).replace(/^\s+|\s+$/g, "")
    if (cleaned === root.setting("holidayCountry", "")) return
    root.persistSettings({ holidayCountry: cleaned })
  }

  function commitBirthYear(year) {
    if (year === root.birthYear) return
    root.persistSettings({ birthYear: Model.parseBirthYear(year, root.today.getFullYear()) })
  }

  function commitLifeExpectancy(years) {
    if (years === root.lifeExpectancy) return
    root.persistSettings({ lifeExpectancy: Model.parseLifeExpectancy(years) })
  }

  function clearLifeSetting() {
    root.persistSettings({ birthYear: 0 })
  }

  // A live preview for the format chips: the bar's 'ww' ISO-week token is
  // substituted first (Qt has no specifier of its own), and vertical newlines
  // collapse to middots so a chip stays one line tall.
  function formatDisplayLabel(format) {
    var text = String(format === undefined || format === null ? "" : format)
    if (text.indexOf("ww") !== -1) {
      text = text.replace(/ww/g, String(Model.isoWeekLiteral(root.today.getFullYear(), root.today.getMonth() + 1, root.today.getDate())))
    }
    try {
      var rendered = Qt.formatDate(root.today, text)
      if (rendered && rendered !== "") return String(rendered).replace(/\n/g, " \u00b7 ")
    } catch (e) { }
    return text
  }

  // Applied locally first so the panel redraws on the click itself; the
  // shell.json write comes back through the bar as the same value. With no
  // writable entry (the widget is not in the layout) it stays a session-only
  // preference rather than doing nothing. The host widget builds its own
  // entry when the label format is cycled, so it has to be kept in step or
  // it would write this key straight back out from a stale copy.
  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]

    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function setWeekStart(day) {
    var next = Model.normalizedWeekStart(day, root.weekStart)
    if (next === root.weekStart) return
    persistSettings({ weekStartDay: Model.weekStartSettingName(next) })
  }

  function startEditingLife() {
    root.editingLife = true
    Qt.callLater(function() {
      bornField.text = root.birthYear > 0 ? String(root.birthYear) : ""
      expectancyField.text = String(root.lifeExpectancy)
      bornField.selectAll()
      bornField.forceActiveFocus()
    })
  }

  function cancelEditingLife() {
    root.editingLife = false
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  // Shared by both fields: Tab hops to the other one, Enter commits the pair,
  // Escape drops the lot.
  function handleLifeKey(event, other) {
    if (event.key === Qt.Key_Escape) {
      root.cancelEditingLife()
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      root.commitLife()
      event.accepted = true
    } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      other.selectAll()
      other.forceActiveFocus()
      event.accepted = true
    }
  }

  // Double-tapping the life bar puts it away again. The expectancy stays in
  // the config so setting a birth year again brings your own number back
  // rather than the default.
  function clearLife() {
    if (root.birthYear <= 0) return
    persistSettings({ birthYear: 0 })
  }

  function commitLife() {
    var born = Model.parseBirthYear(bornField.text, today.getFullYear())
    var span = Model.parseLifeExpectancy(expectancyField.text)
    if (born !== root.birthYear || span !== root.lifeExpectancy)
      persistSettings({ birthYear: born, lifeExpectancy: span })
    cancelEditingLife()
  }

  function toggleWeekStart() {
    setWeekStart(Model.toggledWeekStart(root.weekStart))
  }

  // The stored report may be a plain object or a JSON string; either way
  // it lands as the object the model's report parser wants.
  function weatherReport() {
    var raw = setting("weather", null)
    if (raw && typeof raw === "string") {
      try { return JSON.parse(raw) } catch (e) { return null }
    }
    return raw
  }

  // Holidays are filtered by country, the same "Name, CC" lines the world
  // clock parses. Empty config marks nothing.
  function holidayCountry() {
    var list = Model.parseCountryList(setting("holidayCountry", ""))
    return list.length > 0 ? list[0].cc : ""
  }

  // Guarded so a missing report renders nothing rather than crashing the
  // binding: the model's null comes back as an empty line.
  function climateText() {
    var c = root.climate
    if (!c) return ""
    return c.glyph + " " + Model.tempLabel(c.temperature, root.celsius) + " · feels " + Model.tempLabel(c.feelsLike, root.celsius)
  }

  // English short day names, matching the rest of the interface.
  function weekdayLabel(weekday) {
    return String(labelLocale.dayName(weekday, Locale.ShortFormat)).toUpperCase()
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: {
      if (Model.keyForDate(clock.date) === String(root.todayKey)) return
      var followToday = root.viewingCurrentMonth
      root.today = clock.date
      if (followToday) root.goToToday()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(560))
    contentHeight: panel.fittedContentHeight(calendarColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // The settings sheet hands the keyboard to its controls: Tab/arrows
      // walk the form instead of stepping the month grid.
      blocked: root.editingLife || root.showingSettings
      onMoveRequested: function(dx, dy) {
        if (dx !== 0) root.moveMonth(dx)
        if (dy !== 0) root.moveYear(dy)
      }
      onActivateRequested: root.goToToday()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "[") root.moveMonth(-1)
        else if (t === "]") root.moveMonth(1)
        else if (t === "{") root.moveYear(-1)
        else if (t === "}") root.moveYear(1)
        else if (t === "t" || t === "T") root.goToToday()
        else if (t === "w" || t === "W") root.toggleWeekStart()
      }

      Flickable {
        id: calendarScroll
        anchors.fill: parent
        contentWidth: calendarColumn.width
        contentHeight: calendarColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height || contentWidth > width

        Column {
          id: calendarColumn
          // Never narrower than the grid. The popup width is capped to what
          // the screen allows, and a fixed seven-column grid would otherwise
          // lose its last days off the edge instead of scrolling.
          width: Math.max(calendarScroll.width, gridColumn.width)
          spacing: Style.space(8)

          // ---- Header: a title bar instead of a floating lock-up. The
          //      date reads at heading weight on the left with the living
          //      clock meta beneath it; the gear pins to the trailing edge
          //      and swaps the whole body between the calendar and its
          //      settings. Stepping the view back turns the left block into
          //      a "back to today" target, same as the old centered hero.
          Item {
            width: parent.width
            height: Style.space(56)

            PanelSeparator {
              anchors.bottom: parent.bottom
              anchors.left: parent.left
              anchors.right: parent.right
              foreground: root.contentForeground
              strength: 1.0
            }

            MouseArea {
              id: heroMouse
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              anchors.left: parent.left
              anchors.right: settingsGear.left
              enabled: !root.viewingCurrentMonth && !root.showingSettings
              hoverEnabled: enabled
              cursorShape: Qt.PointingHandCursor
              onClicked: root.goToToday()

              PanelToolTip {
                visible: heroMouse.containsMouse
                text: "Back to today"
                fontFamily: root.contentFontFamily
              }
            }

            Row {
              anchors.left: parent.left
              anchors.right: settingsGear.left
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.spacing.controlPaddingX
              spacing: Style.space(12)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "󰃭"
                color: heroMouse.containsMouse
                  ? Style.hoverStateColor(root.contentForeground, Color.accent)
                  : Qt.darker(root.contentForeground, 1.3)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.iconLarge
              }

              Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)

                Text {
                  id: heroDate
                  textFormat: Text.PlainText
                  text: root.showingSettings
                    ? "Preferences"
                    : Qt.formatDate(root.today, "dddd, MMMM d")
                  color: heroMouse.containsMouse
                    ? Style.hoverStateColor(root.contentForeground, Color.accent)
                    : root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.heading
                  font.bold: true
                }

                Text {
                  textFormat: Text.PlainText
                  text: root.showingSettings
                    ? "myles.clock \u00b7 changes apply immediately"
                    : root.headerMeta
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  font.letterSpacing: 0.5
                }
              }
            }

            PanelActionButton {
              id: settingsGear
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.rightMargin: Style.space(6)
              iconText: "\u2699"
              tooltipText: root.showingSettings ? "Back to calendar" : "Settings"
              foreground: root.showingSettings
                ? Style.hoverStateColor(root.contentForeground, Color.accent)
                : root.contentForeground
              hoverColor: Style.hoverStateColor(root.contentForeground, Color.accent)
              fontFamily: root.contentFontFamily
              focusable: true
              bordered: root.showingSettings
              onClicked: root.toggleSettings()
            }
          }

          // ---- Calendar body. Wrapped in one switchable stack so the
          //      settings form replaces it wholesale and the popup resizes
          //      to whichever view is open.
          Column {
            id: calendarView
            visible: !root.showingSettings
            width: parent.width
            spacing: Style.space(8)

            // ---- Year progress, doubling as the rule under the header:
            //      a plain hairline said nothing, and whole days done
            //      over days in the year says the same thing louder.
            Item {
              width: parent.width
              height: yearBlock.y + yearBlock.height

              Item {
                id: yearBlock
                y: Style.space(6)
                anchors.horizontalCenter: parent.horizontalCenter
                width: gridColumn.width
                height: Math.max(yearLabel.implicitHeight, Style.space(10))

                TapHandler {
                  enabled: !root.editingLife
                  onDoubleTapped: root.startEditingLife()
                }

                Row {
                  visible: root.editingLife
                  anchors.horizontalCenter: parent.horizontalCenter
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(10)

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "BORN"
                    color: Qt.darker(root.contentForeground, 1.5)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.letterSpacing: 1
                  }

                  TextField {
                    id: bornField
                    width: Style.space(70)
                    anchors.verticalCenter: parent.verticalCenter
                    placeholderText: "year"
                    foreground: root.contentForeground
                    font.family: root.contentFontFamily
                    inputMethodHints: Qt.ImhDigitsOnly

                    Keys.onPressed: function(event) { root.handleLifeKey(event, expectancyField) }
                  }

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: 0
                    leftPadding: Style.space(6)
                    text: "LIVE TO"
                    color: Qt.darker(root.contentForeground, 1.5)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.letterSpacing: 1
                  }

                  TextField {
                    id: expectancyField
                    width: Style.space(60)
                    anchors.verticalCenter: parent.verticalCenter
                    placeholderText: "90"
                    foreground: root.contentForeground
                    font.family: root.contentFontFamily
                    inputMethodHints: Qt.ImhDigitsOnly

                    Keys.onPressed: function(event) { root.handleLifeKey(event, bornField) }
                  }
                }

                Text {
                  id: yearLabel
                  textFormat: Text.PlainText
                  visible: !root.editingLife
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.today.getFullYear()
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.letterSpacing: 1
                }

                Text {
                  id: yearPercent
                  textFormat: Text.PlainText
                  visible: !root.editingLife
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.yearDonePercent + "%"
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                Rectangle {
                  id: yearTrack
                  visible: !root.editingLife
                  anchors.left: yearLabel.right
                  anchors.right: yearPercent.left
                  anchors.leftMargin: Style.space(12)
                  anchors.rightMargin: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  height: Style.space(6)
                  radius: Style.cornerRadius > 0 ? height / 2 : 0
                  color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)

                  Rectangle {
                    width: Math.round(parent.width * root.yearDone)
                    height: parent.height
                    radius: parent.radius
                    color: Style.selectedStateColor(root.contentForeground, Color.accent)

                    Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                  }
                }
              }
            }

            // ---- Memento mori. Only here once someone has gone looking and
            //      given an age; the same rail as the year above it, measured
            //      against a nominal lifetime.
            Item {
              visible: root.birthYear > 0
              width: parent.width
              height: visible ? lifeBlock.height : 0

              Item {
                id: lifeBlock
                anchors.horizontalCenter: parent.horizontalCenter
                width: gridColumn.width
                height: Math.max(lifeLabel.implicitHeight, Style.space(10))

                Text {
                  id: lifeLabel
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  text: "LIFE"
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.letterSpacing: 1
                }

                Text {
                  id: lifePercent
                  textFormat: Text.PlainText
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.lifeDonePercent + "%"
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                Rectangle {
                  anchors.left: lifeLabel.right
                  anchors.right: lifePercent.left
                  anchors.leftMargin: Style.space(12)
                  anchors.rightMargin: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  height: Style.space(6)
                  radius: Style.cornerRadius > 0 ? height / 2 : 0
                  color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)

                  Rectangle {
                    width: Math.round(parent.width * root.lifeDone)
                    height: parent.height
                    radius: parent.radius
                    color: Style.selectedStateColor(root.contentForeground, Color.accent)

                    Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                  }
                }

                TapHandler {
                  onDoubleTapped: root.clearLife()
                }

                MouseArea {
                  id: lifeMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  acceptedButtons: Qt.NoButton

                  PanelToolTip {
                    visible: lifeMouse.containsMouse
                    text: "Memento Mori"
                    fontFamily: root.contentFontFamily
                  }
                }
              }
            }

            // ---- Month grid: week numbers down a gutter on the left, then
            //      the seven day columns. Always six rows, so the popup is
            //      exactly as tall in February as it is in August.
            Item {
              width: parent.width
              height: gridColumn.y + gridColumn.height

              WheelHandler {
                onWheel: function(event) {
                  // Horizontal wheels and touchpad side-scrolls report y === 0;
                  // without this they would every one read as "next month".
                  if (event.angleDelta.y === 0) return
                  root.moveMonth(event.angleDelta.y > 0 ? -1 : 1)
                }
              }

              Column {
                id: gridColumn
                // The meter above is a solid rule; the grid needs room to
                // read as its own block rather than hanging off it.
                y: Style.space(18)
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Style.space(3)

                Row {
                  id: headerRow
                  spacing: root.cellSpacing

                  // The week-number heading doubles as the week-start toggle.
                  // It is the one control in the panel whose meaning is not
                  // self-evident, so it carries a tooltip naming the day the
                  // click will switch to.
                  Rectangle {
                    width: root.weekColumnWidth
                    height: Style.space(16)
                    radius: Style.cornerRadius
                    color: weekStartMouse.containsMouse
                      ? Style.hoverFillFor(root.contentForeground, Color.accent)
                      : "transparent"

                    Text {
                      anchors.centerIn: parent
                      text: "W"
                      color: weekStartMouse.containsMouse
                        ? Style.hoverStateColor(root.contentForeground, Color.accent)
                        : Qt.darker(root.contentForeground, 1.9)
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                      font.letterSpacing: 1
                      font.bold: true
                    }

                    MouseArea {
                      id: weekStartMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.toggleWeekStart()
                    }

                    PanelToolTip {
                      visible: weekStartMouse.containsMouse
                      text: "Start weeks on " + root.nextWeekStartLabel
                      fontFamily: root.contentFontFamily
                    }
                  }

                  Item {
                    width: root.gutterWidth
                    height: Style.space(16)
                  }

                  Repeater {
                    model: root.weekdays

                    Text {
                      textFormat: Text.PlainText
                      required property var modelData
                      width: root.cellWidth
                      height: Style.space(16)
                      horizontalAlignment: Text.AlignHCenter
                      verticalAlignment: Text.AlignVCenter
                      text: root.weekdayLabel(modelData)
                      color: Qt.darker(root.contentForeground, 1.5)
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                      font.letterSpacing: 1
                      font.bold: true
                    }
                  }
                }

                Repeater {
                  model: root.weeks

                  Row {
                    required property var modelData
                    spacing: root.cellSpacing

                    Text {
                      textFormat: Text.PlainText
                      width: root.weekColumnWidth
                      height: root.cellHeight
                      horizontalAlignment: Text.AlignHCenter
                      verticalAlignment: Text.AlignVCenter
                      text: modelData.week
                      color: Qt.darker(root.contentForeground, 1.9)
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                    }

                    Item {
                      width: root.gutterWidth
                      height: root.cellHeight
                    }

                    Repeater {
                      model: modelData.days

                      Rectangle {
                        id: dayCell
                        required property var modelData

                        property string dayFlags: Model.holidayFlagsForDay(root.easterHolidays, modelData.year, modelData.month, modelData.day)
                        property string dayHolidays: Model.holidayLabelsForDay(root.easterHolidays, modelData.year, modelData.month, modelData.day)
                        property bool hasHoliday: root.holidayCountry() !== "" && dayFlags.indexOf(root.holidayCountry()) !== -1

                        width: root.cellWidth
                        height: root.cellHeight
                        radius: Style.cornerRadius
                        // Today is outlined, not filled: a lit-up block shouts
                        // over a grid this quiet.
                        color: "transparent"
                        border.width: modelData.today ? Style.spacing.hairline : 0
                        border.color: Style.normalBorderFor(root.contentForeground, Color.accent)

                        Text {
                          textFormat: Text.PlainText
                          anchors.centerIn: parent
                          text: modelData.day
                          color: modelData.inMonth
                            ? (modelData.weekend ? Qt.darker(root.contentForeground, 1.45) : root.contentForeground)
                            : Qt.darker(root.contentForeground, 2.2)
                          font.family: root.contentFontFamily
                          font.pixelSize: Style.font.body
                          font.bold: modelData.today
                        }

                        // Holiday mark, a dot under the day number only when
                        // that day is one in the configured country. Hovering
                        // the cell names the holiday.
                        Rectangle {
                          visible: dayCell.hasHoliday
                          anchors.horizontalCenter: parent.horizontalCenter
                          anchors.bottom: parent.bottom
                          anchors.bottomMargin: Style.space(3)
                          width: Style.space(5)
                          height: Style.space(5)
                          radius: width / 2
                          color: Style.selectedStateColor(root.contentForeground, Color.accent)
                        }

                        MouseArea {
                          anchors.fill: parent
                          hoverEnabled: true
                          acceptedButtons: Qt.NoButton

                          PanelToolTip {
                            visible: parent.containsMouse && dayCell.hasHoliday
                            text: dayCell.dayHolidays
                            fontFamily: root.contentFontFamily
                          }
                        }
                      }
                    }
                  }
                }
              }

              // Hairline down the week-number gutter, drawn only beside the
              // day rows so it does not cut through the header band.
              Rectangle {
                x: gridColumn.x + root.weekColumnWidth + root.cellSpacing + Math.round((root.gutterWidth - width) / 2)
                y: gridColumn.y + headerRow.height + gridColumn.spacing
                width: Style.spacing.hairline
                height: gridColumn.height - headerRow.height - gridColumn.spacing
                color: root.contentForeground
                opacity: 0.1
              }
            }

            // ---- Month stepping, spanning the grid it drives. The chevrons
            //      sit on the grid's outer bounds, the same edges the year
            //      rail above uses, so the row reads as the panel's other
            //      full-width rail instead of a cluster floating in space.
            //      The label is centered and fixed-width, so it holds still
            //      from "MAY" to "SEPTEMBER".
            Item {
              width: parent.width
              height: monthNav.height

              Item {
                id: monthNav
                anchors.horizontalCenter: parent.horizontalCenter
                width: gridColumn.width
                height: monthLabel.implicitHeight + Style.space(10)

                Text {
                  id: monthLabel
                  textFormat: Text.PlainText
                  anchors.horizontalCenter: parent.horizontalCenter
                  anchors.verticalCenter: parent.verticalCenter
                  // Fixed width so the chevrons hold still between a
                  // "MAY 2026" and a "SEPTEMBER 2026".
                  width: Style.space(130)
                  horizontalAlignment: Text.AlignHCenter
                  text: Qt.formatDate(root.viewDate, "MMMM yyyy").toUpperCase()
                  color: Qt.darker(root.contentForeground, 1.4)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                  font.letterSpacing: 1
                }

                PanelActionButton {
                  // Pulled out by the button's own padding so the glyph, not
                  // its hit box, lines up with the "2026" on the year rail.
                  anchors.left: parent.left
                  anchors.leftMargin: -Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: "󰅁"
                  tooltipText: "Previous month"
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  onClicked: root.moveMonth(-1)
                }

                PanelActionButton {
                  anchors.right: parent.right
                  anchors.rightMargin: -Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: "󰅂"
                  tooltipText: "Next month"
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  onClicked: root.moveMonth(1)
                }
              }
            }

            // ---- World clock, when places are configured: each row is the
            //      place name, its local time, and the country code the
            //      model attached. Nothing renders without any places.
            Item {
              visible: root.places.length > 0
              width: parent.width
              height: visible ? worldBlock.height : 0

              Item {
                id: worldBlock
                anchors.horizontalCenter: parent.horizontalCenter
                width: gridColumn.width
                height: worldColumn.height

                Column {
                  id: worldColumn
                  width: parent.width
                  spacing: Style.space(5)

                  Text {
                    text: "WORLD"
                    color: Qt.darker(root.contentForeground, 1.5)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 1
                    font.bold: true
                  }

                  Repeater {
                    model: root.worldRows

                    Item {
                      required property var modelData
                      width: worldColumn.width
                      height: Style.space(22)

                      Text {
                        textFormat: Text.PlainText
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.name
                        color: root.contentForeground
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.bodySmall
                      }

                      Text {
                        textFormat: Text.PlainText
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.time + "  " + modelData.cc
                        color: Qt.darker(root.contentForeground, 1.5)
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.bodySmall
                      }
                    }
                  }
                }
              }
            }

            // ---- Current conditions, one quiet line beneath the calendar
            //      when a report is available. The glyph and the "feels"
            //      both come out of the model's report parser.
            Item {
              visible: root.climate !== null
              width: parent.width
              height: visible ? climateItem.height : 0

              Text {
                id: climateItem
                textFormat: Text.PlainText
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.climateText()
                color: Qt.darker(root.contentForeground, 1.5)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }

            // ---- Upcoming holidays, a few capped lines the model already
            //      sorted and dated. The date is read off the model's key.
            Item {
              visible: root.upcomingList.length > 0
              width: parent.width
              height: visible ? upcomingBlock.height : 0

              Item {
                id: upcomingBlock
                anchors.horizontalCenter: parent.horizontalCenter
                width: gridColumn.width
                height: upcomingColumn.height

                Column {
                  id: upcomingColumn
                  width: parent.width
                  spacing: Style.space(5)

                  Text {
                    text: "UPCOMING"
                    color: Qt.darker(root.contentForeground, 1.5)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 1
                    font.bold: true
                  }

                  Repeater {
                    model: root.upcomingList

                    Item {
                      required property var modelData
                      width: upcomingColumn.width
                      height: Style.space(22)

                      Text {
                        textFormat: Text.PlainText
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.name
                        color: root.contentForeground
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.bodySmall
                      }

                      Text {
                        textFormat: Text.PlainText
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: Qt.formatDate(new Date(Number(modelData.key.slice(0, 4)), Number(modelData.key.slice(5, 7)) - 1, Number(modelData.key.slice(8, 10))), "d MMM · yyyy", root.labelLocale)
                        color: Qt.darker(root.contentForeground, 1.5)
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.bodySmall
                      }
                    }
                  }
                }
              }
            }
          }

          // ---- Settings sheet. Same centered column width as the calendar
          //      grid so the swap reads as one surface; each section is a
          //      small-caps header over a control, with a dim hint line under
          //      the control explaining what it does. Every write goes
          //      through persistSettings() and applies the moment you click.
          Item {
            id: settingsView
            visible: root.showingSettings
            width: parent.width
            implicitHeight: settingsBody.height

            Column {
              id: settingsBody
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              spacing: Style.space(6)

              // ---- Display
              Column {
                width: parent.width
                spacing: Style.space(6)

                PanelSectionHeader {
                  text: "DISPLAY"
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                }

                Flow {
                  width: parent.width
                  spacing: Style.space(6)

                  Repeater {
                    model: root.displayFormatOptions

                    Button {
                      required property var modelData
                      text: root.formatDisplayLabel(modelData.format)
                      tooltipText: modelData.format
                      selected: modelData.selected
                      bordered: true
                      focusable: true
                      foreground: root.contentForeground
                      background: Color.background
                      accent: Color.accent
                      fontFamily: root.contentFontFamily
                      fontSize: Style.font.bodySmall
                      onClicked: root.setClockFormat(modelData.format)
                    }
                  }
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  wrapMode: Text.WordWrap
                  text: "Live previews of the bar label. Right-clicking the bar clock cycles formats, too."
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              // ---- Calendar
              Column {
                width: parent.width
                spacing: Style.space(6)

                PanelSeparator {
                  width: parent.width
                  foreground: root.contentForeground
                }

                PanelSectionHeader {
                  text: "CALENDAR"
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                }

                ButtonGroup {
                  options: [
                    { value: "default", label: "Default", tooltip: "Follow the system locale" },
                    { value: "monday", label: "Monday", tooltip: "ISO-style weeks" },
                    { value: "sunday", label: "Sunday", tooltip: "American convention" }
                  ]
                  value: root.weekStartChoice
                  foreground: root.contentForeground
                  background: Color.background
                  accent: Color.accent
                  fontFamily: root.contentFontFamily
                  onChanged: function(value) { root.setWeekStartChoice(value) }
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  wrapMode: Text.WordWrap
                  text: "Where the grid starts its week. Default follows the locale; the grid's W heading toggles Monday/Sunday on the spot."
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              // ---- World clock
              Column {
                width: parent.width
                spacing: Style.space(6)

                PanelSeparator {
                  width: parent.width
                  foreground: root.contentForeground
                }

                PanelSectionHeader {
                  text: "WORLD CLOCK"
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                }

                QQC.TextArea {
                  id: placesEditor
                  width: parent.width
                  height: Style.space(88)
                  text: root.setting("places", "")
                  placeholderText: "Nairobi, KE\nLondon, GB\nTokyo, JP"
                  placeholderTextColor: Qt.darker(root.contentForeground, 1.6)
                  color: root.contentForeground
                  selectionColor: Style.selectionFillFor(root.contentForeground, Color.accent)
                  selectedTextColor: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: TextEdit.Wrap
                  selectByMouse: true
                  leftPadding: Style.spacing.controlPaddingX + Border.left(Border.controlSpec("normal", root.contentForeground, Color.accent))
                  rightPadding: Style.spacing.controlPaddingX + Border.right(Border.controlSpec("normal", root.contentForeground, Color.accent))
                  topPadding: Style.spacing.inputPaddingY + Border.top(Border.controlSpec("normal", root.contentForeground, Color.accent))
                  bottomPadding: Style.spacing.inputPaddingY + Border.bottom(Border.controlSpec("normal", root.contentForeground, Color.accent))

                  background: BorderSurface {
                    color: Style.controlFill(false, false, root.contentForeground, Color.accent)
                    borderSpec: Border.controlSpec("normal", root.contentForeground, Color.accent)
                    radius: Style.cornerRadius
                  }

                  onEditingFinished: root.commitPlacesText(text)
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  wrapMode: Text.WordWrap
                  text: "One place per line, using Name, CC — e.g. Nairobi, KE. Comma-separated pairs also drive the country filters below."
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              // ---- Climate
              Column {
                width: parent.width
                spacing: Style.space(6)

                PanelSeparator {
                  width: parent.width
                  foreground: root.contentForeground
                }

                PanelSectionHeader {
                  text: "CLIMATE"
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                }

                ButtonGroup {
                  options: [
                    { value: "metric", label: "Metric", tooltip: "\u00b0C" },
                    { value: "imperial", label: "Imperial", tooltip: "\u00b0F" }
                  ]
                  value: root.unitChoice
                  foreground: root.contentForeground
                  background: Color.background
                  accent: Color.accent
                  fontFamily: root.contentFontFamily
                  onChanged: function(value) { root.setUnit(value) }
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  wrapMode: Text.WordWrap
                  text: "Units for the current-conditions line. Weather data itself arrives from the weather setting in shell.json."
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              // ---- Holidays
              Column {
                width: parent.width
                spacing: Style.space(6)

                PanelSeparator {
                  width: parent.width
                  foreground: root.contentForeground
                }

                PanelSectionHeader {
                  text: "HOLIDAYS"
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                }

                TextField {
                  id: countryField
                  width: parent.width
                  text: root.setting("holidayCountry", "")
                  placeholderText: "Kenya, KE"
                  foreground: root.contentForeground
                  accent: Color.accent
                  font.family: root.contentFontFamily
                  onEditingFinished: root.commitHolidayCountry(text)
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  wrapMode: Text.WordWrap
                  text: "Marks the holiday dots on the grid and feeds the UPCOMING list. One Name, CC pair — e.g. Kenya, KE."
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              // ---- Personal
              Column {
                width: parent.width
                spacing: Style.space(6)

                PanelSeparator {
                  width: parent.width
                  foreground: root.contentForeground
                }

                PanelSectionHeader {
                  text: "PERSONAL"
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                }

                Row {
                  spacing: Style.space(12)

                  NumberField {
                    id: settingsBorn
                    label: "BORN"
                    value: root.birthYear
                    from: 0
                    to: root.today.getFullYear()
                    stepSize: 1
                    fieldWidth: Style.spacing.numberFieldWidth
                    foreground: root.contentForeground
                    accent: Color.accent
                    fontFamily: root.contentFontFamily
                    onModified: function(v) { root.commitBirthYear(v) }
                  }

                  NumberField {
                    id: settingsExpectancy
                    label: "LIVE TO"
                    value: root.lifeExpectancy
                    from: 0
                    to: 120
                    stepSize: 1
                    fieldWidth: Style.spacing.numberFieldWidth
                    foreground: root.contentForeground
                    accent: Color.accent
                    fontFamily: root.contentFontFamily
                    onModified: function(v) { root.commitLifeExpectancy(v) }
                  }
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  wrapMode: Text.WordWrap
                  text: "A birth year of 0 hides the LIFE meter under the calendar. LIVE TO runs it against a nominal lifetime (90)."
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              // ---- Footer
              Column {
                width: parent.width
                spacing: Style.space(6)

                PanelSeparator {
                  width: parent.width
                  foreground: root.contentForeground
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  text: "myles.clock v1.0.0 \u00b7 changes reach shell.json instantly"
                  color: Qt.darker(root.contentForeground, 2.0)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }
        }
      }
    }
  }
}