# Chat Module

## Summary

The internal chat system is modular and separated from document logic.
The IT ticketing system is also modular and isolated from scanner/document flows.

### Backend

- path: `backend/src/chat/`
- HTTP + Socket.IO
- uses the existing JWT authentication flow
- ticket module path: `backend/src/tickets/`

### Frontend

- mobile: `mobile_app/lib/features/chat/`
- desktop: `desktop_app/lib/features/chat/`
- mobile tickets: `mobile_app/lib/features/tickets/`
- desktop tickets: `desktop_app/lib/features/tickets/`

## Main Data

- departments
- conversations
- messages
- conversation member states
- roles / permissions
- audit logs
- system error logs
- tickets
- ticket updates (timeline)
- ticket settings (support team members)

## Realtime Behavior

- sockets reconnect automatically
- active conversations are rejoined after reconnect
- unread counts and presence are updated through socket events
- incoming messages trigger local notifications unless the conversation is already open
- chat composer has rotating quick-actions for images, files, screenshot, and reaction
- desktop screenshot action uses window capture mode for open apps/windows
- mobile screenshot action sends a picked screenshot image from device storage

## Admin Scope

Admin can:

- manage users
- manage departments
- manage rooms
- create broadcast channels and define publishers/admins
- update role permissions
- inspect audit logs
- inspect backend system errors
- configure IT support team for ticket assignment

## Realtime Events

- `conversation_updated`, `receive_message`, `typing`, `message_seen`, `presence_updated`
- `ticket_updated`, `tickets_updated`, `ticket_settings_updated`

Manager capabilities depend on the assigned role permissions.
