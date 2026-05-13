# Driver Free Trial and Profile Rejection Features

This plan covers the implementation of a 7-day free trial for new drivers, as well as a robust profile rejection workflow for the admin.

## User Review Required

Please review the following plan. Let me know if you are satisfied with it or if you want any adjustments before I proceed with the implementation!

## Open Questions

All resolved. ✅

## Additional Requirement

- **Gallery Photo Picker**: In the onboarding screen, allow the driver to also pick their profile photo from the gallery (not just camera selfie). Show a dialog asking "Camera" or "Gallery" when the selfie area is tapped.

## Proposed Changes

---

### Admin App
Modifications to the admin app to support the rejection workflow.

#### [MODIFY] `admin/lib/screens/document_management_screen.dart`
- **Rejection Bottom Sheet**: When "Reject" is clicked for a pending driver, show a beautiful bottom sheet instead of instantly rejecting/blocking them.
- **Pre-filled Reasons**: The sheet will have selectable chips/radio buttons for common reasons:
  - "Photo does not match Aadhaar/License"
  - "Name does not match documents"
  - "Documents are blurred/unreadable"
- **Custom Reason**: Add a text field for any custom rejection reason.
- **Status Update**: Upon submitting the rejection, update the driver's Firestore document to set `isApproved: false`, `isRejected: true`, and `rejectionReason: "<reason>"`.
- **New Rejected Tab**: Add a "Rejected" filter tab to the screen so rejected drivers don't clutter the "Pending" tab, and admins can view who was rejected.

---

### Driver App
Modifications to the driver app to support the free trial and rejection workflow.

#### [MODIFY] `driver/lib/main.dart`
- Update the `AuthGate` to check for `isRejected == true` in the driver's profile.
- If rejected, route the user to the new `RejectedScreen` instead of the `PendingScreen`.

#### [NEW] `driver/lib/screens/rejected_screen.dart`
- Create a new screen that visually informs the driver that their profile was rejected.
- Display the exact rejection reason provided by the admin (e.g., "Your profile got rejected because of: Documents are blurred/unreadable").
- Include a prominent "Resubmit Documents" button that navigates the user back to the `OnboardingScreen`.

#### [MODIFY] `driver/lib/screens/onboarding_screen.dart`
- **Pre-fill Data**: Update `initState` to fetch existing profile data (if available) to pre-fill the name, vehicle type, and vehicle number.
- **Update Logic**: Change the `_submit` method to use `SetOptions(merge: true)` so it doesn't overwrite the original account creation date.
- **Reset Rejection State**: When submitting the documents, ensure `isRejected` is set to `false` and `rejectionReason` is set to `null` so the profile goes back into the "Pending" state for admin review.

#### [MODIFY] `driver/lib/screens/subscription_screen.dart`
- **Free Trial Check**: Check the driver's profile for a `hasFreeTrialUsed` flag.
- **Free Trial UI**: If the free trial hasn't been used, prominently display a "Start 7 Days Free Trial" option at the top of the plans (no payment/cash required).
- **Free Trial Action**: When clicked, update the driver's `subscriptionActiveUntil` by adding 7 days, set `hasFreeTrialUsed: true`, and create a payment history record with amount `0` and type `free_trial`.

## Verification Plan

### Manual Verification
1. **Admin Rejection**: Log into the admin app, reject a pending driver, provide a custom reason, and verify the driver moves to the "Rejected" tab.
2. **Driver Rejection View**: Log into the driver app with the rejected account, verify the "Rejected" screen appears with the correct reason.
3. **Resubmission**: Click "Resubmit Documents" in the driver app, ensure fields are pre-filled, submit new documents, and verify the driver returns to "Pending" in the admin app.
4. **Free Trial**: Approve the driver in the admin app, navigate to the driver app's Subscription screen, start the free trial, and verify the active time is extended by 7 days. Ensure the free trial button disappears afterward.
