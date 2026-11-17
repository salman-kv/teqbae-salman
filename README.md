# Teqbae HRMS — Offline-Capable Employee Workspace (Flutter)

Employee app to view attendance, check in/out, and apply for leave. It keeps working offline and syncs reliably when the connection returns. UI follows the designs in `docs/`.

## Architecture: MVC

```
lib/
  models/        MODEL  – data classes + business rules (pure Dart, no Flutter)
    models.dart    Employee, AttendanceEvent, LeaveRequest, ...
    rules.dart     check-in/out rules, geofence distance, leave validation, history merge
  views/         VIEW   – widgets only; they read a controller and call its methods
    home_view, attendance_view, leave_view, leave_form_sheet, profile_view, app_shell
  controllers/   CONTROLLER – ChangeNotifier classes holding screen state + app logic
    attendance_controller   dashboard, punch in/out, Done, day summaries, history filter, Sync Now
    leave_controller        leave list + submit
    settings_controller     office override, mock GPS, mock API scenario, theme
  services/      talks to the outside world (used by controllers)
    api_service (Dio) · local_db (SQLite) · sync_service · location_service · connectivity_service
mock_server/     local mock REBS API (Dart shelf, in-memory data)
deliverables/    app-debug.apk, mock_server/ (standalone Windows build + config), video/ (demo clips)
test/            automated tests
```

Flow: **View → Controller → (Model rules + Services) → notifyListeners → View rebuilds.**
No business logic lives in `build()` methods.

### Stack and why
| Need | Choice | Why |
|---|---|---|
| State | `provider` + `ChangeNotifier` | Simplest fit for MVC; no code generation |
| HTTP | `dio` | Timeouts and clear error types |
| Storage | `sqflite` (SQLite) | Queue needs ordering + a unique constraint; JSON cache in one table |
| GPS | `geolocator` | Permissions + position in one package |
| Network | `connectivity_plus` | Triggers sync when the network returns |
| Timezone | `timezone` | Company date is computed in the company timezone |
| IDs | `uuid` | Client-generated event IDs |

## Setup and running

### Read this first: the app needs the mock server
The app has no backend inside it. It talks to a **mock API server** (`mock_server/`) over HTTP. The server address is fixed inside the APK as `http://10.0.2.2:8080`, which on an Android **emulator** means "the PC the emulator runs on".

| Situation | Does it work? |
|---|---|
| Android emulator on the same PC that runs the mock server | Yes. Start the server, install the APK, done |
| A real phone | Not with the prebuilt APK. Rebuild it with your PC's address (Path B) |
| First launch with the server not running | Error screen "No connection to the server." with a Retry button |
| Server was reachable once, then stopped | The app keeps working from saved data. Punches are queued and sync when the server is back |

So the APK alone is not enough: whoever receives it also needs the server running, on the PC where the emulator runs (Path A) or on a PC in the same Wi-Fi as the phone (Path B).

### Path A: Android emulator (quickest)
1. **Start the mock server** (pick one):
   * **Windows, no tools needed:** double-click `deliverables/mock_server/start_mock_server.bat`. It runs `rebs_mock_server.exe`, which reads `config.json` from the same folder. Keep the window open.
   * **Any OS with Flutter or Dart installed:**
     ```bash
     cd mock_server
     dart pub get
     dart run bin/server.dart
     ```
   Check it: open `http://localhost:8080/employee/me` in a browser. You should see the employee as JSON.
2. **Start an Android emulator** (Android 8 or newer).
3. **Install the app:** `adb install -r deliverables/app-debug.apk` (or drag the APK onto the emulator window).
4. **Allow location** when the app asks. To stand "at the office": emulator Extended controls (the `...` button) > Location > latitude `12.9716`, longitude `77.5946` > Send. Or use **Profile > Location Simulator > Use mock GPS > At office**.
5. **Open the app.** The first launch needs the server (it loads the profile and the office). Then try Punch In.

