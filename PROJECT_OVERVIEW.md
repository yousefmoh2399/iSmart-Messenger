# CS Scanner Project Overview

Last updated: 2026-04-07

## 1. Project Purpose

This repository contains a full workplace system with three main parts:

1. `backend/`
   Node.js + Express + MongoDB API.
2. `desktop_app/`
   Flutter desktop app for Windows used by employees/admins.
3. `mobile_app/`
   Flutter mobile app used mainly for scanning, uploading, and chat.

The system combines:

- document scanning and upload
- remote file browsing
- internal chat
- announcements
- ticket management
- desktop printing / file save relay
- desktop update distribution

## 2. High-Level Architecture

### Backend

The backend is the central source of truth. It provides:

- REST APIs for auth, users, documents, chat, tickets, announcements, backups, and updates
- Socket.IO real-time events for chat and desktop relay jobs
- MongoDB persistence for users, conversations, tickets, devices, releases, and update jobs

Entry points:

- `backend/src/server.js`
- `backend/src/app.js`

### Desktop App

The desktop app is a Flutter Windows client with custom Win32 runner logic.

It handles:

- admin and employee workflows
- chat and presence
- printer publishing to mobile
- saving files from mobile to desktop
- desktop update heartbeat and auto-install
- tray behavior and startup registration

Key entry points:

- `desktop_app/lib/main.dart`
- `desktop_app/lib/app/desktop_app.dart`
- `desktop_app/windows/runner/main.cpp`
- `desktop_app/windows/runner/flutter_window.cpp`

### Mobile App

The mobile app is a Flutter client focused on:

- camera/document scanning
- PDF generation
- pending upload management
- browsing uploaded files
- internal chat
- notifications

Key entry points:

- `mobile_app/lib/main.dart`
- `mobile_app/lib/app/mobile_app.dart`

## 3. Main Functional Areas

### Authentication and Session

Backend:

- `backend/src/routes/auth.routes.js`
- `backend/src/services/auth.service.js`

Desktop:

- `desktop_app/lib/features/auth/`

Mobile:

- `mobile_app/lib/features/auth/`

The apps store tokens locally, restore session on startup, and use `/api/users/me` to validate session state.

### User Management

Backend:

- `backend/src/routes/user.routes.js`
- `backend/src/controllers/user.controller.js`
- `backend/src/services/user.service.js`

Supports:

- profile editing
- avatar upload
- admin user creation / update / activation
- password reset

### Documents and Scanning

Backend documents:

- `backend/src/routes/document.routes.js`
- `backend/src/services/document.service.js`

Mobile scanning:

- `mobile_app/lib/features/scanner/data/scanner_service.dart`
- `mobile_app/lib/features/scanner/data/image_processing_service.dart`
- `mobile_app/lib/features/scanner/data/pdf_builder_service.dart`
- `mobile_app/lib/features/scanner/data/local_document_store.dart`

Desktop files:

- `desktop_app/lib/features/files/`

### Chat

Backend chat API and sockets:

- `backend/src/chat/controllers/chat.controller.js`
- `backend/src/chat/services/chat.service.js`
- `backend/src/chat/sockets/chat.socket.js`

Desktop chat:

- `desktop_app/lib/features/chat/`

Mobile chat:

- `mobile_app/lib/features/chat/`

Current chat capabilities include:

- direct/group/department/broadcast conversations
- typing state
- delivery / seen markers
- conversation preferences
- pinned group messages
- attachments
- presence status

### Tickets

Backend:

- `backend/src/tickets/`

Desktop:

- `desktop_app/lib/features/tickets/`

Mobile:

- `mobile_app/lib/features/tickets/`

### Announcements

Backend:

- `backend/src/admin/announcements/`

Desktop:

- `desktop_app/lib/features/admin/data/announcement_repository.dart`

Mobile:

- `mobile_app/lib/features/admin/data/announcement_repository.dart`

### Backup

Backend:

- `backend/src/admin/backup/`

Desktop admin UI:

- `desktop_app/lib/features/admin/presentation/backup_screen.dart`

## 4. Desktop Update System

Backend update management:

- `backend/src/admin/updates/update.service.js`
- `backend/src/admin/updates/update.controller.js`
- `backend/src/admin/updates/update-admin.routes.js`
- `backend/src/admin/updates/update-client.routes.js`
- `backend/src/admin/updates/device.model.js`
- `backend/src/admin/updates/release.model.js`
- `backend/src/admin/updates/update-job.model.js`
- `backend/src/admin/updates/update-task.model.js`

Desktop agent:

- `desktop_app/lib/shared/services/desktop_update_agent.dart`

Admin UI:

- `desktop_app/lib/features/admin/presentation/update_management_screen.dart`

