# Workplace Document Scanner + Internal Chat

Monorepo production-style system for internal workplace use:

1. `mobile_app/` Flutter mobile app for login, document scanning, PDF creation, upload, chat, and profile.
2. `desktop_app/` Flutter desktop app for document management, chat, admin operations, and profile.
3. `backend/` Node.js + Express + MongoDB API with JWT auth, file storage, Socket.IO, chat + ticket modules, admin controls, audit logs, and system error logs.

## Architecture

```text
Flutter Mobile ----\
                    -> Express API + Socket.IO -> MongoDB + Disk Storage
Flutter Desktop ---/
```

## Core Features

### Documents

- JWT login
- multi-user document ownership
- scan paper documents on mobile
- apply cleanup filters and build multi-page PDF
- upload PDF to backend
- view, rename, delete, download, and open documents

### Chat

- direct messages
- department conversations
- group rooms
- broadcast conversations
- broadcast publishers can target one or more departments per message
- typing indicator
- online / idle / offline / last seen
- unread counts
- delivery + seen state
- edit message
- delete message
- reply to message
- search inside conversation
- pagination for message history
- pin / mute / archive
- file / image / pdf attachments
- rotating quick-actions button in composer (images, files, screenshot, reaction)
- desktop: capture screenshot from open windows and send instantly
- mobile: pick and send screenshot image directly from device
- local notifications for incoming chat messages
- reconnect state banner in chat UI

### IT Tickets

- branch users can create IT support tickets with automatic ticket numbers
- ticket timeline with public comments and internal notes
- status workflow: open / assigned / in_progress / waiting_branch / resolved / closed
- assignment workflow to IT support team members
- realtime ticket updates through Socket.IO on mobile and desktop
- admin-managed IT support team membership

### Admin

- create / update / activate / deactivate users
- assign role and department
- create / update / delete departments
- manage rooms and memberships
- create broadcast channels and choose publishers/admins
- update role permissions
- configure IT support team members for ticket handling
- view audit logs
- view backend system error logs

### Profile

- current user profile screen on mobile and desktop
- update full name
- update password
- upload avatar
- avatar URLs returned from backend

## Tech Stack

### Backend

- Node.js
- Express.js
- MongoDB + Mongoose
- JWT
- bcrypt
- multer
- Socket.IO
- helmet
- cors
- express-rate-limit

### Flutter

- Flutter
- flutter_riverpod
- dio
- socket_io_client
- flutter_local_notifications
- screen_capturer
- cunning_document_scanner
- image
- pdf

## Monorepo Structure

```text
backend/
  src/
    chat/
      controllers/
      models/
      routes/
      services/
      sockets/
      utils/
    tickets/
      controllers/
      models/
      routes/
      services/
mobile_app/
  lib/
    features/
      auth/
      chat/
      files/
      profile/
      scanner/
      tickets/
desktop_app/
  lib/
    features/
      auth/
      chat/
      files/
      profile/
      tickets/
README.md
CHAT_MODULE.md
```

## Demo Users

Run the backend seed script first:

```bash
cd backend
npm run seed
```

Default demo accounts:

- `admin@DBACD.com / Admin@123456`
- `manager1 / 123456`
- `user1 / 123456`
- `user2 / 123456`

## Backend Setup

```bash
cd backend
npm install
cp .env.example .env
npm run dev
```

Important `.env` values:

- `PORT`
- `MONGODB_URI`
- `JWT_SECRET`
- `BASE_URL`
- `UPLOAD_DIR`
- `MAX_FILE_SIZE_MB`
- `CORS_ORIGIN`

The backend serves:

- REST API
- Socket.IO server
- document downloads
- chat attachment downloads
- avatar downloads

## Mobile Setup

```bash
cd mobile_app
flutter pub get
flutter run --dart-define=API_BASE_URL=https://usta.qzz.io
```

Notes:

- Android emulator: use `http://10.0.2.2:PORT`
- real device on same network: use your LAN IP
- public deployment: use your public HTTPS domain

## Desktop Setup

```bash
cd desktop_app
flutter pub get
flutter run -d windows --dart-define=API_BASE_URL=https://usta.qzz.io
```

## Chat Module Overview

Chat is isolated under `backend/src/chat/`, `mobile_app/lib/features/chat/`, and `desktop_app/lib/features/chat/`.

### HTTP Routes