### Path B: a real Android phone (same Wi-Fi as the PC)
1. Start the mock server as in Path A. When Windows Firewall asks, allow it on private networks (port 8080).
2. Find the PC's IPv4 address (`ipconfig`), for example `192.168.1.10`. Check from the phone's browser: `http://192.168.1.10:8080/employee/me`.
3. Build an APK that knows that address, then install it:
   ```bash
   flutter build apk --debug --dart-define=API_BASE_URL=http://192.168.1.10:8080
   ```
   Output: `build/app/outputs/flutter-apk/app-debug.apk`.
4. A real phone is not at the configured office, so use **Profile > Location Simulator** (At office), or move the office to your location in `mock_server/config.json` (restart the server).
5. This path was not tested on a physical phone in this project (only on the emulator).

### Run from source, tests, rebuild
* Run: `flutter pub get`, then `flutter run` (emulator; uses `10.0.2.2:8080`). For a phone: `flutter run --dart-define=API_BASE_URL=http://<PC-IP>:8080`.
* Tests: `flutter test` (72 tests).
* App icon and launch screen: a location pin with a check mark on the brand blue (light splash `#1A5FDB`, dark `#0A2F7A`). The artwork is drawn by code: `flutter test tool/brand_art_test.dart` writes the PNGs to `assets/icon` and `assets/splash`, then `dart run flutter_launcher_icons` and `dart run flutter_native_splash:create` turn them into the Android resources (adaptive and Android 13 themed icon, light/dark/Android 12 splash). Both tools are dev-only dependencies.
* Rebuild the APK: `flutter build apk --debug`. Rebuild the standalone server: `cd mock_server && dart compile exe bin/server.dart -o ../deliverables/mock_server/rebs_mock_server.exe` (Windows build; copy `config.json` next to it).

### Between demos (reset)
* Reset the server data: open `http://localhost:8080/__reset` (also sets the scenario back to `normal`). Restarting the server does the same, because its data lives in memory.
* Reset the app: `adb shell pm clear com.example.teqbae_salman` (or Settings > Apps > Teqbae HRMS > Storage > Clear). This removes the saved data and the pending queue.

### Troubleshooting
| Symptom | Likely cause | Fix |
|---|---|---|
| "No connection to the server." on first launch | Server not running, or wrong address | Start the server. Emulator uses `10.0.2.2`. A phone needs the rebuilt APK and the firewall open |
| Works on the emulator, not on a phone | The APK points to `10.0.2.2` | Use Path B |
| "You are 1112 m from the office..." | GPS is not at the office | Profile > Location Simulator > At office, or set the emulator location |
| Punch rejected: "Outside permitted area" | Office Geofence override differs from the server's office | Profile > Office Geofence > Reset |
| Pending Sync does not clear | Server down, or a scenario such as `server_error` or `timeout` is active | Profile > Mock API Scenario > Normal, then Sync Now |
| Port 8080 already in use | Another copy of the server is running | Stop it, or change `port` in `config.json` and rebuild the app with `--dart-define=API_BASE_URL=...` |
| Name or office change not visible | The server reads `config.json` only at start | Restart the server, then reopen the app online |

### Demo flow (3-5 min)
Dashboard load > Punch In > Punch Out > Punch In again (the total adds up) > turn the server off (Profile > Mock API Scenario > Server error) and Punch Out / Done > close and reopen the app (pending is kept) > back to Normal and tap **Sync Now** > Attendance: open a day (the seed data has Short hours and 10 PM auto-closed examples) > Leaves: open a request, then Apply and show the validation errors (past date, overlap, short reason, over balance) and a successful submit.

Recorded demo clips of every scenario (online, offline, sync, retry, geofence, rejection, leave, calendar, Profile tools) are in `deliverables/video/` (see `SCENES.md` there).
### Configurable office coordinates
* Server side: `mock_server/config.json` (`office.latitude/longitude/radiusMeters/timezone`), or `POST /__config` with `{"latitude":..,"longitude":..,"radiusMeters":..}`.
* Device side: **Profile → Office Geofence** overrides the coordinates and radius on the device (Reset restores the server value). If the device and server offices differ, the server rejects the event, which is a handy demo of server-side validation.

