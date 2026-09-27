# Web / iOS alignment

Reviewed September 26, 2026 against `/Users/iver/Projects/amountly` at `e5b4f2b`.
The active Next.js dashboard routes, services, reporting helpers, tests, and current
Supabase migrations were the reference. The older web mock dashboard and iOS
changelog were not treated as the current product contract.

## Changes

| Area | Native behavior aligned with the web app |
| --- | --- |
| Overview | Real workspace records, received-payment revenue, outstanding balances, vendor bills, tracked hours, review links, financial search, monthly-close navigation. Totals explicitly separate currencies. |
| Authentication | Preserve the existing session work; avoid competing sign-in/session hydration and unnecessary token refresh. Inactive or inaccessible profiles are not treated as new accounts. |
| Records | Decode PostgreSQL timestamps and calendar dates consistently, preserve exact concurrency versions, paginate financial reads, support unassigned time, and retain archive semantics for clients/projects/expenses/vendors. |
| Invoices | Atomic draft creation, draft editing/deletion, versioned issuance/cancellation, current currency/tax/payment-term defaults, and frozen issued client/line details. |
| Payments | Record amount/date/method/reference against an invoice; derive balances from unreversed receipts. Append-only corrections and evidence-based historical Paid review replace direct status changes. |
| Time billing | Use the atomic reservation command. Business time requires approval; freelancers may invoice their own eligible draft/submitted/approved entries. Prevent reserved or projectless entries from selection. |
| Bills and purchasing | Separate personal bills from vendor bills, persist supported recurrence values, derive due status from calendar dates, use versioned payment/cancellation, and add vendor/purchase-order workflows. Freelancers can reach purchasing. |
| Review | Expense/time submission and independent approval, record history, and historical invoices awaiting payment evidence. |
| Receipts | Upload private, bounded, type-checked JPEG/PNG/WebP/PDF files and request short-lived signed links. No receipt access URLs in exports. |
| Tax Prep | Recorded income/expense totals, cash/accrual basis, fiscal period and currency selection, receipt/categorization checks, supported-year illustrative estimates, filing reminders, quarterly seeding, workspace CSV and tax-packet CSV. |
| Settings and exports | Persist shared workspace and notification preferences. Add payment/correction/vendor/purchasing exports, paginate beyond 500 rows, bound export size, neutralize spreadsheet formulas, and clean up temporary share files. |
| Invoice PDF | Use issued snapshots, correct currency/payment balances, wrapped text and multiple pages instead of a fixed single page. |

Commands use the shared server's authorization, validation, version checks, and
atomic workflows. New capture forms retain their original request ID and payload
for retries; a confirmed write is not repeated when a subsequent read fails.
No hosted backend migrations were applied. Current web migrations were applied
only to a disposable local Supabase stack for validation.

## Verification

- Final native integration run: **9 app-hosted XCTest tests passed** against
  isolated local Supabase, including real authenticated writes, partial and
  concurrent payments, corrections, issued snapshots, stale versions, response
  loss after commit, failed read after commit, duplicate taps, role/tenant denials,
  independent review, personal/vendor bills, purchasing, time reservations,
  private receipts with real signed-link expiry, 1,005-row pagination, CSV security,
  shared preferences, multi-page PDF content, session refresh/restore and sign-out, and login-form failure/recovery.
- **7 Swift rules tests passed** for money, fiscal boundaries, CSV escaping,
  supported tax years, dates, time eligibility and receipt validation.
- **48 web reference tests passed** across security, reporting, exports, capture,
  auth, PDF and calendar summaries. The disposable PostgreSQL security suite
  passed **11 scenario groups**.
- The full web local release suite passed against actual Supabase and a local
  production web build: RLS, concurrency, retries, legacy payments, purchasing,
  preferences, approvals, 1,005-row exports, expired sessions/disabled users,
  receipt isolation and actual 60-second URL expiry, authenticated CSV/PDF, CSP,
  and the safe unconfigured-AI response.
- In-app browser and iPhone 17 Pro simulator compared the same synthetic workspace:
  dashboard, invoices, payment corrections, expenses/review, vendor bills,
  purchase orders, Tax Prep and preferences. The fiscal report agreed on **100.00
  USD income, 99.00 USD expenses and 1.00 USD net**. Native CSV share preview loaded.
- UI inspection fixed invoice-card snapshot names, currency and fractional
  quantity display, long descriptions, the receipt-based paid date, correction
  reference/reason visibility, record history links, dashboard hours labels,
  payment-term choices, and the visible default-tax field label.
- Pre-commit security review removed raw authentication errors and personal
  signup/setup data from logs, and made unexpected login errors safe for display.
  The new login-form integration test verifies rejection, cleared loading state,
  and successful recovery with valid local credentials.
- Native request UUIDs are normalized to lowercase, matching returned database
  identifiers. The full native suite passed again with fresh fixtures afterward.
- Debug simulator and unsigned generic-iOS Release builds; `git diff --check`.
  There is no dedicated Swift lint configuration in this repository.

Reproduction instructions and safety boundaries are in
[IntegrationTests/README.md](IntegrationTests/README.md). Generated credentials,
fixtures, logs and result bundles remain outside Git. All mutation tests used
synthetic local accounts; no hosted financial records were changed.

## Verification limits and platform differences

- Native integration tests exercise the real Swift service/repository layer;
  they are not exhaustive automated taps through every SwiftUI form. The UI pass
  supplements these tests. Simulator coordinate/text input was unavailable, so
  an exhaustive form-entry pass could not be completed. Native session refresh/sign-out were tested; explicit
  expired-token rejection was covered by the real web/API suite.
- Physical-device camera/OCR and device file sharing still need a device pass.
  Release compilation is not an App Store archive or physical-device installation.
  Existing Vision concurrency and missing-AppIntents metadata warnings remain.
- The app retains native navigation, controls, date localization and capture/OCR.
  It does not reproduce the web AI interface or every web table control. Saved
  date-format preferences are shared; native dates still use device localization.
- Two reference-web display limitations were observed: the vendor-bill table
  renders a EUR bill with a dollar sign, and a saved custom 14-day payment term
  leaves the web selector blank. Native currency remains correct; its selector
  offers the web's standard terms while preserving a previously saved custom value.
  These web files were not modified.
- Native tax packets restrict filing reminders to the selected reporting period.
  Filing amounts remain USD, matching the web's existing filing-record convention;
  other currencies are never silently converted.
- Advanced accounting, payroll, inventory and team modules remain behind the
  existing product-scope gate.

## Keeping future changes consistent

When the web changes, compare the active route and service with its native
repository/model first, then check the newest migration or RPC signature. Check
status transitions, ownership, timestamps, currency, payment evidence, retries,
and export columns before adjusting presentation. Extend the native rules tests
for financial/security changes and compare both applications with the same
workspace. Do not apply the old migrations bundled in this iOS repository to the
shared backend as an automatic synchronization step.

Run native checks from this repository:

```sh
swift test --scratch-path /tmp/amountly-rules-build
xcodebuild -project alpha.xcodeproj -scheme alpha \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug build
xcodebuild -project alpha.xcodeproj -scheme alpha \
  -destination 'generic/platform=iOS' \
  -configuration Release CODE_SIGNING_ALLOWED=NO build
git diff --check
```

Existing local authentication edits were preserved and extended. The alignment
changes and verification harness are prepared together for the main-branch commit. The web source files were left unchanged. Temporary web/proxy processes and
the isolated Supabase stack were stopped after verification; disposable database
volumes and private test artifacts remain available locally for reproduction.
