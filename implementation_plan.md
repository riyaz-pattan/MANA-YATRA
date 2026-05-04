# MANA YATRA - Implementation Plan

This document outlines the step-by-step implementation plan based on your requested inclusions and exclusions for the Rider, Driver, and Admin applications.

## Goal
To refine the feature set of all three MANA YATRA applications by removing unnecessary features (like the 'Car' vehicle type, wallets, and manual bookings) and adding requested core features (like Ride History, Profile/Settings, Document Status, and Cash Payments).

> [!IMPORTANT]
> **User Review Required**
> Please review this implementation plan. Once you approve, I will begin executing these changes step-by-step.

---

## Proposed Changes

### 1. Global / Common Changes

#### [MODIFY] `rider/lib/config/constants.dart` & `driver/lib/config/constants.dart`
- Remove the `'car'` entry from `vehicleTypes`, `pricePerKm`, and `baseFare`.
- Ensure the default fallback vehicle type is `'auto'` or `'bike'`.

---

### 2. Rider App Changes

#### [MODIFY] `rider/lib/screens/home_screen.dart`
- Remove any UI elements that display or allow the selection of the 'Car' vehicle type.
- Ensure only 'Auto' and 'Bike' are available for ride estimation.

#### [MODIFY] `rider/lib/screens/active_ride_screen.dart`
- **Cash Payment Flow:** Add UI indicating "Pay ₹X in Cash" to the driver at the end of the trip. No wallet or UPI integration will be added.

#### [NEW] `rider/lib/screens/ride_history_screen.dart`
- Create a new screen that fetches from the `rides` Firestore collection where `riderId == currentUser.uid` and `status == 'completed'`.
- Display date, pickup, drop-off, driver details, and the final cash amount paid.

#### [NEW] `rider/lib/screens/profile_screen.dart`
- Create a basic profile screen displaying the user's phone number and simple account details.
- Provide navigation links to Ride History, Settings, and Logout.

#### [NEW] `rider/lib/screens/settings_screen.dart`
- Add basic toggles and a "Send Feedback" button.

---

### 3. Driver App Changes

#### [MODIFY] `driver/lib/screens/onboarding_screen.dart`
- Complete the KYC implementation.
- Add UI and logic to pick and upload Profile Photo, Aadhaar Card, and Driving License images to Firebase Cloud Storage.
- Save the resulting download URLs to the `drivers` Firestore document.
- Remove 'Car' from any vehicle type dropdown menus.

#### [NEW] `driver/lib/screens/ride_earnings_history_screen.dart`
- Fetch from the `rides` Firestore collection where `driverId == currentUser.uid` and `status == 'completed'`.
- Display a list of past trips and calculate total cash earnings collected directly from riders.

#### [NEW] `driver/lib/screens/subscription_screen.dart`
- Display the current subscription status (e.g., "Active until [Date]").
- Add a "Pay ₹15 for Today" button (UI placeholder for future Razorpay integration).

#### [NEW] `driver/lib/screens/profile_status_screen.dart`
- Read the driver's document from Firestore and display the KYC verification status (`pending`, `verified`, or `rejected`).
- Provide navigation to edit details or re-upload documents if rejected.

#### [NEW] `driver/lib/screens/support_screen.dart`
- Add a basic FAQ list and a "Submit Support Ticket" button.

#### [NEW] `driver/lib/screens/settings_screen.dart`
- Add Notification Preferences (e.g., "Mute new ride alerts").
- Add a prominent Logout button.

#### [MODIFY] `driver/lib/screens/dashboard_screen.dart`
- Add a side drawer or bottom navigation bar to easily access the new History, Subscription, Profile, Support, and Settings screens.

---

### 4. Admin App Changes

#### [MODIFY] `admin/lib/screens/drivers_screen.dart`
- Ensure the table or list does not filter or display 'Car' vehicle types.
- Ensure the admin can view the uploaded DL, Aadhaar, and Profile Photos to approve/reject the driver.

#### [NEW] `admin/lib/screens/earnings_report_screen.dart`
- Create a dedicated dashboard tab to track Subscription Payments collected from drivers (placeholder data until Razorpay is active).

#### [NEW] `admin/lib/screens/document_management_screen.dart`
- A simple settings screen where the admin can define or view the required document types for onboarding.

#### [NEW] `admin/lib/screens/notification_settings_screen.dart`
- A screen providing a text field and button to send global Firebase Cloud Messaging (FCM) broadcast notifications to all riders or drivers.

---

## Open Questions
- Do you have a specific UI package or design style (e.g., a specific color for the new screens) you want me to use for the new Profile/History screens, or should I match the existing app theme?

## Verification Plan
1. **Compilation:** Ensure all three Flutter apps compile without errors after adding new files and modifying constants.
2. **UI Verification:** Manually verify via screenshots that the 'Car' option is removed from the Rider estimation UI and Driver onboarding.
3. **Data Integrity:** Verify that new drivers are saved with only 'auto' or 'bike' in Firestore.