### Simulating locations (for reviewers)
* **In-app**: **Profile → Location Simulator** → turn on *Use mock GPS*, then choose *At office* or *~1 km away* or type coordinates.
* **Emulator**: Extended controls (…) → Location → set a point and *Send*.

### Mock scenarios (**Profile → Mock API Scenario**, or by URL)
`GET http://localhost:8080/__scenario/<name>[?count=1]` — `count=1` applies it to the next request only.

| Scenario | Behaviour |
|---|---|
| `normal` | Successful responses |
| `slow` | Every call delayed 3 s |
| `timeout` | Server never answers; nothing is saved |
| `timeout_after_accept` | Event IS saved, but the reply never arrives (the hard case) |
| `server_error` | 500 on every call |
| `duplicate_conflict` | `POST /attendance/events` → 409 "already exists" |
| `leave_reject` | `POST /leave/requests` → 422 with field errors |

`GET /__reset` restores seed data.

## How the mock server works

`mock_server/bin/server.dart` is a small HTTP server written with Dart `shelf` and `shelf_router`. It listens on all network interfaces, on the port from `config.json` (8080).

* **No database.** All state is kept in memory: the attendance days with their events, the table of event ids already processed (idempotency), and the leave requests. A restart or `/__reset` brings back the seed data. `config.json` only holds the employee, the office (position, radius, timezone) and the yearly leave totals.
* **Seed data:** the last six working days of attendance (weekdays only), including a short-hours day and a day that was never closed (auto-closed at 10 PM), plus three leave requests (Approved, Pending, Rejected). Leave balance = yearly total minus Pending and Approved days.
* **Request path:** every request is logged, goes through the **scenario middleware** (which can delay it, hang it, answer 500, 409 or 422, depending on the active scenario), and then reaches the endpoint handler.
* **Attendance checks done by the server** (it never trusts the phone): inside the office radius (except "Done"), timestamp not in the future, work date equal to the company date of the timestamp, events in time order, no punch in while already punched in, punch out only after a punch in, Done only after punching out, nothing after Done or after 10 PM. A repeated `eventId` is answered with the first result (`duplicate:true`) and creates nothing.
* **Leave checks done by the server:** valid type and dates, start not in the past, end not before start, enough balance, no overlap with a Pending or Approved request, reason of at least 10 non-space characters.
* **Approving and rejecting leave.** The app has no manager login (login is out of scope). Instead the **reviewer tool** (Profile > Leave Approvals) calls the control endpoint GET /__leave/<id>/approve or /reject. Only a Pending request can be decided (a second decision gets 409, an unknown id 404). Approved requests keep their days reserved, rejected ones free them, and the calendar and balances follow. Attendance has no approval step: the attendance "Rejected" status means the server refused a punch during sync.
* **Control endpoints** (not part of the real API): `/__scenario/<name>[?count=N]`, `/__leave/<id>/approve|reject`, `/__reset`, and `/__config` (GET or POST to change the office at runtime).

## Profile options: what each one does

| Option | What it does | Effect in the app |
|---|---|---|
| **Office Geofence** | Overrides the office latitude, longitude and radius on this phone only. Reset goes back to the server's office. | The distance check before a punch uses it. The server does not know about it, so if it differs from the server's office the server rejects the punch (shown as Rejected). |
| **Location Simulator** | Shows the phone's **current real GPS coordinates** (read once, with the distance to the office, a refresh button and a "Use as mock position" shortcut). When mock GPS is switched on, punches use the coordinates you pick (At office, ~1 km away, or typed) instead of the real GPS. | The punch is blocked or allowed by the same distance rule, and the coordinates are sent to the server with the event. |
| **Mock API Scenario** | Tells the mock server how to answer the next requests (see the scenario table). "Only for the next request" makes it one-shot. | The phone shows the chosen name; failures show up as Pending Sync, Rejected, or error messages. Changing it needs the server to be reachable. |
| **Leave Approvals** | Lists Pending leave requests with Reject and Approve buttons (stands in for a manager). Calls the mock server's /__leave/<id>/approve|reject. | The request becomes Approved or Rejected in the Leaves tab and the calendar; the Home and Leaves balances update (rejecting frees the days). Needs the server to be reachable. |
| **Offline Sync Queue** | Shortcut to Attendance filtered on Pending Sync. | The count shown is the number of events waiting in the phone's database. |
| **Appearance** | Light, Dark or System theme. | The whole app changes and remembers the choice. |

