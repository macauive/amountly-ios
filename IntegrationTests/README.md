# Native verification

## Current Render alignment (October 7, 2026)

Production uses the web's cookie-authenticated Render APIs. The loopback Supabase
instructions below remain a legacy database-workflow harness; they do not prove
current Render auth, receipt-file AI or accountant ZIP behavior.

For current offline verification, build the simulator test target, then run only
the explicitly mocked tests. This runner disables app restoration and live tests,
removes QA/local credential overrides, and deletes its temporary `.xctestrun`.

```sh
swift test --scratch-path /private/tmp/amountly-alignment-rules
xcodebuild -project alpha.xcodeproj -scheme AmountlyIntegration \
  -destination 'platform=iOS Simulator,id=SIMULATOR_UUID' \
  -derivedDataPath /private/tmp/amountly-alignment-build build-for-testing
python3 scripts/run-offline-tests.py \
  --products /private/tmp/amountly-alignment-build/Build/Products \
  --device SIMULATOR_UUID
```

Use an available arm64 simulator ID from `xcrun simctl list devices available`.
The Swift suites cover 29 tests and the hosted runner selects thirteen tests. The
hosted tests do not write financial records or call a model provider.

The existing `AIParityTests/testLiveSharedAIService` now uses an isolated
in-memory Render cookie session. `RenderLiveSmokeTests` checks protected reads,
one synthetic receipt-file extraction and accountant packet authorization. An
active standalone freelancer must receive ZIP bytes; other account types must
receive 403. The designated QA business account verified denial.
They require `AMOUNTLY_AI_LIVE_TESTING=1` and QA credentials provided locally via
`AMOUNTLY_AI_QA_EMAIL` / `AMOUNTLY_AI_QA_PASSWORD`. **Do not run them without explicit
authorization for hosted QA sign-in, protected record reads, synthetic AI uploads
and packet downloads.** Do not place credentials in shell history, source,
tracked configuration or logs. The two live checks passed during this refresh
after explicit user authorization. `testPrepareManualQAUI` additionally requires
`AMOUNTLY_QA_UI=prepare`; it persists the normal cookie only in the simulator
Keychain for inspection. Always finish with `AMOUNTLY_QA_UI=cleanup` and only
`testCleanUpManualQAUI`, which signs that hosted session out.

A third explicit hosted check, `testLiveFreelancerSetupReceiptAndPacket`,
requires `AMOUNTLY_SYNTHETIC_FREELANCER_TESTING=1`, the dedicated QA email/password
and `AMOUNTLY_FREELANCER_QA_ID`. It refuses an identity mismatch and creates only
synthetic expenses in the new freelancer account. It exercises the native
profile contract, private upload, saved review marker, original byte match and
an authorized ZIP. On this refresh the ZIP's record, Reviewed index, original
bytes and SHA-256 matched. The account has a unique password stored outside Git;
existing QA accounts and their roles were preserved. This fixture was provisioned
administratively, so it does not prove signup-email delivery.

The browser-managed ChatGPT connection has a native Settings link. The local
receipt XCUITest passed Files selection, Quick Look presentation/dismissal,
manual draft save, Mark/Clear reviewed and a corrected amount resetting review.
Its oracle reads the real local database and checks exactly one saved record.
After preparing the loopback stack below, reproduce it with:

```sh
python3 scripts/run-integration-tests.py \
  --fixtures /private/tmp/amountly-ios-fixtures.json \
  --products /private/tmp/amountly-alignment-build/Build/Products \
  --device SIMULATOR_UUID --prepare-receipt-ui
xcodebuild -project alpha.xcodeproj -scheme AmountlyUI \
  -destination 'platform=iOS Simulator,id=SIMULATOR_UUID' \
  -derivedDataPath /private/tmp/amountly-alignment-ui-build build-for-testing
python3 scripts/run-ui-tests.py \
  --fixtures /private/tmp/amountly-ios-fixtures.json \
  --products /private/tmp/amountly-alignment-ui-build/Build/Products \
  --device SIMULATOR_UUID
python3 scripts/run-integration-tests.py \
  --fixtures /private/tmp/amountly-ios-fixtures.json \
  --products /private/tmp/amountly-alignment-build/Build/Products \
  --device SIMULATOR_UUID --cleanup-receipt-ui
```

