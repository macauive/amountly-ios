# Web / iOS alignment

Reviewed September 26, 2026 against `/Users/iver/Projects/amountly` at `e5b4f2b`.
The active Next.js dashboard routes, services, reporting helpers, tests, and current
Supabase migrations were the reference. The older web mock dashboard and iOS
changelog were not treated as the current product contract.

## Current AI implementation — September 30, 2026

The seven active web AI tasks now use the same authenticated `https://amountly.app/api/ai`
service from native SwiftUI. OpenAI keys and model selection remain on the web
server. No web deployment, database migration, new key, or production financial
write was needed.

| Task | Native entry points |
| --- | --- |
| Expense capture and categorization | New/edit expense → Smart expense capture. |
| Receipt/document extraction | New/edit expense → Receipt/document extraction; paste receipt text, or scan camera pages into the text field before requesting extraction. File attachment remains a separate action, matching the web's attachment/text distinction. |
| Invoice/bill line capture | Create Invoice, Edit Draft, and New Vendor Bill. AI line insertion respects line limits and existing time-invoice restrictions. |
| Invoice reminders | Sent/overdue invoice with a positive balance → Draft Payment Reminder → editable draft → explicit copy/share. Uses the outstanding balance and issued client name. No automatic sending. |
| Time capture | Quick Entry and new/edit Time Entry. Exact minutes are retained; explicit time ranges are retained; estimated blocks and next-day endings are visible and editable. Missing duration cannot create a saveable invented hour. |
| Contact capture | Add/edit client → Smart contact capture. |
| Dashboard insights | Overview → AI insights: suggested next steps, monthly narrative/highlights, and AI search results. Existing financial totals and search remain available on AI failure. |

Capture results are previews until the user taps Apply suggestion. Requests are
cancelled on sheet dismissal/replacement. Errors do not change form fields;
retries are explicit. Account changes discard pending responses and previews.
Dashboard requests debounce for 750 ms and use stable request keys. Only approved
summary fields, a bounded sample of the selected currency's loaded records, and
permitted native destinations are sent. The sample is labeled; it is not a
replacement for the accounting totals.

The old expense, time, contact and duplicate receipt-amount parsers have been
removed, eliminating their unchecked duration conversion and monetary guesses.
Receipt scanning now performs on-device Vision OCR only, with up to ten pages
and a 12,000-character limit; the shared service interprets the extracted text.