- `GET /api/chat/users`
- `GET /api/chat/roles`
- `GET /api/chat/conversations`
- `GET /api/chat/admin/conversations`
- `POST /api/chat/conversations`
- `GET /api/chat/conversations/:id`
- `PUT /api/chat/conversations/:id`
- `PATCH /api/chat/conversations/:id/preferences`
- `DELETE /api/chat/conversations/:id`
- `GET /api/chat/conversations/:id/messages`
- `POST /api/chat/messages`
- `PATCH /api/chat/messages/:id`
- `PATCH /api/chat/messages/:id/seen`
- `DELETE /api/chat/messages/:id`
- `GET /api/chat/search/messages`
- `GET /api/chat/presence/:userId`
- `GET /api/chat/admin/audit-logs`
- `GET /api/chat/admin/system-errors`

## Ticket Module Overview

Tickets are isolated under `backend/src/tickets/`, `mobile_app/lib/features/tickets/`, and `desktop_app/lib/features/tickets/`.

### Ticket HTTP Routes

- `GET /api/tickets`
- `POST /api/tickets`
- `GET /api/tickets/:id`
- `POST /api/tickets/:id/comments`
- `PATCH /api/tickets/:id/status`
- `PATCH /api/tickets/:id/assignee`
- `GET /api/tickets/settings`
- `PUT /api/tickets/settings` (admin only)
- `GET /api/tickets/support-users`

### Socket Events

- `join_conversation`
- `leave_conversation`
- `send_message`
- `receive_message`
- `typing`
- `stop_typing`
- `message_seen`
- `message_delivered`
- `user_online`
- `user_offline`
- `presence_updated`
- `conversation_updated`
- `unread_count_updated`
- `ticket_updated`
- `tickets_updated`
- `ticket_settings_updated`

### Socket Authentication

- the same JWT token is used for REST and sockets
- socket handshake sends `auth.token`
- backend rejects unauthenticated socket sessions
- mobile and desktop automatically reconnect and rejoin active conversations

### Permission Model

Permissions are stored per role:

- `canCreateUsers`
- `canCreateDepartments`
- `canCreateRooms`
- `canSendBroadcast`
- `canDeleteMessages`
- `canUploadFiles`
- `canModerateDepartment`
- `canViewDepartmentLogs`

### Business Rules

- each user belongs to at most one department
- each department has a default department conversation on the backend
- department default rooms are hidden from the normal room picker UI
- direct conversation between the same two users is unique
- normal users cannot start direct chat with admin accounts
- ownership and membership are enforced on every route and socket event

## File Storage

- documents: `backend/uploads/{userId}/...`
- chat attachments: `backend/uploads/chat/{conversationId}/...`
- avatars: `backend/uploads/avatars/{userId}/...`

Metadata is stored in MongoDB. Physical files are removed when a document or chat attachment is deleted.

## Scanner Pipeline

The mobile scanner is a practical production-oriented implementation:

- camera scan via `cunning_document_scanner`
- document crop heuristic
- light flattening
- local contrast normalization
- wrinkle/shadow suppression
- paper whitening
- stronger text edge enhancement
- adaptive black/white mode

This produces a cleaner “printed page” look than the original capture while trying to preserve text readability.

## Theme + UI

- Material 3
- Arabic-first RTL
- dark blue visual direction
- light / dark / system theme switcher
- connection-state banner inside chat

## Notifications

- local notifications are shown for incoming chat messages on mobile and desktop
- active conversation is excluded from duplicate notifications
- socket reconnect state is surfaced in the UI

Practical note:

- on Android, foreground/background delivery depends on the app process staying alive
- true push delivery while the app is fully terminated still requires FCM; this repo currently uses Socket.IO + local notifications only

## Profile + Avatar

Profile APIs:

- `GET /api/users/me`
- `PUT /api/users/me`
- `POST /api/users/me/avatar`
- `GET /api/users/:id/avatar`

## Security

- bcrypt password hashing
- JWT auth
- ownership checks for documents
- membership checks for chat
- role-based permission checks
- multer validation for uploads
- rate limiting on auth and chat message posting
- helmet + CORS
- audit logging for privileged actions
- backend system error logging for admin review

## Verification

Commands verified locally:

```bash
cd backend
node --check src/chat/controllers/chat.controller.js
node --check src/chat/routes/chat.routes.js
node --check src/tickets/controllers/ticket.controller.js
node --check src/tickets/routes/ticket.routes.js
node --check src/tickets/services/ticket.service.js
node --check src/middleware/error.middleware.js

cd ../mobile_app
flutter pub get
flutter analyze
flutter test

cd ../desktop_app
flutter pub get
flutter analyze
flutter test
```

Note:
- full `mobile_app` analyze currently reports existing deprecation infos for old `Radio` usage (`groupValue` / `onChanged`) in scanner/files/chat screens, unrelated to tickets/broadcast additions.

## Known Limits

- scanner is enhanced but still not OCR-based
- no inline PDF renderer inside chat yet
- Android terminated-state push notifications are not implemented
- desktop admin/document screens still have room for more visual refinement beyond this production baseline