Current behavior after the latest fix:

- desktop sends heartbeat regularly to backend
- backend can queue update tasks per device / branch / all devices
- desktop downloads the installer silently
- desktop verifies checksum when provided
- desktop launches a detached PowerShell helper
- helper waits for app shutdown, runs silent installer, reports task result to backend, then reopens the app
- the employee now sees an in-app updating overlay instead of needing to press Next/Next manually
- backend auto-completes an active task if the client restarts on the target version

## 5. Desktop Windows Runner Customizations

Relevant files:

- `desktop_app/windows/runner/main.cpp`
- `desktop_app/windows/runner/flutter_window.cpp`
- `desktop_app/windows/runner/flutter_window.h`

Important behaviors:

- system tray integration
- startup on Windows login
- tray presence status
- hide to tray on close
- single-instance enforcement

Latest fix:

- launching the desktop app again no longer creates extra running/background copies
- second launch focuses the existing instance instead

## 6. Mobile Notifications

### Existing Local Notifications

File:

- `mobile_app/lib/shared/services/local_notification_service.dart`

Used for local display inside the app when needed.

### New Push Notification Layer

Backend:

- `backend/src/models/push-device.model.js`
- `backend/src/services/push-notification.service.js`
- `backend/src/routes/user.routes.js`
- `backend/src/controllers/user.controller.js`
- `backend/src/services/user.service.js`

Mobile:

- `mobile_app/lib/shared/services/push_notification_service.dart`
- `mobile_app/lib/main.dart`
- `mobile_app/lib/app/mobile_app.dart`

Current flow:

1. Mobile app initializes Firebase Messaging.
2. Mobile app registers the current FCM token with backend using `/api/users/me/push-devices`.
3. Backend stores active push tokens per user/device.
4. When a chat message is created, backend checks whether the target user currently has a live mobile socket.
5. If the user does not have a live mobile socket, backend sends an FCM push notification.
6. On logout, the mobile app unregisters the current token.

Important note:

- Push notification code is now implemented.
- To make FCM work in production, Firebase project credentials/config must still be supplied.

Required Firebase setup:

- backend environment must provide one of:
  - `FIREBASE_SERVICE_ACCOUNT_JSON`
  - `FIREBASE_SERVICE_ACCOUNT_BASE64`
  - `FIREBASE_SERVICE_ACCOUNT_PATH`
  - or working `GOOGLE_APPLICATION_CREDENTIALS`
- mobile app must be connected to a Firebase project with platform config files
- Android typically needs a valid `google-services.json`
- iOS needs the matching Firebase/Apple push setup if iOS support is required

Without Firebase config:

- the app still runs normally
- push registration/send safely no-ops
- no background-closed-app notification will be delivered

## 7. Important Shared State / Providers

Desktop providers:

- `desktop_app/lib/shared/providers/providers.dart`

Mobile providers:

- `mobile_app/lib/shared/providers/providers.dart`

These are central for:

- API client
- auth repository
- socket connection
- local notifications
- desktop update agent
- push notification service

## 8. Common Operational Commands

Backend:

```bash
cd backend
npm install
npm start
```

Desktop:

```bash
cd desktop_app
flutter pub get
flutter run -d windows
```

Mobile:

```bash
cd mobile_app
flutter pub get
flutter run
```

## 9. Files To Read First For Future Changes

If the next task is mainly about backend business logic:

- `backend/src/app.js`
- `backend/src/server.js`
- the feature folder under `backend/src/...`

If the task is desktop-related:

- `desktop_app/lib/app/desktop_app.dart`
- `desktop_app/lib/shared/providers/providers.dart`
- the feature folder under `desktop_app/lib/features/...`
- `desktop_app/lib/shared/services/desktop_update_agent.dart`
- `desktop_app/windows/runner/main.cpp`

If the task is mobile-related:

- `mobile_app/lib/app/mobile_app.dart`
- `mobile_app/lib/shared/providers/providers.dart`
- the feature folder under `mobile_app/lib/features/...`
- `mobile_app/lib/shared/services/push_notification_service.dart`

## 10. Current Known Caveats

- Firebase push delivery still depends on real Firebase project configuration being added.
- Mobile `flutter analyze` currently reports only pre-existing deprecation infos around `Radio` APIs, not blocking errors.
- Backend `npm audit` reports dependency vulnerabilities; these were not addressed in this change set.

## 11. Summary Of Latest Fixes

Applied in this round:

- desktop updates now install automatically through a detached helper and reopen the app
- desktop update progress is visible to the employee through an overlay
- desktop duplicate-instance/background duplicate launch issue is fixed at the Windows runner level
- backend now tracks mobile push tokens and sends push notifications for chat when the mobile client is not live on socket
- project-wide technical reference added in this file