The app never tracks location continuously: GPS is read once, at the moment of a punch.
## API contract (mock server)

Same endpoints as the suggested list. Deviations are explained below. All bodies are JSON; times are ISO-8601 UTC; dates are `YYYY-MM-DD`.

| Method | Endpoint | Request | Success response |
|---|---|---|---|
| GET | `/employee/me` | – | `{id, name, department, office:{latitude, longitude, radiusMeters, timezone}}` |
| GET | `/attendance?month=YYYY-MM` | – | `{records:[{id, date, events:[{eventId, type, timestamp}]}]}` – every punch of the day, in order |
| POST | `/attendance/events` | `{eventId, type:"check_in"\|"check_out"\|"day_done", timestamp, latitude, longitude, workDate}` (`check_in` = Punch In, `check_out` = Punch Out, `day_done` = Done, which needs no position) | `201 {status:"accepted", eventId, duplicate:false}`; a repeat of a known `eventId` returns `200 {…, duplicate:true}` and creates nothing |
| GET | `/leave/balance` | – | `{casual, sick}` – days **still available** (pending + approved requests already deducted) |
| GET | `/leave/requests` | – | `{requests:[{id, type, startDate, endDate, reason, status}]}` |
| POST | `/leave/requests` | `{type:"casual"\|"sick", startDate, endDate, reason}` | `201` the new request (`status:"pending"`) |

Errors: `400` malformed · `409` already punched in / day already done · `422` outside geofence, punch out without punch in, Done while still punched in, event older than the previous one, work date not matching the timestamp, or leave validation (`{errors:{field:message}}`) · `5xx` server problem.

Why the contract was adjusted: `GET /leave/balance` returns one number per leave type (the dashboard shows Casual and Sick separately, as in the designs), and `POST /attendance/events` carries a client-generated `eventId` and `workDate` so retries are safe and the server can compare them with its own calculation. Mock-only control endpoints (`/__scenario/<name>`, `/__config`, `/__reset`) are not part of the real contract.

## Event identity and idempotency

* Every tap creates **one** event with a UUID `eventId`, made once on the device and stored in SQLite *before* any network call.
* Retries resend the **same** `eventId`. The server keeps a table of processed `eventId`s and answers a repeat with the original result (`duplicate: true`) instead of creating another record.
* **Timeout where the server may have saved it**: the client cannot tell, so the event stays *Pending* and is retried with the same ID. The server dedupes → exactly one record. (Try `timeout_after_accept`.)
* **Double taps**: (1) a `busy` flag ignores taps while one is running; (2) the day state is re-checked before every save (a second Punch In while punched in is refused); (3) a partial unique index in SQLite allows only one non-rejected Done per work date.

## Sync rules (`services/sync_service.dart`)
* Pending events are sent **one at a time in creation order**.
* Network error / timeout / 5xx → stays *Pending*, the run stops (so a check-out never overtakes its check-in).
* 409 / 400 / 422 → *Rejected* with the server's reason; every later pending event of the same day is rejected too (the punches of a day depend on each other).
* Triggers: app start, **Sync Now**, pull-to-refresh, connectivity returning, the app coming back to the foreground, and right after each tap. Only one run at a time.
* Pending events are in SQLite, so they survive closing and reopening the app.

## What a production server must repeat
Device checks are for user experience only. The server must re-validate: the geofence (using its own office data), the event timestamp (plausible, not in the future, ideally server time as the source of truth), the company work date (computed server-side), one check-in per day, check-out after check-in, `eventId` idempotency, authentication/authorisation, and — for leave — dates, overlap and balance. Spoofed GPS cannot be detected on the device alone.

