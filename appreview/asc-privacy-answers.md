# App Store Connect privacy answers

Written for: Anj, to fill in App Store Connect → App Privacy by hand.

These must match `ios/Runner/PrivacyInfo.xcprivacy`, line for line. A mismatch
between the manifest and the questionnaire is itself a flag, and it is one of
the easiest things for a reviewer to check mechanically.

Path: **App Store Connect → your app → App Privacy → Edit**.

---

## 1. Data collection

> Do you or your third-party partners collect data from this app?

**Yes.**

---

## 2. Which data types

Tick exactly these seven. For every one of them the follow-up answers are the
same, which is what makes this quick:

- **Used for Tracking:** No
- **Linked to the User's Identity:** Yes
- **Purpose:** App Functionality (only)

| Section in ASC | Data type | Why it is collected |
|---|---|---|
| Contact Info | **Email Address** | Google or Apple sign-in |
| Contact Info | **Name** | Display name on the profile and on posts |
| Identifiers | **User ID** | The account every other row hangs off |
| User Content | **Photos or Videos** | Avatars, and pictures attached to a post |
| User Content | **Other User Content** | Coach messages, posts, comments, notes, tasks |
| User Content | **Audio Data** | Voice notes, and body doubling audio |
| Health & Fitness | **Health** | Mood and energy tracking |

**Health is the one not to skip.** A record of how somebody's mental health is
going is health data. Filing it under "Usage Data" would understate it, and it
is the category a reviewer of a mental-health app will look for.

---

## 3. Do NOT tick these

Each of these has a specific reason to be absent. If you tick one, the manifest
and the questionnaire disagree.

| Do not tick | Why |
|---|---|
| **Precise Location** / **Coarse Location** | The app resolves a town name with `LocationAccuracy.low`, sends the coordinates only to Apple's own geocoder, and uses the result solely to render "for your day in \<town\>". It never enters a request to our server. Under Apple's definition of collect, that is not collected. |
| **Contacts** | Mail is read over IMAP on the device. No address book is uploaded. |
| **Usage Data**, **Product Interaction**, **Advertising Data** | No analytics, ads or attribution SDK exists in the project. |
| **Diagnostics**, **Crash Data**, **Performance Data** | No crash or performance SDK exists in the project. |
| **Purchase History** | Stripe holds this, and the app does not send it to us as a user data type. Revisit this if you add In-App Purchase. |
| **Sensitive Info** | Apple scopes this to race, sexual orientation, disability, religion, political opinion, biometric and union membership. The app does not ask for any of them. Mood goes under Health, above. |

---

## 4. Tracking

> Do you use data for tracking purposes?

**No.** The manifest declares `NSPrivacyTracking: false` with an empty
`NSPrivacyTrackingDomains`. Because the answer is no, the app does **not** need
`NSUserTrackingUsageDescription` or an App Tracking Transparency prompt, and it
correctly has neither.

---

## 5. While you are in there

Two fields in **App Review Information** that this rejection cycle depends on:

- **Notes.** State plainly that the app sends coach messages to a third-party
  AI provider, that the provider is named on screen, and that the app asks
  permission before anything is sent and does not send anything if the person
  declines. Apple's letter asks for exactly this if the behaviour exists.
- **Support URL.** Must reach a page that exists and offers a route to a human.
  Point it at the page carrying the refund policy.

---

## 6. If you add In-App Purchase

When 3.1.1 is resolved with StoreKit, revisit:

- **Purchase History** under Identifiers may then need ticking, depending on
  what the server stores against the account.
- The manifest gains nothing automatically. If a new required-reason API comes
  in with the StoreKit work, it has to be added to `NSPrivacyAccessedAPITypes`
  by hand, or the upload fails with ITMS-91053.
