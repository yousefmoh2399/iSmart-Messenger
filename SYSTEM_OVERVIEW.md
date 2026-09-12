# CS Scanner - System Overview

Last updated: 2026-04-09

## 1) Platform Components

- `backend/`: Node.js + Express + MongoDB + Redis (optional/fallback-aware) APIs.
- `mobile_app/`: Flutter mobile app (scanner, chat, files, updates, offline flow).
- `desktop_app/`: Flutter desktop app (admin/user workflow, chat, files, servers browser).

## 2) Authentication and Sessions

- Access token + refresh token architecture with automatic refresh.
- Multi-device sessions supported using per-device refresh sessions.
- Logout and session invalidation behavior aligned across desktop and mobile.
- Arabic-first error messaging for auth failures and session issues.

## 3) Backend Stability and Security

- Structured JSON logging for server lifecycle and request failures.
- Rate limiting applied with Redis-first behavior and safe fallback handling.
- Localized backend validation/errors for consistent Arabic UX.
- Emergency admin bootstrap support for disaster recovery scenarios.
- Graceful shutdown handling for process signals.

## 4) Mobile App Capabilities

- Professional scanner workflow with enhancement modes and fallback behavior.
- Chat + attachments with improved loading UX and download/save support.
- Offline mode support (work while offline, then automatic sync on reconnect).
- Update agent improvements (resilient task checks, better state handling).
- No timer-driven core logic where replaced with event/socket-driven behavior.

## 5) Desktop App Capabilities

- Files dashboard redesign and improved navigation.
- Chat UX improvements and attachment actions.
- Desktop-to-mobile and mobile-to-desktop file transfer flow support.
- Role-based file size limits:
  - Admin: up to 200 MB
  - Non-admin users: up to 30 MB

## 6) Servers Page and In-App Browser

Path: `desktop_app/lib/features/servers/presentation/servers_screen.dart`

### Server Monitoring

- Multiple company servers with configured fallback ports.
- Per-port health probing and availability status.
- Latency measurement (`ms`) for each probed port.
- Smart ranking: reachable ports first, then lower latency.
- Last successful port persistence per server.
- Stability score based on recent probe history.
- Alert when a server transitions from UP to DOWN.

### Browser Features

- In-app WebView (no forced external browser).
- Multi-tab browsing with tab session restore on app restart.
- Pinned tabs support.
- Protected pinned tabs: pinned tabs cannot be closed until unpinned.
- URL navigation bar + open action + copy current URL.
- Smart address suggestions while typing in the URL bar (history + bookmarks + known server links).
- Home shortcut to server initial URL.
- Back/forward/reload controls.
- Bookmarks management.
- Star toggle bookmark action for current page.
- Reopen last closed tab support.
- Duplicate current tab support.
- Find in page (`window.find`) from browser tools menu.
- Tabs overview panel for quick switching between all open tabs.
- Tabs overview supports drag-and-drop reorder with active-tab preservation.
- Built-in passwords manager panel (view saved hosts/users and remove entries).
- Keyboard shortcuts:
  - `Ctrl+L` focus address bar
  - `Ctrl+T` new tab
  - `Ctrl+W` close current tab
  - `Ctrl+R` reload
  - `Ctrl+F` find in page
- Unified browser tools menu (duplicate tab, reopen closed tab, find in page, open externally).
- Browser settings panel:
  - configurable home page
  - configurable search engine template
  - intranet-only mode switch (restricts external URLs)
- Clear browsing data flow with confirmation (history, bookmarks, saved passwords).
- Site permissions panel per host:
  - Notifications (Ask / Allow / Block)
  - Cookies (Allow / Block)
  - Popups (Allow / Block)
  - Persistent per-host permissions storage.
- Site data inspector:
  - shows current page host/port/path
  - displays currently visible cookies for the active page
- Per-site permissions reset for the current host.
- Browser profile portability:
  - Export browser profile JSON
  - Import browser profile JSON
  - Includes settings, bookmarks, history, saved credentials, and site permissions
- Page tools panel:
  - copy current page URL
  - view host/port/path page info
- Intranet practical operations:
  - one-click open for all company servers in pinned tabs
  - LAN guardrails to avoid accidental external browsing
- New tab grid view for internal-only workflow:
  - opening a new tab shows a 4-card company servers grid
  - each card displays server status color (up/down)
  - each card displays best port (with latency when available)
  - one click opens the selected server using best available port automatically
- Built-in credential helper:
  - Save login credentials per host automatically from values already typed in page login fields.
  - Login-page save suggestion prompt.
  - Auto-fill username/password on revisits for saved hosts (including after app restart and dynamic login forms).
- History with:
  - Search
  - Clear history action
  - Retention policy (last 30 days, capped to 300 entries)

### Download Experience

- Download manager with queue, progress, retry, and open-file actions.
- Download directory setting and recent downloaded files preview.
- Download items are managed through a dedicated "Download Manager" panel (not cluttering the URL area).
- Export/Import server settings (retry policy + persisted runtime settings).

## 7) UI and UX Direction

- Arabic-focused interface wording.
- Loading improvements including shimmer/skeleton usage in major flows.
- Improved profile and dashboard visual consistency on mobile and desktop.

## 8) Known Operational Notes

- Windows desktop builds that fail with executable lock may require closing the running app first.
- WebView plugin dependencies on Windows require proper NuGet availability.
- Final production confidence should include full E2E passes on:
  - login/refresh/session persistence
  - update flow
  - file transfer both directions
  - scanner quality
  - offline sync behavior

## 9) Suggested Next Hardening

- Complete and fix `npm audit` findings in backend dependencies.
- Run full regression matrix (mobile + desktop + backend) with documented checklist.
- Add automated smoke tests for critical APIs and socket events.
