# One Bharat Export-Import — Flutter App

3 roles ek hi codebase mein: **Importer**, **Exporter**, **Logistics (3PL)**.

## Setup

1. **Flutter SDK installed hona chahiye** (3.3+). Check: `flutter doctor`

2. **Dependencies install karo:**
   ```bash
   flutter pub get
   ```

3. **Backend URL set karo** — `lib/core/constants/app_constants.dart` mein:
   - Android **emulator**: `http://10.0.2.2:8080/api/v1` (already set — 10.0.2.2 emulator ka localhost alias hai)
   - **Physical device**: apni machine ka LAN IP daalo, jaise `http://192.168.1.5:8080/api/v1` (jaise tumne OneHealth mein Windows Firewall rule + LAN IP se kiya tha, wahi pattern yahan bhi)
   - Razorpay key bhi yahin daalna: `razorpayKeyId`

4. **Run:**
   ```bash
   flutter run
   ```

## Kya bana hai

- ✅ Login/Register (role selection: importer/exporter/logistics)
- ✅ JWT session persistence (flutter_secure_storage)
- ✅ Importer: create order → Razorpay checkout → payment verify → order list → confirm delivery
- ✅ Exporter: view incoming orders → assign 3PL logistics partner
- ✅ Logistics: view assigned shipments → update status (picked_up → in_transit → delivered)

## Abhi bache hue (batao kya chahiye next)

- ❌ KYC document upload screens (backend API ready hai: `/kyc/submit`, S3 presigned upload flow banana hai)
- ❌ POD (proof of delivery) photo upload UI — backend endpoint ready hai (`/shipments/upload-pod`), image_picker already pubspec mein hai bas UI nahi bani
- ❌ Order detail screen (tracking timeline view — backend `/shipments/:id/timeline` ready hai)
- ❌ Notifications screen (backend ready, FCM push wiring baaki)
- ❌ Admin dashboard (KYC approve/reject UI)
- ❌ Exporter/Logistics ID lookup — abhi manually ID type karni padti hai (search/directory feature chahiye)

## Important notes

- **Razorpay test mode** use karo pehle (`rzp_test_...` keys) — dashboard.razorpay.com se free mil jaate hain
- App **debug mode** mein hai — production build ke liye `flutter build apk --release` (signing key setup karna padega, jaise tumne pehle kiya hai)
- Exporter ka "fund account ID" abhi importer ko manually daalna padta hai confirm-delivery ke time — ye production mein backend se auto-fetch hona chahiye (ek chota endpoint `GET /orders/:id/exporter-payout-info` banana hoga)