Open Files once to initialize its local container. The UI runner copies only the
generated synthetic PNG into Files, removes that copy afterward and deletes its
private run configuration. Hosted share verification uses `HostedShareUITests`
with `AMOUNTLY_SYNTHETIC_SHARE_TESTING=1` after an explicitly prepared dedicated
freelancer session. This check passed for the downloaded private receipt and
accountant ZIP, opening Files destinations and cancelling before saving or
sending. Finish by signing the prepared native session out. Physical camera
capture still requires a connected, unlocked device. Loopback native sessions
are blocked from hosted AI/receipt extraction/accountant downloads, so they
cannot borrow a previously saved Render cookie.

## Legacy local integration checks

These are app-hosted XCTest tests calling the real Swift repositories against a
**disposable loopback Supabase stack**. They do not click through every SwiftUI
form. Use the in-app browser and iOS Simulator for the complementary UI pass.
Never substitute a hosted URL or production credentials.

Prerequisites: Xcode with an iOS simulator, Docker, Supabase CLI, Node, Python 3,
and the web checkout's installed dependencies. The web checkout's migrations
are authoritative; do not use the legacy migrations in this iOS repository.

1. Create a fresh directory outside both repositories. Copy the web checkout's
   `supabase/config.toml` and `supabase/migrations` into its `supabase` directory.
   Set `project_id = "amountly-ios-validation"` and disable configured seed files
   (`[db.seed] sql_paths = []`). Check ports 54321–54329 are free. Do not reset an
   existing local project to make room.
2. Start that isolated project:

   ```sh
   supabase start --workdir /private/tmp/amountly-ios-validation \
     -x studio,mailpit,logflare,vector,supavisor,postgres-meta,edge-runtime,realtime,imgproxy
   ```

   CLI status/start output contains local credentials; keep it private.
3. Generate new fixtures before each full run. The generator creates eight
   synthetic actors, projects, approved/draft time, and 1,005 partially paid
   invoices. It never reads hosted environment files. The fixture file contains
   random local test passwords and must stay outside Git with mode 0600.

   ```sh
   node scripts/prepare-local-tests.cjs /Users/iver/Projects/amountly \
     /private/tmp/amountly-ios-validation /private/tmp/amountly-ios-fixtures.json
   node scripts/local-fault-proxy.cjs
   ```

   Keep the proxy running in a separate terminal. It binds loopback port 54331
   and forwards only to port 54321. Faults simulate a committed write whose
   response is lost, a failed read after that write, and overlapping taps.
4. Find the intended simulator with `xcrun simctl list devices available`, then
   replace `SIMULATOR_UUID` below:

   ```sh
   xcodebuild -project alpha.xcodeproj -scheme AmountlyIntegration \
     -destination 'platform=iOS Simulator,id=SIMULATOR_UUID' \
     -derivedDataPath /tmp/amountly-ios-build build-for-testing
   python3 scripts/run-integration-tests.py \
     --fixtures /private/tmp/amountly-ios-fixtures.json --device SIMULATOR_UUID
   ```

   The runner injects the fixture into a temporary mode-0600 `.xctestrun`, removes
   that file when finished, and writes a private log and `.xcresult` under `/tmp`.
   Treat those result bundles as local test artifacts. `--only` accepts an XCTest
   test identifier. Test methods execute serially; full runs require fresh actors.
   Without the local flags these integration tests skip. The normal `alpha`
   scheme remains available for running, profiling, analyzing, and archiving.
5. For a web/native comparison, build and start the web app using the same fixture:

   ```sh
   node scripts/run-local-web.cjs /Users/iver/Projects/amountly \
     /private/tmp/amountly-ios-fixtures.json build
   node scripts/run-local-web.cjs /Users/iver/Projects/amountly \
     /private/tmp/amountly-ios-fixtures.json start
   ```

   Open `http://127.0.0.1:4174` in the in-app browser. Use the synthetic owner from
   the private fixture file. The test runner leaves that owner signed into the
   native app's separate local-test keychain. Launch the Debug app with
   `AMOUNTLY_LOCAL_TESTING=1`, `AMOUNTLY_LOCAL_URL=http://127.0.0.1:54331`, and the
   fixture's `AMOUNTLY_LOCAL_ANON_KEY`, but **without** `AMOUNTLY_XCTEST` for UI use.
   With `simctl launch`, these variables use the `SIMCTL_CHILD_` prefix. Load the
   key programmatically, not as a command-line literal. This configuration is
   compiled out of Release builds. Web overrides are process-local; `.env` files
   are not changed, although `.next` is rebuilt for the local backend.
6. Stop the proxy/web processes when finished and run
   `supabase stop --workdir /private/tmp/amountly-ios-validation`. This preserves
   disposable stack volumes and does not stop unrelated Docker services.

