# MANA YATRA Platform Architecture & Technical Report

This report provides a comprehensive summary of the **MANA YATRA** ride-sharing platform, analyzing its three core Flutter applications: **Admin**, **Driver**, and **Rider**. It breaks down the features, API integrations, application workflows, and specific Firebase operation counts (Reads/Writes/Deletes) per scenario.

---

## 1. High-Level Overview

The platform uses a standard ride-hailing tripartite architecture:
- **Rider App:** For passengers to book rides, view driver bids, and track their trips in real-time.
- **Driver App:** For drivers to receive ride requests, submit fare bids, and navigate to the passenger.
- **Admin App:** For platform administrators to monitor analytics, verify driver documents, and manage users/rides.

### Core Technologies & APIs
- **Framework:** Flutter (Dart)
- **Backend (BaaS):** Firebase (Authentication, Firestore, Realtime Database, Cloud Storage)
- **Location & Routing:** 
  - `Google Maps Platform` (Maps SDK, Places API for search, Directions/Routes API for paths/ETAs)
  - `Geolocator` for device GPS access.
  - `dart_geohash` for spatial querying.

---

## 2. Application Features Breakdown

### 📱 Rider App
- **Authentication:** Phone number login via Firebase Auth (OTP).
- **Location Selection:** Context-aware pickup and drop-off search using Google Places.
- **Ride Request:** Creates ride requests broadcasting to nearby drivers.
- **Bidding System:** Real-time view of driver bids for a requested ride.
- **Active Ride Tracking:** Real-time map visualization of the driver's approach and trip progress.
- **Payment & Rating:** Ride completion handling.

### 🚕 Driver App
- **Authentication & Onboarding:** Phone Auth, plus a registration flow for profile photo, Aadhaar, and Driving License uploads (stored in Firebase Storage).
- **Dashboard / Status:** Toggle Online/Offline status. Polls for nearby ride requests using Geohashing.
- **Bidding System:** View ride details and place custom fare bids.
- **Smart Tracker:** Background/Foreground location tracking that updates Firebase efficiently based on distance/time filters.
- **Active Navigation:** Turn-by-turn or route visualization from pickup to drop-off.

### 💻 Admin App
- **Analytics Dashboard:** Overview of total rides, revenue, and active users/drivers.
- **User Management:** View, suspend, or manage rider accounts.
- **Driver Verification:** Review uploaded KYC documents (Aadhaar, License, Selfie) and approve/reject driver onboarding.
- **Ride Monitoring:** View logs of ongoing and completed rides, including dispute resolution.

---

## 3. Workflows & Firebase Operation Analysis

The following details the interactions between the apps and Firebase. *Counts are approximate and depend on exact implementation limits (e.g., batched reads).*

### Scenario A: Driver Goes Online & Tracking
**Workflow:** Driver toggles "Online" and `SmartTracker` begins.
- **Driver App:**
  - **Writes:** 
    - `1 Write/Update` to Firestore `drivers` collection (status = online).
    - `Continuous Writes` to RTDB (`liveLocations/$driverId`) - occurs roughly every 5 meters or set interval.
    - `Periodic Writes` to Firestore `drivers` to update Geohash for discovery.
- **Rider App / Admin App:** None until a ride is active.

### Scenario B: Rider Requests a Ride
**Workflow:** Rider enters destination and taps "Request Ride".
- **Rider App:**
  - **Reads:** External API calls to Google Maps (Geocoding/Directions).
  - **Writes:** `1 Write` to `rides` collection (Status: 'searching', contains pickup/dropoff coords).
- **Driver App:**
  - **Reads:** `Continuous Reads` (Firestore Listener or spatial query polling) by online drivers in the vicinity checking for new `rides`. (Counts as 1 read per matching document per driver).

### Scenario C: Driver Places a Bid
**Workflow:** Driver sees the request and submits a fare bid.
- **Driver App:**
  - **Writes:** `1 Write` to `bids` collection.
  - **Writes:** `1 Update` to the `rides` document (Updating status to 'bidding' or appending driver to a list).
- **Rider App:**
  - **Reads:** `Continuous Reads` (Listener) on the `bids` collection linked to their `rideId`. (1 read per incoming bid).

### Scenario D: Rider Accepts a Bid
**Workflow:** Rider taps "Accept" on a specific driver's bid.
- **Rider App:**
  - **Writes:** `1 Batch Write` consisting of:
    - Update `rides` doc (Status: 'matched', assigning `driverId`, setting final price, generating OTP).
    - Update `bids` doc (Status: 'accepted').
- **Driver App:**
  - **Reads:** The driver's listener on the `rides` or `bids` collection triggers, moving them to the Active Ride screen.

### Scenario E: Active Ride & Navigation
**Workflow:** Driver is en route to pickup / navigating to drop-off.
- **Driver App:**
  - **Writes:** `Continuous Writes` to RTDB `liveLocations/$driverId` for smooth tracking.
  - **Writes:** `Periodic Updates` to `rides` collection (e.g., status: 'arrived', 'started', 'completed').
- **Rider App:**
  - **Reads:** `Continuous Reads` (Listener) on RTDB `liveLocations/$driverId` to animate the car marker on the map.
  - **Reads:** `Continuous Reads` (Listener) on `rides` doc for status transitions.

### Scenario F: Ride Completion
**Workflow:** Driver ends the trip.
- **Driver App:**
  - **Writes:** `1 Update` to `rides` collection (Status: 'completed').
  - **Deletes:** Might delete the specific `liveLocations/$driverId` node in RTDB if the driver goes offline (1 Delete), though usually, it's just overwritten.
- **Rider App:**
  - **Reads:** Ride listener triggers completion UI.
- **Admin App:**
  - **Reads:** Analytics listeners update aggregated stats (if aggregation functions/triggers are used, this happens server-side, otherwise app reads newly completed rides).

### Scenario G: Driver Onboarding & Admin Verification
**Workflow:** New driver signs up and uploads documents; Admin verifies.
- **Driver App:**
  - **Writes:** `Multiple Writes` to Firebase Cloud Storage (Photo, Aadhaar, License).
  - **Writes:** `1 Write/Update` to Firestore `drivers` collection with image URLs and status = 'pending'.
- **Admin App:**
  - **Reads:** Admin navigates to Drivers Screen, causing `N Reads` from `drivers` collection (where N is the number of drivers loaded).
  - **Writes:** Admin clicks "Approve". `1 Update` to `drivers` collection (status = 'verified').

---

## 4. Summary of Database Strategy

1. **Firestore** is used for persistent, structural data that requires complex querying and high durability (Users, Drivers profiles, Rides history, Bids, Geohashes).
   - *Cost optimization:* Rides and Bids are separated to prevent the `rides` document from growing too large and to avoid unnecessary document read charges when polling.
2. **Realtime Database (RTDB)** is explicitly used for high-frequency location pinging (`SmartTracker`). 
   - *Cost optimization:* RTDB charges by bandwidth rather than per-read/write, making it significantly cheaper for live marker tracking on a map.
3. **Cloud Storage** handles all binary blobs (KYC documents, Profile pictures).
4. **Google Maps APIs** are strictly used for client-side resolution (Geocoding, Routes, Places) to construct the UI, avoiding backend overhead.

*This architecture is highly scalable and follows industry best practices for a ride-sharing MVP to enterprise transition, efficiently balancing Firestore costs with RTDB performance.*
