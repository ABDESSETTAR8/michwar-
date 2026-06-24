/// <reference path="../pb_data/types.d.ts" />

// Default values for new `users` records (mirrors the defaults previously
// set by AuthService.createUserProfile in lib/core/services/auth_service.dart).
onRecordCreateRequest((e) => {
  if (!e.record.get("role")) e.record.set("role", "passenger");
  if (e.record.get("roleSelected") == null) e.record.set("roleSelected", false);
  if (e.record.get("loyaltyPoints") == null) e.record.set("loyaltyPoints", 0);
  if (!e.record.get("loyaltyTier")) e.record.set("loyaltyTier", "standard");
  if (e.record.get("totalRidesCompleted") == null) e.record.set("totalRidesCompleted", 0);
  e.next();
}, "users");

// Prevent a user from self-promoting their role or editing
// loyalty/ride-count fields via a normal PATCH — these are hook-only
// (role changes go through POST /api/michwar/role; loyalty fields are
// updated by the ride-completion hook). `roleSelected` is intentionally
// NOT protected — RoleSelectionScreen sets it to `true` via a normal PATCH
// once the user picks "passenger" (the "driver" path also sets it
// server-side, see pb_hooks/11_drivers.pb.js).
var MW_USER_PROTECTED_FIELDS = ["role", "loyaltyPoints", "loyaltyTier", "totalRidesCompleted"];

onRecordUpdateRequest((e) => {
  var isAdmin = e.auth && e.auth.get("role") === "admin";
  if (!isAdmin) {
    var original = $app.findRecordById("users", e.record.id);
    for (var i = 0; i < MW_USER_PROTECTED_FIELDS.length; i++) {
      var field = MW_USER_PROTECTED_FIELDS[i];
      e.record.set(field, original.get(field));
    }
  }
  e.next();
}, "users");
