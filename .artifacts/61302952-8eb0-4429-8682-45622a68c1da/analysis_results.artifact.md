# Database Connection Audit Report

This report documents the complete audit of database (Supabase) connections across all modules in the `aquasync_driver_app` project.

## Summary of Connected Features

| Feature / Module | Status | Database Table / Source | Description |
| :--- | :--- | :--- | :--- |
| **Authentication (Login / Password Reset)** | Connected ✅ | `auth.users`, `profiles` | Authenticates driver via Supabase Auth and fetches profile roles. |
| **Driver Profile & Station Info** | Connected ✅ | `profiles` | Fetches driver full name, phone, vehicle plate, and water station business details (`station_name`, `station_address`, `station_latitude`, `station_longitude`). |
| **Deliveries & Assigned Tasks** | Connected ✅ | `deliveries`, `orders`, `order_items`, `profiles` | Real-time fetching and subscription to assigned orders and delivery status. |
| **QR Code Scanner & Gallon Verification** | Connected ✅ | `gallons`, `gallon_transactions`, `rfid_qr_records` | Scans physical QR tags, verifies against the database, updates verification state, and links scanned gallons to orders. |
| **Live Map & Route (GPS & Station / Destinations)** | Connected ✅ | `driver_locations`, `deliveries`, `profiles` | Pushes driver real-time GPS coordinates to Supabase, fetches delivery destinations, and geocodes/plots the Water Station / Business location from database records. |
| **Completed Deliveries & Reviews** | Connected ✅ | `deliveries`, `reviews`, `profiles` | Fetches completed deliveries history and customer driver reviews. |
| **Proof of Delivery (POD) & Signatures** | Connected ✅ | Supabase Storage (`pod`), `deliveries` | Uploads POD photos/signatures to Supabase Storage and updates delivery status to `delivered`. |

---

## What is NOT Connected / Items Requiring Attention

1. **Route Optimization API (Google Directions / OSRM)**:
   - **Current State**: Uses a lightweight client-side sorting fallback (`_allDeliveries.sort(...)`) and straight-line polylines on OpenStreetMap.
   - **Recommendation**: If precise turn-by-turn routing is required, integrate a real routing API (e.g., OSRM public API or Google Directions API).
2. **External Push Notifications (FCM / OneSignal)**:
   - **Current State**: Uses Supabase Realtime Postgres Changes (`SupabaseService.subscribeToDeliveries`) to trigger in-app `DriverNotification` banners when dispatch or order status changes.
   - **Recommendation**: For background push notifications when app is closed, integrate Firebase Cloud Messaging (FCM).
