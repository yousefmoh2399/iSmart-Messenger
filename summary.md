# CS Scanner System

Production-grade internal workplace system combining document scanning, chat, ticketing, and desktop integration.

## Update Log

### 2026-04-11 19:26 EET

Implemented a cross-platform stability and UX pass focused on chat-first navigation, branch organization, notifications, message favorites, and file-transfer flow.

Completed in this pass:

* App entry now opens directly on chat after authentication on both mobile and desktop.
* Mobile chat now includes quick access to `My Files`, the work dashboard, and the profile screen without returning to the old default landing flow.
* Desktop chat sidebar now includes quick actions for files, servers, and profile in both compact and expanded layouts.
* Realtime mobile notification taps now deep-link into the originating chat conversation instead of only opening the app shell.
* Theme cycling was simplified to light/dark only; `ThemeMode.system` is no longer used as a user-facing mode.
* Branch UX was aligned with the existing department model:
  * Admin screens
  * user creation/editing
  * chat directory/grouping
  * room labels and filters
  now present `الفروع` / `الفرع` instead of the previous department wording.
* Added per-message favorites in backend + mobile + desktop using message metadata:
  * toggle endpoint in chat API
  * optimistic updates in both apps
  * favorite action in mobile message sheet
  * favorite action in desktop message context menu
* Improved mobile incoming-file save UX:
  * clearer system-save explanation when choosing a custom location
  * preserved safe Android save flow without raw-path writes
* Desktop incoming LAN transfers can now:
  * save to the default configured folder
  * or choose a custom destination folder per transfer
* Desktop LAN sending now performs an explicit connectivity probe before file selection and raises the local direct-transfer limit to `500 MB`.
* Shared files in the desktop conversation info panel are now capped to 5 visible items with a `المزيد` entry opening the full shared-files gallery instead of overcrowding the panel.
* Mobile message actions now support re-downloading an attachment even after the inline download badge disappears.

Validation completed:

```bash
flutter analyze mobile_app
flutter analyze desktop_app
node --check backend/src/chat/services/chat.service.js
node --check backend/src/chat/controllers/chat.controller.js
node --check backend/src/chat/routes/chat.routes.js
```

---

# 🧩 Overview

This system is built as a **modular monorepo** with three main clients:

* 📱 **Mobile App (Flutter)** — scanning, uploads, chat
* 🖥️ **Desktop App (Flutter Windows)** — admin, files, updates, printing
* 🌐 **Backend (Node.js + Express)** — API, realtime, storage, orchestration

```text
Mobile App  ───┐
               ├──> Backend (REST + Socket.IO) ───> MongoDB + File Storage
Desktop App ───┘
```

---

# ⚙️ Core Capabilities

## 📄 Document System

* Mobile document scanning + enhancement
* Multi-page PDF generation
* Upload, browse, rename, delete
* Desktop file relay + printing

## 💬 Chat System

* Direct, group, department, broadcast conversations
* Realtime messaging via Socket.IO
* Typing indicators, presence, unread counts
* Delivery + seen states
* Attachments (images, files, PDFs)
* Screenshot sending (mobile + desktop)

## 🎫 Ticketing System

* IT support ticket creation
* Timeline (comments + internal notes)
* Status workflow:

  * open → assigned → in_progress → waiting_branch → resolved → closed
* Assignment to support team
* Realtime updates

## 🛠️ Admin System

* User & department management
* Role-based permissions
* Broadcast channels
* Audit logs + system error logs
* Ticket support team configuration

## 🔄 Desktop Update System

* Device heartbeat
* Remote update scheduling
* Silent installer execution
* Auto-restart after update

---

# 🧱 Architecture

## Backend

* Node.js + Express
* MongoDB (Mongoose)
* JWT authentication
* Socket.IO (realtime layer)

Responsibilities:

* API + business logic
* realtime messaging
* file storage management
* authentication + permissions

## Clients

### Mobile (Flutter)

* Scanner pipeline
* Upload manager
* Chat + notifications

### Desktop (Flutter Windows)

* Admin workflows
* File handling
* Printer integration
* Update agent

---

