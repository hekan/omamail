import QtQuick
import QtTest
import "../../components" as Components
import "../../providers/Registry.js" as Provider

Item {
  width: 200; height: 100
  Component {
    id: tabsFactory
    Components.MailboxTabs {
      textColor: palette.text
      accentColor: palette.highlight
      panelFontFamily: "sans-serif"
      allMailboxes: Provider.mailboxes("imap")
    }
  }
  SystemPalette { id: palette }
  TestCase {
    name: "MailboxTabsDestinations"
    function test_compact_server_folder_tabs_keep_inbox_and_localized_drafts_reachable() {
      var tabs = createTemporaryObject(tabsFactory, parent, {width:160})
      tabs.allMailboxes = Provider.mailboxes("imap", ["inbox", "drafts", "sent", "archive", "spam", "trash"], 10)
      tabs.folderLabels = [
        {id:"INBOX", name:"INBOX", rawName:"INBOX", system:false},
        {id:"Poczta/Szkice", name:"Poczta/Szkice", rawName:"Poczta/Szkice", system:false},
        {id:"literal", name:"<b>Folder</b>", rawName:"<b>Folder</b>", system:false}
      ]
      var selectedId = "", selectedName = ""
      tabs.folderSelected.connect(function(id, name) { selectedId = id; selectedName = name })
      tabs.currentFolderId = "Poczta/Szkice"
      tryVerify(function() { return tabs.contentX > 0 })
      function textItem(item, value) {
        if (item.text === value && item.textFormat !== undefined) return item
        var children = item.children || []
        for (var i = 0; i < children.length; i++) {
          var found = textItem(children[i], value)
          if (found) return found
        }
        return null
      }
      var drafts = textItem(tabs, "Poczta/Szkice")
      verify(drafts !== null)
      compare(drafts.parent.selected, true)
      mouseClick(drafts, drafts.width / 2, drafts.height / 2)
      compare(selectedId, "Poczta/Szkice")
      compare(selectedName, "Poczta/Szkice")
      var literal = textItem(tabs, "<b>Folder</b>")
      verify(literal !== null)
      compare(literal.textFormat, Text.PlainText, "Server names must not become markup")
      tabs.currentFolderId = "INBOX"
      var inbox = textItem(tabs, "INBOX")
      tryVerify(function() { return inbox.parent.selected })
      wait(0)
      mouseClick(inbox, inbox.width / 2, inbox.height / 2)
      compare(selectedId, "INBOX", "Return to Inbox without the hidden sidebar")
    }

    function test_narrow_windows_keep_all_mail_junk_and_trash_reachable() {
      var tabs = createTemporaryObject(tabsFactory, parent, { width: 160 })
      verify(tabs !== null)
      compare(tabs.mailboxes.length, tabs.allMailboxes.length)
      var keys = tabs.mailboxes.map(function(box) { return box.key })
      verify(keys.indexOf("all") >= 0)
      verify(keys.indexOf("spam") >= 0)
      verify(keys.indexOf("trash") >= 0)
      tryVerify(function() { return tabs.contentWidth > tabs.width })
      verify(tabs.interactive)
      tabs.current = "trash"
      tryVerify(function() { return tabs.contentX > 0 })
      tabs.current = "inbox"
      tryCompare(tabs, "contentX", 0)
    }
  }
}
