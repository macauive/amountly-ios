# Native local integration checks

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
     -x studio,inbucket,logflare,vector,supavisor,postgres-meta,edge-runtime,realtime,imgproxy
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