Security: requests use the current refreshed Supabase bearer session, ephemeral
network storage, no cookies/cache, a fixed HTTPS endpoint, and no redirect
following. Input size/shape and response size, schemas, money, dates, durations,
and destinations are validated. Server failures become safe local messages.
Existing server authorization, quotas, redaction and model-output validation
remain in force. No provider keys or raw responses are logged or embedded.
Session API behavior was checked against the
[Supabase Swift documentation](https://supabase.com/docs/reference/swift/auth-getsession).

Intentional exclusions: `time_invoice_draft` has no active web UI caller, and the
financial-review agent is an explicitly gated local synthetic preview. Neither
is presented as a shipped mobile feature. Normal time-to-invoice billing remains
available without AI generation. Purchase-order line capture was not added
because the active web AI entry point is vendor bills, not purchase orders.

Verification completed on September 30:

- **13 AI contract/HTTP tests and 7 existing rules tests passed** (20 unit tests).
- **4 app-hosted tests passed**: exact time-form application, dashboard summaries,
  synthetic-image Vision OCR, and live shared-service requests.
- **Eight live synthetic requests passed**, covering all seven active tasks and
  both mixed-duration and trailing-meridiem time inputs. The amount, receipt total,
  line arithmetic, duration and labeled-contact examples were checked against
  expected values. QA signed in through a separate SDK session and signed out
  afterward; no financial records or outbound messages were created.
- **47 web reference tests passed** for security, capture retries, calendar
  summaries and financial-review contracts.
- The in-simulator shared SwiftUI component was inspected with computer use:
  Get suggestion displayed a preview while preserving the form; Apply suggestion
  updated it to the expected description and amount.
- Debug simulator/test build and unsigned Release device build **passed**.
  The existing missing-AppIntents-metadata warning remains; the old Vision
  sendability warnings disappeared with the OCR refactor.
- `git diff --check`, Python runner syntax and a credential-pattern scan passed.

Precommit follow-up: the fresh loopback suite passed 12 checks (eight financial
workflows, configuration, and three offline AI checks). Real expense and contact
forms passed preview/application and local persistence checks, including expense
503/retry recovery and dismissal/reopening of a pending contact request. Invoice
preview/application produced the expected 150 total, but the computer-use tool
could not click Create (`noWindowsAvailable`). The optional form inspection test
therefore failed its missing-invoice assertion; the final invoice UI save remains
unverified. This is a tool-blocked UI gap, not a passing end-to-end form test.
Debug/test and unsigned Release builds passed after the inspection setup change.

Physical-device camera capture and share destinations still require a device
pass. This is not an App Store archive or exhaustive UI automation of every form.
Suggestions remain editable because successful synthetic examples cannot prove
correct interpretation of every future input.

Verification and reproduction are in `IntegrationTests/README.md`. The historical
audit below preserves the original failing examples; it describes the app before
these changes, not the current implementation.

## AI verification before remediation — September 29–30, 2026

**Result at the initial audit: AI parity was not implemented, and the existing native capture parsers
have reproducible correctness and input-safety failures.** Compared iOS
`3c5c06c` with the current web checkout at `1609b6a`. The earlier workflow
verification below must not be interpreted as verification of web AI on iOS.

### Feature inventory

The web declares eight tasks in `src/lib/ai/contracts.ts`. Its active pages call
seven of them through the authenticated `/api/ai` client. No native caller for
that endpoint or equivalent model integration was found in the Swift source.

| Web AI feature | Current native implementation | Result |
| --- | --- | --- |
| Expense text capture and categorization (`expense_capture`) | Synchronous `ExpenseCaptureParser` in `ExpenseView.swift`; keyword categories, regex amounts/dates, no model or confidence value. | Partial local substitute; failing probes. |
| Receipt/document text extraction (`receipt_capture`) | Vision camera OCR followed by `ReceiptScanner` heuristics; attaching a receipt file does not invoke the web extraction task. | Different implementation; receipt text parsing fails some probes. Camera/OCR not verified in this run. |
| Invoice and bill line capture (`invoice_line`) | Manual native line forms. | AI capture missing on both native surfaces. |
| Invoice reminder drafting (`invoice_reminder`) | No native AI subject/body/tone generation found. | Missing. |
| Time capture (`time_entry`) | `TimeCaptureParser` used by the time form and quick entry. | Partial local substitute; wrong durations and overflow crash reproduced. |
| Client/contact capture (`contact_capture`) | `ContactCaptureParser` in the contact form. | Partial local substitute; labels lose their meaning when lines are reordered. |
| Dashboard suggestions, monthly narrative, and search (`dashboard_insights`) | Native totals, fixed prompts and substring search in `HomeView.swift`. | AI insights missing; deterministic dashboard functionality remains present. |
| Time-to-invoice AI drafting (`time_invoice_draft`) | Native time billing exists without AI prose generation. | Web task/helper exists, but no active web UI caller was found; not counted as a confirmed active web feature. |

The web also contains a separate financial-review agent preview under
`/api/financial-review/agent`. It is explicitly limited to enabled local
synthetic mode, not customer-data execution. No native counterpart was found;
this is not classified as a production web feature. The standalone category
suggestion helper likewise has no active caller; categorization is used through
expense capture instead.

### Reproduced native failures

`python3 scripts/verify-smart-capture.py` compiles the current parser source
extracted from the app into a temporary Foundation executable. It does not
reimplement the algorithms or modify production source. The receipt text parser
is exposed only in that temporary executable. Results: **10 of 22 checks passed,
12 checks failed, and a separate oversized-duration process crashed (SIGTRAP).**

| Synthetic input / expectation | Observed native result |
| --- | --- |
| `$1,234.56` | `1.00` |
| Item `$10.00`, tax `$0.80`, total `$10.80` | Captures `10.00`, the first dollar amount. |
| `Adapter $20` | Marketing category because `ad` matches a substring. |
| `2026-02-31` | Produces a date instead of rejecting an impossible date. |
| `1 hour 30 minutes` | 60 minutes. |
| `1 to 3 pm` | 840 minutes (14 hours). |
| Work note without any duration | Invents 60 minutes and reports a duration was found. |
| `25 hours` | Exceeds the web task's maximum of 1,440 minutes. |
| `Contact: Alex Example` before `Company: Demo Studio` | Company and person are reversed (two failing assertions). |
| Receipt total `$10.80`, followed by `TOTAL SAVINGS $2.00` | Captures `2.00`. |
| `Apple Store`, `Laptop $999.00` | Software category instead of hardware. |
| Very large numeric hours pasted into the time parser | Unchecked `Double` to `Int` conversion traps; the separate probe process exits with signal 5. |

The crashing conversion is in `TimeEntryFormSheet.swift` at
`Int((value * 60).rounded())`. Both native smart-time entry points call it before
their normal save validation. These probes test parser results, not persisted
financial records. No financial records were created or changed.

### Checks and limits

- Existing native Swift rules suite: **7 passed**.
- Web security, capture retry, calendar summary, financial-review and agent
  contract suites: **47 passed**. These use mocked provider responses; they do
  not prove successful live model generation or every task's output quality.
- Native Debug simulator build: **passed**. Existing Vision sendability and
  unused-variable warnings remain.
- Native unsigned Release device build: **passed**; this is compilation, not a
  physical-device installation or App Store archive.
- `git diff --check` and Python probe-script syntax validation: **passed**.
- No authenticated live AI requests, browser form tests, simulator UI flows,
  physical-device camera/OCR, or network failure/retry UI checks were performed
  in this verification. Native end-to-end AI parity cannot pass while its model
  integration and several feature entry points are absent.
- This pass adds the reproducible probe script and this report only. App
  behavior is unchanged; failures are intentionally left visible for remediation.

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
