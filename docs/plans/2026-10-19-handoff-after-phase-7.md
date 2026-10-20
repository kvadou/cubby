# Handoff after phase 7

## Done
- **API: parent accounts.**
  - `guardianships`, one family per parent account for now.
  - `family_messages`, delivered in the same transaction as a director's approval, with a fixed subject.
  - Family endpoints under `/api/v1/family`, scoped to the signed-in parent; `me` lists their families.
  - The web app tells a parent to use the phone app.
  - An independent security review found no HIGH issue; its MEDIUM and LOW findings are fixed (see the record).
- **iOS app (`ios/`).**
  - SwiftUI with sign in, plus the Today, Messages and Billing tabs.
  - The token is kept in the Keychain; sign out revokes it.
  - Every tab has loading, empty, error and offline states.
  - Dynamic Type stacks rows at accessibility sizes. Light and dark mode both checked.
- **Tests:** 190 API specs. On the iOS 26.5 simulator, 5 Swift Testing client tests and an XCUITest flow with screenshots, at default text in light and dark and at accessibility-large text.
- **Records:**
  - Research: `docs/prior-art/2026-10-19-phase7-ios.md`, O1 to O5 closed; the lint passes.
  - Plan: `docs/plans/2026-10-19-phase7-plan.md`.

## Machine notes
- **Xcode 27.1 setup.** It needed `xcodebuild -runFirstLaunch` (CoreSimulator was out of date). The iOS 26.5 runtime had no devices, so I created "Cubby iPhone".
- **Signing.** Test bundles need local ad-hoc signing (`CODE_SIGN_IDENTITY: "-"`). A device build needs an Apple team id in `project.yml`.
- **Large-text UI run:** `TEST_RUNNER_CUBBY_UI_TEXT_SIZE=UICTContentSizeCategoryAccessibilityL`.

## Demo logins (local)
- Director: `renee@littleoaks.test`.
- Parent: `parent@littleoaks.test` (Russel family, child Meryl).
- Password: the local demo value in `api/db/seeds/demo_users.rb`.
- On a deployed cluster, the password is generated: `terraform -chdir=infra/terraform/cluster output -raw demo_password`.

## Still open
- **Bedrock access** (phase 4).
- **Parents:**
  - Several families per parent.
  - Push notifications, which need an Apple developer account.
  - Replies and payments.
  - Daily reports and photos, which have no data model.
- **The deployed demo doesn't include phase 7 yet.** `make up` rebuilds from main, which now carries it.

## Next: phase 8
Android parent app (Kotlin, Jetpack Compose) against the same family endpoints. It needs a JDK and Android Studio installed, which are multi-GB.
