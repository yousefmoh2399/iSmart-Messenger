# CS Scanner Task Progress: Safe Hard Delete + Force Logout Fix

## Current Status

- [x] **Phase 1: tokenVersion security for force logout**
  - Added `tokenVersion` to user.model.js
  - Updated auth.middleware.js (JWT validation)
  - Updated user.service.js (increment on password change/reset)
- [ ] **Phase 2: Safe hard delete functions**
  - Add `deleteUser()` in user.service.js (cascade conversations/tickets)
  - Add `logoutUserAll()` (clear refreshSessions, emit socket, ++tokenVersion)
  - Add DELETE /users/:id and POST /users/:id/logout-all routes
- [ ] **Phase 3: Admin UI buttons**
  - Desktop Flutter: users_controller + UI buttons/dialogs
  - Mobile Flutter: users_controller + UI buttons/dialogs
- [ ] **Phase 4: Cascade cleanup for Branch/Department**
  - Update branch.service.js deleteBranch()
  - Update department.service.js deleteDepartment() (tickets too)
- [ ] **Phase 5: Test & Complete**

## Next Step

Implement safe `deleteUser()` and `logoutUserAll()` in `backend/src/services/user.service.js`

**Ready to proceed?**
