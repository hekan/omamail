// Real IMAP cache and label migration, with only backend RPC stubbed.
import QtQuick
import QtTest
import "transports.js" as Transports
import "../../message/Message.js" as Message
import "../../account/Model.js" as Model
import "../../providers/Registry.js" as Registry
import "../../providers" as Providers
import "../../account" as Account
import "../../components" as Components

Item {
  id: root
  width: 400
  height: 500
  SystemPalette { id: palette }
  Component {
    id: sidebarFactory
    Components.MailboxSidebar {
      width: 400; height: 500
      textColor: palette.text; accentColor: palette.highlight; dimColor: palette.mid
      panelFontFamily: "monospace"
      service: null
    }
  }
  QtObject {
    id: auth
    property string accountId: "imap:synthetic@example.com"
    property string pluginDir: "/tmp/omamail-review113-cache"
    property var settings: ({
        imapHost: "imap.example.com",
        imapPort: 993,
        username: "synthetic",
        insecure: false
      })
    function withCredentials(cb) {
      cb("synthetic:secret", "");
    }
  }
  Providers.ImapClient {
    id: client
    auth: auth
    email: "synthetic@example.com"
  }
  QtObject {
    id: mailbox
    property bool ready: true
    property string providerId: "imap"
    property string rawQuery: ""
    property var labels: [
      {
        id: "Work",
        name: "Work",
        rawName: "Work",
        delimiter: "/"
      },
      {
        id: "Receipts",
        name: "Receipts",
        rawName: "Receipts",
        delimiter: "/"
      }
    ]
    property var monitoredIds: ["Work", "Receipts"]
    property var api: client
    property var cache: ({
        putLabels: function (x) {}
      })
    function monitoredMigrated(x) {
      monitoredIds = x;
    }
    function fail(x) {
      console.log(x);
    }
    function abortRequest(x) {
    }
  }
  Account.LabelActions {
    id: actions
    account: mailbox
  }
  TestCase {
    name: "RealImapCache"
    when: windowShown
    function test_server_folders_remain_visible_without_synthetic_destinations() {
      client.backend = null
      client.foldersLoaded = false
      Transports.install(client)
      var delivered = null
      client.getLabels(function(labels, error) {
        compare(error, "")
        delivered = labels
      })
      var requests = Transports.transports(client)
      compare(requests.length, 1)
      compare(requests[0].method, "imap.folders")
      var labels = [
        {id:"INBOX", name:"INBOX", rawName:"INBOX", delimiter:"/", system:true},
        {id:"Poczta/Wyslane", name:"Poczta/Wysłane", rawName:"Poczta/Wyslane", delimiter:"/", system:true},
        {id:"Projects.2026", name:"Projects.2026", rawName:"Projects.2026", delimiter:"", system:false}
      ]
      Transports.reply(requests[0], {folders:[], special:{"\\sent":"Poczta/Wyslane"},
        capabilities:[], labels:labels}, "")
      verify(delivered !== null, "Folder callback must run")
      var rows = Model.labelTree(delivered, [])
      var ids = rows.filter(function(row) { return row.selectable }).map(function(row) { return row.id })
      compare(JSON.stringify(ids), JSON.stringify(["INBOX", "Poczta/Wyslane", "Projects.2026"]))
      compare(rows[2].name, "Wysłane")
      compare(rows[2].depth, 1)
      compare(rows[2].rawName, "Poczta/Wyslane")
      compare(labels[0].system, true, "Do not mutate backend data")
      var views = Registry.mailboxes("imap", client.absentMailboxes, 10)
      compare(JSON.stringify(views.map(function(row) { return row.key })),
        JSON.stringify(["unread", "starred", "all"]))
      var sidebar = createTemporaryObject(sidebarFactory, root)
      sidebar.service = {
        labels:delivered, mailboxes:views, collapsedFolders:[], monitoredLabelIds:[],
        providerId:"imap", hasLabels:false, mailboxKey:"inbox", searchQuery:"", rawQuery:"", rawLabelId:""
      }
      verify(sidebar !== null)
      wait(0)
      function textItem(item, text) {
        if (item.text === text && item.textFormat !== undefined) return item
        var children = item.children || []
        for (var i = 0; i < children.length; i++) {
          var found = textItem(children[i], text)
          if (found) return found
        }
        return null
      }
      verify(textItem(sidebar, "FOLDERS") !== null)
      var inbox = textItem(sidebar, "INBOX")
      verify(inbox !== null)
      compare(inbox.parent.selected, true, "The initial inbox highlights the server folder")
      var sent = textItem(sidebar, "Wysłane")
      verify(sent !== null)
      var selectedName = "", selectedId = ""
      sidebar.labelSelected.connect(function(id, name) { selectedId = id; selectedName = name })
      mouseClick(sent, sent.width / 2, sent.height / 2)
      compare(selectedId, "Poczta/Wyslane")
      compare(selectedName, "Poczta/Wyslane", "Open the raw server name, not a synthetic role")
      compare(Transports.transports(client).length, 1, "Building the tree must not read mail")
    }

    function test_queued_listing_is_fresh() {
      var before = mailbox.labels;
      var second;
      Transports.install(client)
      function finish(request, names) {
        if (request.method !== "imap.folders") { Transports.reply(request, {}, ""); return }
        var labels = (names || []).map(function(name) { return {id:name,name:name,rawName:name,delimiter:"/"} })
        Transports.reply(request, {folders:labels,special:{},capabilities:[],labels:labels}, "")
      }
      function listing() {
        var requests = Transports.transports(client)
        for (var i = 0; i < requests.length; i++) {
          var request = requests[i]
          if (!request.answered && request.method === "imap.folders") return request
        }
        return null
      }
      client.renameLabel("Work", "Jobs", function (x, e) {
        compare(e, "");
        actions.afterLabelMoved(before[0], "Jobs", before);
        client.renameLabel("Receipts", "Bills", function (y, f) {
          compare(f, "");
          actions.afterLabelMoved(before[1], "Bills", before);
        });
      });
      var first = Transports.transports(client)[0]
      compare(first.params.accountId, "imap:synthetic@example.com")
      compare(first.params.credential, undefined)
      finish(first)
      second = Transports.transports(client).filter(function(request) {
        return request.method === "imap.renameFolder" && !request.answered
      })[0]
      var stale = listing();
      verify(stale !== null);
      finish(second)
      finish(stale, ["Jobs", "Receipts"]);
      wait(0);
      var fresh = listing();
      verify(fresh !== null, "A mutation during LIST requires a fresh server read");
      finish(fresh, ["Jobs", "Bills"]);
      tryCompare(actions, "reloading", false, 1000);
      compare(JSON.stringify(mailbox.monitoredIds), JSON.stringify(["Jobs", "Bills"]));
    }
  }
}
