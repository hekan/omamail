import QtQuick
import QtTest
import "../../account" as Account
import "../../providers/Registry.js" as Provider
import "../../account/Model.js" as Model

Item {
  Component {
    id: backendFactory
    QtObject {
      signal notification(string method, var params)
      property bool ready: true
      property var protocolInfo: ({ methods: [] })
      property var requests: []
      function call(method, params, done) {
        if (method === "providers.resolve") requests = requests.concat([{ params: params, done: done }])
      }
    }
  }
  Component {
    id: accountFactory
    Account.MailAccount {
      pluginDir: "/synthetic/provider-domain"
      accountId: "imap:synthetic@example.org"
      providerId: "imap"
      property int loads: 0
      function loadMessages() { loads++ }
      function loadProfile() {}
      function loadSendAs() {}
      function refreshCounts() {}
    }
  }
  TestCase {
    name: "NativeProviderDomain"
    function test_proton_and_gmail_share_all_mail_without_an_extra_archive_entry() {
      var proton = Provider.mailboxes("imap")
      var gmail = Provider.mailboxes("gmail")
      var common = proton.filter(function(box) {
        return gmail.some(function(other) { return other.key === box.key })
      })
      verify(common.some(function(box) { return box.key === "all" }))
      verify(!proton.some(function(box) { return box.key === "archive" }))
      verify(!gmail.some(function(box) { return box.key === "archive" }))
      compare(Provider.mailboxFor("imap", "all").query, "search:ALL")
      verify(!Provider.mailboxes("imap", [], 5).some(function(box) { return box.key === "all" }))
      verify(Provider.mailboxes("imap", [], 5).some(function(box) { return box.key === "archive" }))
      verify(!Provider.mailboxes("imap", [], 6).some(function(box) { return box.key === "archive" }))
      verify(Provider.mailboxes("imap", [], 6).some(function(box) { return box.key === "all" }))
      compare(Provider.mailboxFor("gmail", "all").query,
        "in:anywhere -in:spam -in:trash")
    }
    function test_native_descriptor_preserves_ceiling_and_mailbox_queries() {
      verify(!Provider.can("hey", "archive"))
      verify(!Provider.can("hey", "star"))
      verify(!Provider.can("jmap", "archive", { archive: "No Archive mailbox" }))
      compare(Provider.mailboxFor("imap", "unread").query, "folder:INBOX UNSEEN")
      compare(Provider.mailboxes("jmap", ["archive"]).length, 7)
    }
    function test_search_preparation_preserves_query_identity_and_cancels_on_navigation() {
      var backend = createTemporaryObject(backendFactory, parent)
      var account = createTemporaryObject(accountFactory, parent, { backend: backend, providerId: "gmail" })
      account.rawQuery = "label:A"
      account.rawLabelId = "Label_A"
      account.search("label:A")
      compare(account.effectiveQuery, "label:A")
      compare(account.rawLabelId, "Label_A")
      compare(backend.requests[0].params.operation, "query")
      backend.requests[0].done({ value: "label:A" }, null)
      compare(account.effectiveQuery, "label:A")
      compare(account.searchRaw, "label:A")
      account.search("stale")
      account.selectMailbox("trash")
      backend.requests[1].done({ value: "stale" }, null)
      compare(account.effectiveQuery, "in:trash")
      compare(account.searchQuery, "")
    }
    function test_server_folder_roles_preserve_draft_editing_and_clear_on_leaving() {
      var backend = createTemporaryObject(backendFactory, parent)
      var account = createTemporaryObject(accountFactory, parent, { backend: backend })
      tryVerify(function() { return account.api !== null })
      account.api.folders = [
        {name:"Poczta/Szkice", flags:["\\Drafts"], delimiter:"/"},
        {name:"Projects", flags:[], delimiter:"/"},
        {name:"Drafts", flags:[], delimiter:"/"},
        {name:"Poczta/Archiwum", flags:["\\Archive"], delimiter:"/"},
        {name:"Everything", flags:["\\All"], delimiter:"/"}
      ]
      account.api.special = {"\\drafts":"Drafts"}
      account.selectLabel("Poczta/Szkice", "Poczta/Szkice")
      backend.requests[0].done({value:'folder:"Poczta/Szkice"'}, null)
      compare(account.mailboxKey, "drafts", "The server role enables continuing an existing draft")
      compare(account.effectiveQuery, 'folder:"Poczta/Szkice"')
      account.selectLabel("Projects", "Projects")
      backend.requests[1].done({value:'folder:"Projects"'}, null)
      compare(account.mailboxKey, "inbox", "An ordinary folder must leave draft-editing mode")
      compare(account.effectiveQuery, 'folder:"Projects"')
      account.selectLabel("Drafts", "Drafts")
      backend.requests[2].done({value:'folder:"Drafts"'}, null)
      compare(account.mailboxKey, "inbox", "An English name or inferred mapping is not an advertised role")
      account.selectLabel("Poczta/Szkice", "Poczta/Szkice")
      account.selectMailbox("starred")
      backend.requests[3].done({value:'folder:"Poczta/Szkice"'}, null)
      compare(account.mailboxKey, "starred", "A stale folder reply must not restore the draft role")
      account.selectLabel("Poczta/Archiwum", "Poczta/Archiwum")
      backend.requests[4].done({value:'folder:"Poczta/Archiwum"'}, null)
      compare(account.effectiveQuery, 'folder:"Poczta/Archiwum"')
      compare(account.rawQuery, "", "An advertised role is a mailbox view, not a search")
      compare(Model.keyActionFor("archive", [{id:"1", inInbox:false}], account), "unarchive")
      account.selectLabel("Everything", "Everything")
      backend.requests[5].done({value:'folder:"Everything"'}, null)
      compare(account.effectiveQuery, 'folder:"Everything"')
      account.selectMailbox("all")
      compare(account.rawLabelId, "")
      compare(account.effectiveQuery, "search:ALL", "The virtual view must leave its same-role physical folder")
      account.selectMailbox("inbox")
      account.selectMailbox("all")
      compare(account.effectiveQuery, "search:ALL", "Returning must not reuse a physical folder's cached query")
    }

    function test_label_query_is_native_and_late_navigation_reply_is_ignored() {
      var backend = createTemporaryObject(backendFactory, parent)
      var account = createTemporaryObject(accountFactory, parent, { backend: backend })
      verify(account !== null)
      account.selectLabel("Old Mail", "folder-id")
      compare(backend.requests.length, 1)
      compare(backend.requests[0].params.operation, "labelQuery")
      compare(backend.requests[0].params.value, "Old Mail")
      compare(account.rawQuery, "")
      backend.requests[0].done({ value: "folder:\"Old Mail\"" }, null)
      compare(account.rawQuery, "folder:\"Old Mail\"")
      compare(account.rawLabelId, "folder-id")
      account.selectLabel("Stale", "stale")
      account.selectMailbox("trash")
      backend.requests[1].done({ value: "folder:\"Stale\"" }, null)
      compare(account.rawQuery, "")
      compare(account.mailboxKey, "trash")
    }
  }
}