# 🔁 Realtime System

## Connection Lifecycle

1. Client connects via Socket.IO
2. JWT is validated during handshake
3. Active conversations are joined
4. Presence is broadcast

## Message Flow

```text
Client → send_message
Backend:
  - validate auth
  - validate membership
  - persist message
  - update conversation
  - emit receive_message
Clients:
  - update UI
  - trigger notification if needed
```

## Events

### Chat Events

* receive_message
* typing / stop_typing
* message_seen
* message_delivered
* presence_updated
* conversation_updated

### Ticket Events

* ticket_updated
* tickets_updated
* ticket_settings_updated

---

# 📦 Data Model (High-Level)

* Users
* Departments
* Conversations
* Messages
* Conversation Members
* Tickets
* Ticket Updates (timeline)
* Roles / Permissions
* Audit Logs
* System Error Logs

---

# 🔐 Security

* JWT authentication
* bcrypt password hashing
* role-based access control
* membership validation for chat
* file upload validation (multer)
* rate limiting
* audit logging for sensitive actions

---

# 🧠 Business Rules

* Each user belongs to one department
* Each department has a default conversation
* Direct conversations are unique per user pair
* Permission checks enforced on every route + socket
* Admin-only access to logs and system controls

---

# 📁 Project Structure

```text
backend/
  src/
    chat/
    tickets/

mobile_app/
  lib/features/
    chat/
    scanner/
    tickets/

desktop_app/
  lib/features/
    chat/
    files/
    tickets/
```

---

# 🚀 Setup

## Backend

```bash
cd backend
npm install
npm run start
```

## Mobile

```bash
cd mobile_app
flutter pub get
flutter run
```

## Desktop

```bash
cd desktop_app
flutter pub get
flutter run -d windows
```

---

# ⚠️ Known Limitations

* No OCR support yet
* No inline PDF preview in chat
* Push notifications require Firebase configuration
* Some UI areas can be further refined

---

# 📈 Future Improvements

* Redis adapter for Socket.IO scaling
* OCR integration for scanned documents
* Push notifications for terminated app state
* Enhanced admin analytics dashboard

---

# ✅ Summary

This system is designed as a **production-ready internal platform** with:

* modular architecture
* realtime communication
* strong permission model
* cross-platform clients

It is structured to scale, extend, and support real workplace operations.

---

# 2026-04-12 Bugfix Notes

* Fixed desktop chat sidebar header overflow by switching narrow widths to a compact actions layout with a popup menu instead of forcing all icons into one row.
* Tightened the desktop sidebar header again for ultra-narrow widths by progressively collapsing header actions, reducing avatar/padding sizes, and keeping only the overflow menu when space is too tight.
* Fixed desktop logout `CircularDependencyError` by simplifying `AuthController` login/logout flow and removing provider invalidations that were happening inside the auth notifier cycle.
* Fixed repeated desktop `Token refresh failed: لا يوجد رمز تجديد الجلسة` logs during re-login by making the API client skip auth attachment gracefully for unauthenticated/login requests.
* Restored `الأقسام` UI labels after an incorrect replacement with `الفروع` in chat, admin, conversation, and directory screens on mobile and desktop.
* Added a separate `الفروع` system alongside `الأقسام` instead of replacing it:
  * backend models/routes/services now support branch CRUD and user branch assignment
  * admin user creation/editing on mobile and desktop now supports selecting both department and branch
  * chat overview payloads and user models now include branch data on mobile and desktop
  * chat directory UI now shows employees grouped by branches in addition to departments
* Added a shared desktop top workspace bar for the main screens instead of relying only on scattered side/toolbar actions:
  * the bar now shows avatar + name + square icon buttons for chat, theme, refresh, files, servers, profile, new chat, admin, and tickets
  * the same visual header is now wired into chat, files, servers, profile, and chat appearance screens
  * switching from files/servers/profile back to chat now uses the dedicated chat icon and replacement navigation so the workspace feels like one continuous shell
* Added a dedicated `الفروع` filter beside `الأقسام` and `الغرف` in the desktop chat sidebar so branch browsing is no longer hidden inside the department flow.
