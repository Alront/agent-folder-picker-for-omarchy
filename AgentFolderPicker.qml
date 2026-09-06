import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false
  property string filterText: ""
  property int selectedIndex: 0
  property bool cursorActive: false
  property var history: []
  property int historySelectedIndex: 0
  property bool historyCursorActive: false
  property int completionRequest: 0

  readonly property string pluginId: root.manifest && root.manifest.id
    ? String(root.manifest.id)
    : "io.github.alront.agent-folder-picker"
  readonly property string pluginDir: root.manifest && root.manifest.__sourceDir
    ? String(root.manifest.__sourceDir)
    : ""
  readonly property string homePath: Quickshell.env("HOME")
  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || (root.homePath + "/.local/state")
  readonly property string historyPath: root.stateHome + "/omarchy/agent-folder-picker/paths"
  readonly property string launcherPath: root.pluginDir + "/scripts/launch-agent"
  readonly property string completionPath: root.pluginDir + "/scripts/list-folders"

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int contentSpacing: Style.spacing.md
  property int headerHeight: Math.max(Style.space(42), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int footerHeight: Math.max(Style.space(28), Style.font.caption + Style.spacing.controlPaddingY)
  property int rowHeight: Math.max(Style.space(46), Style.font.title + Style.spacing.rowPaddingX * 2)
  property int cardWidth: Math.min(Style.space(600), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(430), panel.height - Style.gapsOut * 2)

  function open(payloadJson) {
    root.opened = true
    root.filterText = "~/"
    root.selectedIndex = 0
    root.cursorActive = false
    root.historySelectedIndex = 0
    root.historyCursorActive = false
    root.requestCompletions()
    historyFile.reload()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide(root.pluginId)
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function displayPath(path) {
    var value = String(path || "")
    if (value === root.homePath) return "~"
    if (value.indexOf(root.homePath + "/") === 0)
      return "~" + value.substring(root.homePath.length)
    return value
  }

  function loadHistory(raw) {
    var lines = String(raw || "").split("\n")
    var next = []
    var seen = ({})

    for (var i = 0; i < lines.length; i++) {
      var path = lines[i].trim()
      if (!path || seen[path]) continue
      seen[path] = true
      next.push(path)
    }

    root.history = next
    historyModel.clear()
    for (var j = 0; j < next.length; j++)
      historyModel.append({ folderPath: next[j] })

    if (historyModel.count === 0) {
      root.historySelectedIndex = 0
      root.historyCursorActive = false
    } else if (root.historySelectedIndex >= historyModel.count) {
      root.historySelectedIndex = historyModel.count - 1
    }
  }

  function loadCompletions(raw, serial) {
    if (serial !== root.completionRequest) return

    completionModel.clear()
    var lines = String(raw || "").split("\n")
    var seen = ({})

    for (var i = 0; i < lines.length && completionModel.count < 5; i++) {
      var path = lines[i].trim()
      if (!path || seen[path]) continue
      seen[path] = true
      completionModel.append({ folderPath: path })
    }

    if (completionModel.count === 0) {
      root.selectedIndex = 0
      root.cursorActive = false
    } else if (root.selectedIndex >= completionModel.count) {
      root.selectedIndex = completionModel.count - 1
    }

    Qt.callLater(function() {
      if (completionModel.count > 0)
        resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
  }

  function startCompletionScan(serial, query) {
    if (completionProc.running) {
      completionProc.queuedSerial = serial
      completionProc.queuedQuery = query
      return
    }

    completionProc.activeSerial = serial
    completionProc.queuedSerial = 0
    completionProc.queuedQuery = ""
    completionProc.command = [root.completionPath, query]
    completionProc.running = true
  }

  function requestCompletions() {
    root.completionRequest += 1
    completionModel.clear()
    root.selectedIndex = 0
    root.cursorActive = false
    completionTimer.restart()
  }

  function setFilter(nextFilter) {
    root.filterText = nextFilter
    root.historyCursorActive = false
    root.requestCompletions()
  }

  function selectHistory(delta) {
    if (historyModel.count === 0) return

    root.cursorActive = false
    if (!root.historyCursorActive) {
      root.historyCursorActive = true
      root.historySelectedIndex = 0
    } else {
      root.historySelectedIndex = (root.historySelectedIndex + delta + historyModel.count) % historyModel.count
    }

    historyList.positionViewAtIndex(root.historySelectedIndex, ListView.Contain)
  }

  function select(delta) {
    if (completionModel.count === 0) return

    root.historyCursorActive = false
    if (!root.cursorActive) {
      root.cursorActive = true
      root.selectedIndex = delta < 0 ? completionModel.count - 1 : 0
    } else {
      root.selectedIndex = (root.selectedIndex + delta + completionModel.count) % completionModel.count
    }

    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function selectAbsolute(index) {
    if (index < 0 || index >= completionModel.count) return
    root.historyCursorActive = false
    root.cursorActive = true
    root.selectedIndex = index
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function selectHistoryAbsolute(index) {
    if (index < 0 || index >= historyModel.count) return
    root.cursorActive = false
    root.historyCursorActive = true
    root.historySelectedIndex = index
    historyList.positionViewAtIndex(index, ListView.Contain)
  }

  function launchPath(path) {
    var requested = String(path || "").trim()
    if (!requested) return

    root.dismiss()
    Quickshell.execDetached([root.launcherPath, requested])
  }

  function activateIndex(index) {
    if (index < 0 || index >= completionModel.count) return
    root.launchPath(completionModel.get(index).folderPath)
  }

  function activateHistoryIndex(index) {
    if (index < 0 || index >= historyModel.count) return
    root.launchPath(historyModel.get(index).folderPath)
  }

  function submit() {
    if (root.historyCursorActive && historyModel.count > 0) {
      root.activateHistoryIndex(root.historySelectedIndex)
    } else if (root.cursorActive && completionModel.count > 0) {
      root.activateIndex(root.selectedIndex)
    } else if (root.filterText.trim()) {
      root.launchPath(root.filterText)
    } else if (completionModel.count > 0) {
      root.activateIndex(0)
    }
  }

  function completeSelected() {
    if (completionModel.count === 0) return
    root.setFilter(completionModel.get(root.selectedIndex).folderPath)
  }

  ListModel { id: completionModel }
  ListModel { id: historyModel }

  Timer {
    id: completionTimer
    interval: 40
    repeat: false
    onTriggered: root.startCompletionScan(root.completionRequest, root.filterText)
  }

  Process {
    id: completionProc
    property int activeSerial: 0
    property int queuedSerial: 0
    property string queuedQuery: ""

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.loadCompletions(text, completionProc.activeSerial)
    }

    onExited: {
      var serial = queuedSerial
      var query = queuedQuery
      activeSerial = 0
      queuedSerial = 0
      queuedQuery = ""
      if (serial > 0 && serial === root.completionRequest)
        root.startCompletionScan(serial, query)
    }
  }

  FileView {
    id: historyFile
    path: root.historyPath
    watchChanges: true
    printErrors: false
    onLoaded: root.loadHistory(text())
    onLoadFailed: root.loadHistory("")
    onFileChanged: reload()
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "agent-folder-picker"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        z: 10

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else root.dismiss()
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            if (event.modifiers & Qt.ShiftModifier) root.selectHistory(1)
            else root.select(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            if (event.modifiers & Qt.ShiftModifier) root.selectHistory(-1)
            else root.select(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Tab) {
            root.completeSelected()
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.submit()
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

        Rectangle {
          width: parent.width
          height: root.headerHeight
          radius: root.cornerRadius
          color: "transparent"

          Text {
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.filterText || "Agent folder..."
            color: root.foreground
            opacity: root.filterText ? 1 : 0.58
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            elide: Text.ElideLeft
          }
        }

        Row {
          width: parent.width
          height: parent.height - root.headerHeight - root.footerHeight - root.contentSpacing * 2
          spacing: root.contentSpacing

          Item {
            width: (parent.width - parent.spacing) / 2
            height: parent.height

            Text {
              id: folderHeading
              textFormat: Text.PlainText
              width: parent.width
              height: root.footerHeight
              text: "FOLDERS"
              color: root.foreground
              opacity: 0.55
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              verticalAlignment: Text.AlignVCenter
            }

            ListView {
              id: resultList
              anchors.top: folderHeading.bottom
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.left: parent.left
              model: completionModel
              clip: true
              spacing: Style.space(4)
              boundsBehavior: Flickable.StopAtBounds

              delegate: Rectangle {
                id: completionRow
                required property int index
                required property string folderPath

                readonly property bool hasCursor: root.cursorActive && index === root.selectedIndex

                width: ListView.view.width
                height: root.rowHeight
                radius: root.cornerRadius
                color: hasCursor ? root.selectedBackground : "transparent"

                Text {
                  textFormat: Text.PlainText
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(12)
                  anchors.rightMargin: Style.space(12)
                  text: root.displayPath(completionRow.folderPath)
                  color: completionRow.hasCursor ? root.selectedText : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  elide: Text.ElideMiddle
                  verticalAlignment: Text.AlignVCenter
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: root.selectAbsolute(completionRow.index)
                  onClicked: root.activateIndex(completionRow.index)
                }
              }
            }

            Text {
              visible: completionModel.count === 0
              anchors.centerIn: resultList
              width: resultList.width
              text: "No matching folders"
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
            }
          }

          Item {
            width: (parent.width - parent.spacing) / 2
            height: parent.height

            Text {
              id: historyHeading
              textFormat: Text.PlainText
              width: parent.width
              height: root.footerHeight
              text: "PREVIOUS PATHS"
              color: root.foreground
              opacity: 0.55
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              verticalAlignment: Text.AlignVCenter
            }

            ListView {
              id: historyList
              anchors.top: historyHeading.bottom
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.left: parent.left
              model: historyModel
              clip: true
              spacing: Style.space(4)
              boundsBehavior: Flickable.StopAtBounds

              delegate: Rectangle {
                id: historyRow
                required property int index
                required property string folderPath

                readonly property bool hasCursor: root.historyCursorActive && index === root.historySelectedIndex

                width: ListView.view.width
                height: root.rowHeight
                radius: root.cornerRadius
                color: hasCursor ? root.selectedBackground : "transparent"

                Text {
                  textFormat: Text.PlainText
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(12)
                  anchors.rightMargin: Style.space(12)
                  text: root.displayPath(historyRow.folderPath)
                  color: historyRow.hasCursor ? root.selectedText : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  elide: Text.ElideMiddle
                  verticalAlignment: Text.AlignVCenter
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: root.selectHistoryAbsolute(historyRow.index)
                  onClicked: root.activateHistoryIndex(historyRow.index)
                }
              }
            }

            Text {
              visible: historyModel.count === 0
              anchors.centerIn: historyList
              width: historyList.width
              text: "No paths opened yet"
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          height: root.footerHeight
          text: "Enter: open    Up/Down: folders    Shift+Up/Down: history    Tab: complete"
          color: root.foreground
          opacity: 0.55
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          verticalAlignment: Text.AlignVCenter
          horizontalAlignment: Text.AlignHCenter
        }
      }
    }
  }
}