Coverage includes invoice edits/issuance/snapshots, optimistic concurrency,
partial/concurrent payments, corrections, retry identities, duplicate taps,
role and tenant denials, independent approval, personal/vendor bills, purchasing,
time reservation/release, private receipts with real URL expiry, paginated CSV,
spreadsheet injection, shared preferences, multi-page PDF content, session
refresh/restoration, disabled profiles, sign-out, and login-form failure/recovery.


## AI parity checks (September 30, 2026)

The current AI contract/client regression suite replaces the original heuristic
parser probes. No backend or API key is needed:

```sh
swift test --scratch-path /tmp/amountly-ai-rules-build
python3 scripts/verify-smart-capture.py
```

App-hosted `AIParityTests` exercise native time-form application, bounded dashboard
summaries and Vision OCR. Build the `AmountlyIntegration` scheme for the chosen
simulator, then run:

```sh
xcodebuild -project alpha.xcodeproj -scheme AmountlyIntegration \
  -destination 'platform=iOS Simulator,id=SIMULATOR_UUID' \
  -derivedDataPath /tmp/amountly-ai-verification-build build-for-testing
python3 scripts/run-ai-tests.py --device SIMULATOR_UUID
```

`--live` separately opts into eight synthetic requests covering all seven active
web tasks (two time examples), against the production shared AI service. It
requires the designated QA login in `AMOUNTLY_AI_QA_EMAIL` and
`AMOUNTLY_AI_QA_PASSWORD` environment variables. Do not put credentials in command
arguments, checked-in files, screenshots or chat. The runner writes a temporary
mode-0600 xctestrun and removes it afterward. The test uses a separate SDK session
storage key, signs that session out afterward, and never creates financial records
or sends reminders. The provider calls consume the QA account's AI quota. Do not
use a personal customer's login as a substitute.

`--inspect-ui` runs a separate, 55-second XCTest-only screen for computer-use
inspection of the real shared SwiftUI capture component. Its network responses
are synthetic and intercepted in the test target; no UI-testing bypass or mock
code is compiled into the app target. The inspection verified Get suggestion →
reviewed preview → Apply suggestion, including that form values stayed unchanged
until Apply. This is representative component UI coverage, not an exhaustive tap
through every financial form.

Physical-device camera capture and device share destinations still need a device
pass. Synthetic-image Vision OCR is tested in the simulator. Live AI checks prove
the current shared endpoint works for the supplied cases, not that every possible
natural-language input is interpreted correctly. All generated fields remain
editable and require review before saving.

## Precommit follow-up — September 30, 2026

The existing local suite passed again: eight financial-workflow tests, one
configuration test, and three offline AI tests (12 passed; the opt-in live AI and
component inspection tests were skipped). Debug/test and unsigned Release builds
passed after adding an optional SwiftUI environment client for form inspection.
Only the test target contains mock responses.

The real expense and contact forms were exercised with computer use against a
fresh disposable stack. Expense capture showed a safe 503 error, recovered on
explicit retry, kept fields unchanged until Apply, then saved the expected 37.45
amount, merchant and category. A pending contact request was dismissed; reopening
showed an empty form. A new suggestion populated company, contact and email, and
those values were saved and verified through the real repositories.

The invoice form showed a reviewed 2 × 75 = 150 suggestion, preserved its blank
line before Apply, and updated the editable line/total afterward. Its final Create
click could not be completed: the computer-use tool repeatedly returned
`noWindowsAvailable` for coordinate clicks, while accessibility reads/actions
still worked. The invoice was dismissed without saving. Consequently the opt-in
form inspection test **failed its missing-invoice assertion**; it is not a full
end-to-end pass. Expense/contact persistence assertions passed before that
failure. Repeat the invoice UI save check before calling this form pass complete.

To reproduce the opt-in form pass after building, with the proxy running and
fresh local fixtures:

```sh
python3 scripts/run-integration-tests.py --inspect-ai-forms \
  --fixtures /private/tmp/amountly-ios-fixtures.json \
  --products /tmp/amountly-ai-verification-build/Build/Products \
  --device SIMULATOR_UUID
```

The screen waits up to 15 minutes for computer-use/manual actions. Use Fail once
for the expense form, request twice, apply and save. Use Slow for the contact form,
request then dismiss while generating. Switch to Success, reopen contact, request,
apply and save. Finally create an invoice for AI Form Verification Studio using
the suggested line, then tap Finish verification. The XCTest checks the three
saved records and failure/cancellation counters. These are local synthetic writes
only; the opt-in run never calls the hosted AI endpoint. Physical camera capture
and device share destinations remain outside simulator coverage.
