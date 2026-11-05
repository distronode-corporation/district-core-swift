import Foundation

// App parity's allowlist entries (Inbox reply options and assignment, WhatsApp window and
// templates), in a file of their own like `+Setup` and `+Meetings`. Chained into
// `allowedExplicitNulls` in `AllowedExplicitNulls+Union.swift`.

extension StrictDecodeVerifier {
    static let parity: [String: Set<String>] = [
        // ⛔ THE SAME FOUR CONTACT COLUMNS AS `district-conversations.json`'s row 1, ONE FACT
        // PER ROW: the counterpart matched no `Contact`. Rows 0, 1, 2 and 4 are the
        // WhatsApp-only number, the Messenger and Instagram threads and the stranger's SMS;
        // row 3 is the contact-keyed thread and nulls nothing.
        "district-conversations-reply-options.json": [
            "$.conversations[0].contactEmail",
            "$.conversations[0].contactId",
            "$.conversations[0].contactName",
            "$.conversations[0].contactPhone",
            "$.conversations[1].contactEmail",
            "$.conversations[1].contactId",
            "$.conversations[1].contactName",
            "$.conversations[1].contactPhone",
            "$.conversations[2].contactEmail",
            "$.conversations[2].contactId",
            "$.conversations[2].contactName",
            "$.conversations[2].contactPhone",
            "$.conversations[4].contactEmail",
            "$.conversations[4].contactId",
            "$.conversations[4].contactName",
            "$.conversations[4].contactPhone",
        ],
        // Row 1 is the same unresolved stranger, and nobody owns the thread:
        //
        //   assigneeEmail   Null when the thread is unassigned, beside `assignedToMe: false`.
        "district-conversations-assignee.json": [
            "$.conversations[1].assigneeEmail",
            "$.conversations[1].contactEmail",
            "$.conversations[1].contactId",
            "$.conversations[1].contactName",
            "$.conversations[1].contactPhone",
        ],
        // ⛔ THE WHOLE ANSWER TO AN UNASSIGN: nobody owns the thread now.
        "district-conversation-unassign.json": [
            "$.assignment",
        ],
        //   expiresAt    Null while the window is closed.
        //   receivedOn   Null when the customer never wrote on WhatsApp.
        "district-whatsapp-window-closed.json": [
            "$.receivedOn",
            "$.window.expiresAt",
        ],
        //   senderId        Null on a template tied to no one sender (row 0).
        //   variableCount   Null when the body's placeholders are named (row 1).
        "district-whatsapp-templates.json": [
            "$.templates[0].senderId",
            "$.templates[1].variableCount",
        ],
    ]
}
