import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Daily Notes: um botão na barra abre um painel com a lista de notas diárias
// (arquivos .md em `notesDir`). "+" cria a nota de hoje e a abre em um Neovim
// flutuante; cada linha permite abrir, renomear e remover a nota.
//
// Toda a mexida em disco passa por daily-notes.sh, ao lado deste arquivo.
Panel {
  id: root
  moduleName: "thecraftlab.daily-notes"
  ipcTarget: "thecraftlab.daily-notes"
  manageIpc: false

  readonly property string home: Quickshell.env("HOME")
  readonly property string scriptPath: Qt.resolvedUrl("daily-notes.sh").toString().replace(/^file:\/\//, "")
  readonly property string notesDir: {
    var dir = String(setting("notesDir", "~/Documents/daily"))
    return dir.indexOf("~") === 0 ? home + dir.slice(1) : dir
  }
  readonly property string notesDirLabel: notesDir.indexOf(home) === 0 ? "~" + notesDir.slice(home.length) : notesDir
  readonly property string appId: String(setting("appId", "TUI.float"))
  readonly property string nvimAppName: String(setting("nvimAppName", "nvim-daily"))

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  property var notes: []            // [{ name, stem, mtime, size }]
  property bool loaded: false
  property bool cursorActive: false
  property int cursorIndex: 0
  property string renamingName: ""  // arquivo em edição de nome
  property string pendingDelete: "" // arquivo aguardando confirmação
  property string error: ""

  readonly property int maxListHeight: Style.space(320)
  readonly property int rowHeight: Style.space(44)

  // ---------- backend ----------

  function baseCommand() {
    return [root.scriptPath, "--dir", root.notesDir, "--app-id", root.appId, "--nvim-appname", root.nvimAppName]
  }

  function refresh() {
    if (listProc.running) return
    listProc.command = baseCommand().concat(["list"])
    listProc.running = true
  }

  function parseList(raw) {
    var lines = String(raw || "").split("\n")
    var out = []
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i]
      if (line.trim() === "") continue
      var parts = line.split("\t")
      var name = parts[0] || ""
      if (name === "") continue
      out.push({
        name: name,
        stem: name.replace(/\.md$/, ""),
        mtime: Number(parts[1]) || 0,
        size: Number(parts[2]) || 0
      })
    }
    root.notes = out
    root.loaded = true
    if (root.cursorIndex >= out.length) root.cursorIndex = Math.max(0, out.length - 1)
  }

  function runAction(args, closeAfter) {
    if (actionProc.running) return
    root.error = ""
    actionProc.closeAfter = closeAfter === true
    actionProc.command = baseCommand().concat(args)
    actionProc.running = true
  }

  function newNote() {
    root.pendingDelete = ""
    root.renamingName = ""
    runAction(["new"], true)
  }

  function openNote(name) {
    if (!name) return
    root.pendingDelete = ""
    root.renamingName = ""
    runAction(["open", name], true)
  }

  function startRename(name) {
    if (!name) return
    root.pendingDelete = ""
    root.renamingName = name
  }

  function commitRename(from, to) {
    root.renamingName = ""
    var next = String(to || "").trim()
    if (next === "" || next === from.replace(/\.md$/, "")) return
    runAction(["rename", from, next], false)
  }

  function requestDelete(name) {
    if (!name) return
    root.renamingName = ""
    if (root.pendingDelete === name) {
      confirmDelete()
      return
    }
    root.pendingDelete = name
  }

  function confirmDelete() {
    if (root.pendingDelete === "") return
    var target = root.pendingDelete
    root.pendingDelete = ""
    runAction(["delete", target], false)
  }

  function cancelTransient() {
    if (root.renamingName !== "") { root.renamingName = ""; return true }
    if (root.pendingDelete !== "") { root.pendingDelete = ""; return true }
    return false
  }

  function noteAt(index) {
    return index >= 0 && index < root.notes.length ? root.notes[index] : null
  }

  function moveCursor(delta) {
    if (root.notes.length === 0) return
    if (!root.cursorActive) { root.cursorActive = true; return }
    var next = root.cursorIndex + delta
    if (next < 0) next = root.notes.length - 1
    if (next >= root.notes.length) next = 0
    root.cursorIndex = next
    listView.positionViewAtIndex(next, ListView.Contain)
  }

  function formatWhen(mtime) {
    if (!mtime) return ""
    var d = new Date(mtime * 1000)
    var today = new Date()
    var sameDay = d.getFullYear() === today.getFullYear()
      && d.getMonth() === today.getMonth()
      && d.getDate() === today.getDate()
    return sameDay ? "hoje " + Qt.formatTime(d, "HH:mm") : Qt.formatDateTime(d, "dd MMM HH:mm")
  }

  IpcHandler {
    target: "thecraftlab.daily-notes"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function newNote(): void { root.newNote() }
    function refresh(): void { root.refresh() }
  }

  onOpenedChanged: {
    root.cursorActive = false
    root.cursorIndex = 0
    root.renamingName = ""
    root.pendingDelete = ""
    root.error = ""
    if (opened) refresh()
  }

  Process {
    id: listProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseList(text)
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var msg = String(text || "").trim()
        if (msg !== "") root.error = msg.replace(/^daily-notes: /, "")
      }
    }
  }

  Process {
    id: actionProc
    property bool closeAfter: false
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var msg = String(text || "").trim()
        if (msg !== "") root.error = msg.replace(/^daily-notes: /, "")
      }
    }
    onExited: function(exitCode) {
      root.refresh()
      if (exitCode === 0 && actionProc.closeAfter) root.close()
    }
  }

  // Mantém a lista viva enquanto o painel está aberto (nvim salvando, etc.).
  Timer {
    interval: 4000
    running: root.opened
    repeat: true
    onTriggered: root.refresh()
  }

  // ---------- botão na barra ----------

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰠮"
    tooltipText: "Notas diárias"
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton) root.newNote()
      else root.toggle()
    }
  }

  // ---------- painel ----------

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.renamingName !== ""

      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0) root.moveCursor(dx)
      }
      onActivateRequested: {
        if (root.pendingDelete !== "") { root.confirmDelete(); return }
        if (!root.cursorActive) return
        var note = root.noteAt(root.cursorIndex)
        if (note) root.openNote(note.name)
      }
      onDeleteRequested: {
        var note = root.noteAt(root.cursorIndex)
        if (root.cursorActive && note) root.requestDelete(note.name)
      }
      onCloseRequested: {
        if (!root.cancelTransient()) root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "n" || t === "+") root.newNote()
        else if (t === "r") {
          var note = root.noteAt(root.cursorIndex)
          if (root.cursorActive && note) root.startRename(note.name)
        }
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.spacing.panelGap

        PanelHero {
          title: "Notas diárias"
          meta: (root.notes.length === 0 ? "nenhuma nota" : (root.notes.length === 1 ? "1 nota" : root.notes.length + " notas")) + " · " + root.notesDirLabel
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconComponent: Component {
            Text {
              textFormat: Text.PlainText
              text: "󰠮"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }
          trailingControl: Component {
            Button {
              iconText: "󰐕"
              text: "Hoje"
              tooltipText: "Nova nota com a data de hoje (n)"
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              bordered: true
              onClicked: root.newNote()
            }
          }
        }

        PanelSeparator { foreground: root.foreground }

        // Estado vazio.
        Text {
          visible: root.loaded && root.notes.length === 0
          width: parent.width
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: "Nenhuma nota ainda. Clique em “Hoje” (ou pressione n) para criar a nota de " + Qt.formatDate(new Date(), "yyyy-MM-dd") + "."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        ListView {
          id: listView
          visible: root.notes.length > 0
          width: parent.width
          height: Math.min(contentHeight, root.maxListHeight)
          clip: true
          spacing: Style.spacing.xs
          boundsBehavior: Flickable.StopAtBounds
          model: root.notes
          delegate: NoteRow {}
        }

        Text {
          visible: root.error !== ""
          width: parent.width
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: root.error
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "↵ abrir · n nova · r renomear · x remover · esc fechar"
          color: root.dim
          opacity: 0.8
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }

  // ---------- linha da lista ----------

  component NoteRow: CursorSurface {
    id: row
    required property var modelData
    required property int index

    readonly property bool isRenaming: root.renamingName === modelData.name
    readonly property bool isPendingDelete: root.pendingDelete === modelData.name

    width: ListView.view ? ListView.view.width : 0
    height: root.rowHeight
    foreground: root.foreground
    hasCursor: root.cursorActive && root.cursorIndex === index

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      acceptedButtons: Qt.LeftButton
      onEntered: {
        root.cursorActive = true
        root.cursorIndex = row.index
      }
      onClicked: {
        if (row.isRenaming) return
        if (row.isPendingDelete) { root.pendingDelete = ""; return }
        root.openNote(row.modelData.name)
      }
      onDoubleClicked: if (!row.isRenaming) root.startRename(row.modelData.name)
    }

    Row {
      anchors.fill: parent
      anchors.leftMargin: Style.spacing.rowPaddingX
      anchors.rightMargin: Style.spacing.sm
      spacing: Style.spacing.controlGap

      Text {
        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        text: "󰈙"
        color: row.isPendingDelete ? root.urgent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
      }

      Item {
        id: labelSlot
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - parent.spacing * 2 - parent.children[0].width - actions.width
        height: row.height

        Column {
          visible: !row.isRenaming
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width
          spacing: Style.spacing.labelGap

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: row.modelData.stem
            color: row.isPendingDelete ? root.urgent : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: row.hasCursor
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: row.isPendingDelete
              ? "remover esta nota? ↵ ou clique em ✓"
              : root.formatWhen(row.modelData.mtime) + (row.modelData.size > 0 ? " · " + Math.max(1, Math.round(row.modelData.size / 1024)) + " KB" : " · vazia")
            color: row.isPendingDelete ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        TextField {
          id: renameField
          visible: row.isRenaming
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width
          foreground: root.foreground
          verticalPadding: Style.spacing.xs
          placeholderText: "novo nome"
          onVisibleChanged: {
            if (visible) {
              text = row.modelData.stem
              selectAll()
              Qt.callLater(function() { if (renameField.visible) renameField.forceActiveFocus() })
            }
          }
          onAccepted: root.commitRename(row.modelData.name, text)
          Keys.onEscapePressed: root.renamingName = ""
        }
      }

      Row {
        id: actions
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.xxs

        // Renomeando: confirmar / cancelar.
        PanelActionButton {
          visible: row.isRenaming
          iconText: "󰄬"
          tooltipText: "Confirmar nome"
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.commitRename(row.modelData.name, renameField.text)
        }
        PanelActionButton {
          visible: row.isRenaming
          iconText: "󰅖"
          tooltipText: "Cancelar"
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.renamingName = ""
        }

        // Aguardando confirmação de remoção.
        PanelActionButton {
          visible: row.isPendingDelete
          iconText: "󰄬"
          tooltipText: "Remover de vez"
          foreground: root.urgent
          hoverColor: root.urgent
          fontFamily: root.fontFamily
          onClicked: root.confirmDelete()
        }
        PanelActionButton {
          visible: row.isPendingDelete
          iconText: "󰅖"
          tooltipText: "Cancelar"
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.pendingDelete = ""
        }

        // Estado normal.
        PanelActionButton {
          visible: !row.isRenaming && !row.isPendingDelete
          iconText: "󰏫"
          tooltipText: "Renomear (r)"
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.startRename(row.modelData.name)
        }
        PanelActionButton {
          visible: !row.isRenaming && !row.isPendingDelete
          iconText: "󰆴"
          tooltipText: "Remover (x)"
          foreground: root.foreground
          hoverColor: root.urgent
          fontFamily: root.fontFamily
          onClicked: root.requestDelete(row.modelData.name)
        }
      }
    }
  }
}