## Completed features
* Home (dashboard): gradient hero with greeting, name/ID/department, date, an always-visible Online/Offline/pending badge, today's status, a live worked-time ring (8 h target), check-in/out times and the Check In/Out button; Casual and Sick balances; latest 5 attendance records with "View all"; loading, empty, error and offline states.
* The company date is computed live in the company timezone, so "today" rolls over at midnight and the screens refresh when the app returns to the foreground.
* **Punch In / Punch Out any number of times a day**, with GPS, 200 m geofence, and permission handling (denied, permanently denied, GPS off, unavailable). Total worked time = sum of all sessions, live on the dashboard.
* **Done for today** (with a confirmation) ends the day; if still punched in it punches out first. **10 PM auto-done**: an unfinished day closes at 10:00 PM company time (an open session ends at 10 PM) and no new punch is allowed after that.
* **Short hours = leave**: a finished day under 8 h is labelled "Short hours · Leave"; 8 h or more is "Present". This is a label only; it does not change the leave balance.
* Reviewer tool Profile > Leave Approvals: approve or reject Pending leave (mock server), with calendar and balances following.
* Every day in history opens a detail sheet (all sessions, totals, how the day ended); every leave request opens a detail sheet too. The Attendance tab opens with a **monthly calendar**: green = present (P), red = leave (L: short hours, approved leave, or an absent weekday (A)), light red = weekly off (Sat/Sun), amber = leave waiting for approval, blue outline = today. Tap a day for its details; switch between this month and last month. Under it: present days, leave days and total hours of the shown month.
* Attendance History with All / Synced / Pending Sync / Rejected filters and **Sync Now**.
* Offline queue + automatic sync, cached dashboard/history/leave data.
* Leave: bottom-sheet form with all 5 local rules, server error display, list with Pending/Approved/Rejected (viewable offline; submitting needs a connection).
* Profile & Reviewer Simulator: office geofence, location simulator, mock API scenario, sync queue shortcut, light/dark/system theme.
* Leave form shows a live "N days requested · M available" summary.
* Tests: 72 (see below).

## Tests (`flutter test`)
* Check-out without check-in is rejected.
* Double tap and retry-after-timeout create no duplicate server record.
* Pending events survive closing/reopening the database and sync in order.
* Overlapping leave dates are rejected (rules + controller).
* Extras: geofence, permission denied, server outage ordering, 409 handling, leave rules, offline leave.
* Company-date rollover at midnight (a new day allows a new punch).
* Multiple punches: totals add up, Done closes the day (also offline, with ordered sync), a short day is leave.
* Profile screen (widget tests): the tools and their live status, and each popup (office values and bad-latitude error, location inside/outside feedback, scenario list, appearance choices).
* Leave review: a Pending request can be approved or rejected, a decided one cannot be changed, offline changes nothing.
* Calendar (`calendar_test`): present / short hours / weekend / absent / leave marks, month totals, month navigation limits.
* Day rules (`day_rules_test`): sessions, 8 h threshold, 10 PM auto-done, validation, merge of server and local punches.
* Widget tests: loading spinner, error + Retry, empty dashboard content, and Pending Sync on the dashboard.

## Assumptions and limitations
* One preconfigured employee, no login. Many sessions per day but no overnight shifts: a day always ends by 10 PM company time (fixed in code: `AttendanceRules.autoDoneHour` and the server's `autoDoneHour`). The 8 h target is also fixed in code. Calendar: Sat and Sun are weekly offs (fixed); a past weekday without punches after your first record counts as absent (leave); attendance data is loaded for the current and previous month only.
* Leave counts all calendar days. Each type (Casual/Sick) has its own balance; pending requests reserve days.
* A local check-in/out is allowed offline only if the profile was loaded once while online (needed for office and timezone).
* The connectivity plugin shows whether a network is up, not whether the API is reachable; API failures are the source of truth.
* No background sync while the app is terminated. No retry limit/backoff for repeated 5xx.
* Cleartext HTTP is enabled for the local mock server only (Android manifest); use HTTPS in production.
* The mock server stores data in memory.
* iOS is untested (project targets Android first).

## Time spent
_Fill in your actual hours here._

## AI disclosure
This project was planned and generated with the help of Claude (Anthropic) through Claude Code. The author is expected to review, be able to explain, and modify all code before submission.
