/// <reference path="../pb_data/types.d.ts" />

// POST /api/michwar/sos  { rideId: string, lat: number, lng: number }
// Replaces callable/sosAlert.ts. Best-effort attaches the reporting user's
// saved sosContacts phone numbers to the alert for the ops/admin dashboard
// to act on (actual SMS dispatch is out of scope for the self-hosted MVP).
routerAdd("POST", "/api/michwar/sos", (e) => {
  if (!e.auth) throw new UnauthorizedError("You must be signed in.");

  var data = new DynamicModel({ rideId: "", lat: 0, lng: 0 });
  e.bindBody(data);

  if (!data.rideId) {
    throw new BadRequestError("rideId, lat and lng are required.");
  }

  var ride = $app.findRecordById("rides", data.rideId);

  if (ride.get("passenger") !== e.auth.id && ride.get("driver") !== e.auth.id) {
    throw new ForbiddenError("Only ride participants can trigger SOS for this ride.");
  }

  var reportedBy = ride.get("passenger") === e.auth.id ? "passenger" : "driver";

  var alert = new Record($app.findCollectionByNameOrId("sos_alerts"));
  alert.set("ride", data.rideId);
  alert.set("reportedBy", reportedBy);
  alert.set("user", e.auth.id);
  alert.set("locationLat", data.lat);
  alert.set("locationLng", data.lng);
  alert.set("rideStatus", ride.get("status"));
  alert.set("passenger", ride.get("passenger"));
  if (ride.get("driver")) alert.set("driver", ride.get("driver"));
  alert.set("status", "open");

  try {
    var user = $app.findRecordById("users", e.auth.id);
    var sosContacts = user.get("sosContacts") || [];
    var phones = [];
    for (var i = 0; i < sosContacts.length; i++) {
      var contact = sosContacts[i];
      if (contact && contact.phone) phones.push(contact.phone);
    }
    alert.set("notifiedContacts", phones);
  } catch (err) {
    // best-effort only — don't fail the SOS if the user record can't be read
  }

  $app.save(alert);

  console.log("[SOS] ride=" + data.rideId + " reportedBy=" + reportedBy + " user=" + e.auth.id + " alert=" + alert.id);

  return e.json(200, { ok: true, alertId: alert.id });
}, $apis.requireAuth());
