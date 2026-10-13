# Amountly App Store release preparation

Amountly is being prepared for publication under Mac Digital with bundle ID
`macdigital.amountly`, version 1.0, build 1. Apple Developer enrollment is
planned for November 1, 2026; the reminder is scheduled for 9:00 AM Central.
The current Xcode signing team is a development setting and must be replaced
with the enrolled publishing team if different.

## App changes

- Privacy, terms, and support links are available on login, signup, and settings.
  About Amountly identifies Mac Digital and displays the installed version.
- Settings → Delete Account submits an authenticated request for the account
  and associated personal data. The user sees the confirmed 30-day completion
  window, required-retention caveat, and confirmation that the request was
  recorded. No separate support email is required. The existing server queues
  the request; it does not immediately delete the account.
- Optional AI requires explicit permission for the current session. Text
  capture, receipt files, invoice reminders, and dashboard insights are covered.
  The production transport rejects every AI request before network access
  without permission and rejects responses after withdrawal. Consent remains
  in memory and resets on logout, account switch, and process exit.
- The receipt scanner has a camera usage description. Receipt attachments and
  manual bookkeeping remain usable without AI permission.
- Unfinished notification preferences, tax estimates/documents, integrations,
  and offline-data destinations are hidden. The existing Tax Dashboard remains.
- The app includes a privacy manifest. Required-reason declarations cover
  app-only appearance preferences and metadata for app-owned or selected files.
  The existing light and dark icons are opaque 1024 × 1024 images.

## Draft store listing

Name: Amountly

Subtitle: Invoices, expenses & receipts

Suggested category: Business

Keywords: invoice,expenses,receipts,bookkeeping,freelancer,clients,time tracking,business

Description:

Keep client invoices, expenses, receipts, and bookkeeping records together
with Amountly by Mac Digital.

Create invoices, record payments, track project time, and organize client and
vendor information. Capture expenses and attach receipt originals, then review
your recorded income and expenses and share available exports.

Optional AI helps interpret receipt files and text, draft invoice reminders,
and summarize selected records. You choose whether to share data with OpenAI
for these features. Review suggestions before applying them, or enter your
records manually.

Sign in to your Amountly account to use the app. Available workflows depend on
your account type and workspace permissions. Amountly records bookkeeping
information; it does not transfer money or file taxes.

Support URL: https://amountly.app/support

Privacy policy URL: https://amountly.app/privacy

Terms URL: https://amountly.app/terms

## Draft review instructions

Provide a dedicated verified demo account with fictional records in App Store
Connect's review credentials fields. Keep its password out of Git and this
document. Ensure the account can exercise the features included in screenshots.

Sign in with the supplied account. Open Expenses to enter an expense or select
a receipt. Optional AI is disabled until the user selects Allow AI for this
session after reading the disclosure. Suggestions are previews until Apply.
Invoice reminders are editable drafts and are shared only by user action.
Settings provides privacy, support, AI controls, and account deletion.
Account deletion requests are fulfilled by Mac Digital within 30 days, with
completion confirmed by email; required legal retention and backup retention
are explained during processing.

## Privacy disclosure preparation

These categories reflect the current app and manifest. The account owner must
review the final privacy answers against the production service and SDK report
before submitting them in App Store Connect.

| Data | Purpose | Linked to account | Tracking |
| --- | --- | --- | --- |
| Name and email address | Authentication and account functionality | Yes | No |
| User ID | Authentication and record authorization | Yes | No |
| Other financial information | Invoices, expenses, payments, and reports | Yes | No |
| Photos and videos | Receipt images selected or captured by the user | Yes | No |
| Other user content | Documents, descriptions, and bookkeeping input | Yes | No |

Optional AI sends the input and selected record details needed for a feature to
OpenAI through Amountly. Receipt-file extraction sends the selected original.
ChatGPT linking has a separate browser consent flow and can be managed through
the existing website. Do not declare that no data is collected or shared.

## Additional verification on October 13, 2026

