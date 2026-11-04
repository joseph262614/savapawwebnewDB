# 🛡️ Save-A-Paws Administrator Command Center (Web & Desktop)

[![Flutter Web](https://img.shields.io/badge/Flutter-Web%20%2F%20Desktop-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Firebase](https://img.shields.io/badge/Backend-Firebase%20Realtime%20Database-FFCA28?logo=firebase&logoColor=black)](https://firebase.google.com)
[![Role](https://img.shields.io/badge/Access-Admin%20Only-E53935)](#)

> **Save-A-Paws Admin PC** is the centralized management and command workstation for animal welfare administrators, shelter supervisors, and rescue mission dispatchers. It provides high-level executive analytics, user verification, breed and adoption statistics, 5-character adoption pass verification, stray rescue mission dispatching, community content moderation, and shelter donation setup.

For full cross-ecosystem documentation and architecture details, refer to the root [README.md](../README.md).

---

## 🖥️ Key Administrative Modules

### 1. 📊 Executive Overview Dashboard (`admin_screen.dart`)
- Real-time KPI statistics: Total Users, Accredited Fosters, Active Adoptables, Successful Adoptions, and Active Stray Reports.
- System health indicators, quick-action navigation, and operational summary cards.

### 2. 👥 User & Role Management (`admin_users_screen.dart`)
- User directory search by name, username, email, UID, or role (`standard`, `foster`, `volunteer`, `admin`).
- Role assignment and promotion/demotion engine.
- Account suspension and reinstatement controls.
- Complete metadata auditing (registration dates, contact numbers, adoption logs).

### 3. 🐕 Breed Classification & Adoption Analytics (`admin_pet_breeds_screen.dart`)
- Species-specific catalogs for **Dogs** and **Cats**.
- Per-breed adoption metrics (e.g. Aspin, Shih Tzu, Golden Retriever, Puspin, Persian, Siamese).
- Overall completed adoption statistics counters.
- Registry management to update or expand breed classifications for the mobile app foster posting menu.

### 4. 🎟️ 5-Character Pass Code Verification Desk (`admin_users_screen.dart`)
- Center verification terminal to look up adopter 5-character pass codes (e.g., `K9B7X`).
- Review digitally signed middleman adoption agreements, party metadata, and timestamp.
- One-click **`Verify & Finalize Adoption`** to mark the pet as adopted and complete the formal handover.

### 5. 🪪 Foster Accreditation Queue (`admin_verification_requests_screen.dart`)
- Document inspection modal for viewing uploaded government IDs and shelter accreditation proofs.
- One-tap approval (upgrades user to `foster` and unlocks listing features on mobile).
- Rejection engine with customized feedback for resubmission.

### 6. 🚨 Rescue Operations & Dispatch (`admin_reported_pets_screen.dart`)
- Interactive incident command map plotting all reported stray animals.
- Mandatory live camera photograph and GPS coordinates inspection.
- Dispatch field volunteers to exact rescue coordinates.
- Update rescue milestones: `Reported` ➔ `Dispatched` ➔ `In Treatment` ➔ `Rescued/Sheltered`.

### 7. 🛡️ Community Content Moderation (`admin_reported_posts_screen.dart`)
- Flagged posts and comments moderation queue.
- Categorized violation breakdown (Spam, Harassment, Inappropriate, Scams).
- Enforcement tools to dismiss false reports or permanently delete offending content.

### 8. 💳 Shelter Donation & QR Configuration (`admin_donation_screen.dart`)
- Live configuration console for official shelter donation channels: **GCash**, **Maya**, and **Bank Transfer** accounts.
- Upload and swap payment QR codes in real-time, syncing immediately to all mobile user donation screens.

---

## 🚀 Running the Admin Workstation

```bash
# 1. Fetch dependencies
flutter pub get

# 2. Run on Chrome in web mode
flutter run -d chrome

# 3. Build optimized web production bundle
flutter build web --release
```