The release preparation and new web-parity changes were verified together.
All three release-readiness UI cases passed again on iPhone 17 Pro and iPad Pro
13-inch (M5), iOS 26.5 (six executions). The current package and offline suites
passed 41 and 20 tests respectively. Hosted synthetic tests additionally cover
two-session capture recovery/conflicts, native resume/review/save/search/original
inspection, and native keep/resume/cancel/discard without creating an expense.
Prepared sessions and temporary QA run files were cleaned up.

The final unsigned Release archive passed at
`/private/tmp/Amountly-oct13-tested.xcarchive`. Its app identity, camera disclosure
and privacy manifest were verified; Debug fixtures and test plug-ins are absent.
Physical-camera capture, device share destinations, actual deletion fulfillment
and App Store signing/submission remain release checks. No submission occurred.
See `WEB_IOS_ALIGNMENT.md` for the parity checks and their limits.

## Verification on October 7, 2026

- 35 Swift package tests passed, including consent, session ownership, stale AI
  responses, deletion authentication, and strict deletion-confirmation handling.
- 13 offline simulator integration tests passed. No live account credentials or
  hosted AI requests were used in these runs.
- All three release-readiness UI cases passed on iPhone 17 Pro and iPad Pro
  13-inch (M5), iOS 26.5. They cover settings, explicit AI consent/withdrawal,
  relaunch reset, deletion cancellation, and a synthetic request confirmation.
  The iPhone settings case also passed after the test's scrolling adjustment.
- Privacy, terms, and support pages were checked in the in-app browser. The
  hosted deletion endpoint rejected an unauthenticated request with HTTP 401.
- The app privacy manifest passed plist validation; both icon variants are
  opaque 1024 × 1024 images. `git diff --check` passed.
- The final unsigned Release archive passed with Xcode 26.5/iPhoneOS 26.5. Its
  installed app has bundle ID `macdigital.amountly`, display name Amountly,
  version 1.0/build 1, the camera description, and the app privacy manifest.
  The synthetic UI fixture is absent from the Release binary. The archive is
  local at `/private/tmp/Amountly-macdigital.xcarchive`; it is not signed or
  eligible for upload until the publishing account is configured.

Physical-camera capture and actual deletion fulfillment have not been verified
in this preparation. A simulator's synthetic deletion response proves the
native request/confirmation flow, not the production deletion operation.

## Required before submission

1. Enroll in the Apple Developer Program. To display Mac Digital as the App
   Store seller, use organization enrollment for the eligible legal entity;
   setting a bundle ID does not change an individual account's seller name.
   Register `macdigital.amountly`, select the publishing team in Xcode, and
   create the App Store Connect record.
2. Establish daily handling of the existing deletion-request queue. Fulfill
   requests within the agreed 30-day window, explain required retention, and
   confirm completion. Test actual deletion and confirmation using a disposable
   account before submission. A request-confirmation screen alone is not proof
   of completed deletion.
3. Test on a physical iPhone: camera capture, permission denial/recovery, signup
   email delivery, password reset, saving/editing records, AI, attachments,
   downloads, and sharing. Verify representative workflows on iPad because
   both device families are enabled. The minimum OS is currently iOS 26.1.
4. Capture store screenshots of working invoice, expense/receipt, time, and
   overview screens with fictional data at Apple's required iPhone and iPad
   sizes. Release QA screenshots of settings/consent/deletion are inspection
   evidence and are not a complete store screenshot set.
5. Review the final archive's privacy report, SDK declarations, and encryption
   usage. Complete age rating, export compliance, privacy, pricing, regions,
   applicable trader information, and review contact fields truthfully.
6. Finalize the commercial model before introducing paid app features. Digital
   upgrades may require in-app purchase; a qualifying free companion to a paid
   web service can use Apple's exception. No native purchase system is included
   in this preparation.
7. Produce a signed App Store archive with the publishing team, validate it,
   upload, and test with TestFlight. Submit the selected build for review and
   choose manual release if launch timing should stay under owner control.

## Apple references

- [Enrollment and organization requirements](https://developer.apple.com/programs/enroll/)
- [Account deletion requirements](https://developer.apple.com/support/offering-account-deletion-in-your-app/)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
- [Privacy manifests](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)
- [Required reason APIs](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)
