import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SupabaseService {
  static const String _profileCacheKey = 'cached_driver_profile';
  static SupabaseClient get client => Supabase.instance.client;

  static User? get currentUser {
    try {
      return client.auth.currentUser;
    } catch (_) {
      return null;
    }
  }

  static bool get isAuthenticated {
    try {
      return currentUser != null;
    } catch (_) {
      return false;
    }
  }

  // --- AUTHENTICATION ---
  static Future<AuthResponse> signInWithPassword({
    required String email,
    required String password,
  }) async {
    return await client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  static Future<void> signOut() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_profileCacheKey);
    } catch (_) {}
    await client.auth.signOut();
  }

  static Future<void> resetPasswordForEmail(String email) async {
    await client.auth.resetPasswordForEmail(email);
  }

  // --- PROFILES & DRIVER LOCATION ---
  static Future<Map<String, dynamic>?> fetchProfile(String userId) async {
    try {
      final data = await client
          .from('profiles')
          .select('id, full_name, phone, address, role, avatar_url, latitude, longitude, updated_at')
          .eq('id', userId)
          .maybeSingle()
          .timeout(const Duration(seconds: 5));
      
      if (data != null) {
        // Only cache the profile if it belongs to the currently logged-in user.
        // This prevents overwriting the driver's cached profile when fetching a customer's profile.
        if (userId == client.auth.currentUser?.id) {
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_profileCacheKey, jsonEncode(data));
          } catch (_) {}
        }
      }
      return data;
    } catch (e) {
      debugPrint('Error fetching profile from DB (or timeout): $e');
      // Fallback to locally cached profile (Offline session support)
      try {
        final prefs = await SharedPreferences.getInstance();
        final cached = prefs.getString(_profileCacheKey);
        if (cached != null) {
          debugPrint('Loaded driver profile from local cache.');
          return jsonDecode(cached) as Map<String, dynamic>;
        }
      } catch (_) {}
      return null;
    }
  }

  static Future<void> updateDriverLocation({
    required String driverId,
    required double latitude,
    required double longitude,
  }) async {
    final currentUserId = currentUser?.id;
    if (currentUserId == null || currentUserId != driverId) return;

    final isoNow = DateTime.now().toIso8601String();

    try {
      await client.from('profiles').update({
        'latitude': latitude,
        'longitude': longitude,
        'updated_at': isoNow,
      }).eq('id', driverId);
    } catch (e) {
      debugPrint('Error updating profiles location: $e');
    }

    try {
      await client.from('driver_locations').upsert({
        'driver_id': driverId,
        'latitude': latitude,
        'longitude': longitude,
        'updated_at': isoNow,
      }, onConflict: 'driver_id');
    } catch (e) {
      debugPrint('Error updating driver_locations table: $e');
    }
  }

  static Future<void> updateFcmToken(String token) async {
    final user = currentUser;
    if (user == null || token.trim().isEmpty) return;

    try {
      await client.from('profiles').update({
        'fcm_token': token,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', user.id);
    } catch (e) {
      debugPrint('Error updating FCM push token: $e');
    }
  }

  // --- WATER REFILL STATION LOCATION & SETTINGS ---

  /// Helper to parse station data payload supporting all specified field aliases:
  /// - Latitude: latitude, lat, station_latitude
  /// - Longitude: longitude, lng, station_longitude
  /// - Station Name: station_name, full_name, name
  /// - Address: address, station_address
  /// - Geofence Radius: coverage_radius_km, geofence_radius_km, radius_km, geofence_radius
  static Map<String, dynamic> parseStationData(Map<String, dynamic> raw) {
    num? parseNum(dynamic val) {
      if (val == null) return null;
      if (val is num) return val;
      return double.tryParse(val.toString());
    }

    final lat = parseNum(raw['latitude']) ??
        parseNum(raw['lat']) ??
        parseNum(raw['station_latitude']);

    final lng = parseNum(raw['longitude']) ??
        parseNum(raw['lng']) ??
        parseNum(raw['station_longitude']);

    final name = raw['station_name']?.toString() ??
        raw['full_name']?.toString() ??
        raw['name']?.toString() ??
        raw['business_name']?.toString() ??
        raw['shop_name']?.toString();

    final address = raw['address']?.toString() ??
        raw['station_address']?.toString() ??
        raw['shop_address']?.toString() ??
        raw['location_address']?.toString();

    final radiusKm = parseNum(raw['coverage_radius_km']) ??
        parseNum(raw['geofence_radius_km']) ??
        parseNum(raw['radius_km']) ??
        parseNum(raw['geofence_radius']) ??
        parseNum(raw['radius']) ??
        parseNum(raw['coverage_radius']);

    final Map<String, dynamic> result = Map<String, dynamic>.from(raw);

    if (lat != null) {
      result['latitude'] = lat;
      result['lat'] = lat;
      result['station_latitude'] = lat;
    }
    if (lng != null) {
      result['longitude'] = lng;
      result['lng'] = lng;
      result['station_longitude'] = lng;
    }
    if (name != null && name.isNotEmpty) {
      result['station_name'] = name;
      result['full_name'] = name;
      result['name'] = name;
      result['business_name'] = name;
    }
    if (address != null && address.isNotEmpty) {
      result['address'] = address;
      result['station_address'] = address;
    }
    if (radiusKm != null) {
      result['coverage_radius_km'] = radiusKm;
      result['geofence_radius_km'] = radiusKm;
      result['radius_km'] = radiusKm;
      result['geofence_radius'] = radiusKm;
      result['radius'] = radiusKm;
    }

    return result;
  }

  /// Fetches Water Refill Station location, coordinates, and geofence radius from Supabase.
  /// Queries tables: station_settings, system_settings (key: station_config), and profiles (admin role).
  static Future<Map<String, dynamic>?> fetchStationLocation() async {
    return await fetchShopProfile();
  }

  /// Alias for fetchStationLocation()
  static Future<Map<String, dynamic>?> fetchShopProfile() async {
    Map<String, dynamic>? accumulatedData;

    // 1. Query public.station_settings table
    try {
      final data = await client.from('station_settings').select().limit(1).maybeSingle();
      if (data != null && data.isNotEmpty) {
        final parsed = parseStationData(data);
        if (parsed['latitude'] != null && parsed['longitude'] != null) {
          return parsed;
        }
        accumulatedData = parsed;
      }
    } catch (e) {
      debugPrint('fetchShopProfile station_settings query notice: $e');
    }

    // 2. Query public.system_settings table (key: station_config, station_settings, shop_config, etc.)
    try {
      final sysData = await client
          .from('system_settings')
          .select()
          .or('key.eq.station_config,key.eq.station_settings,key.eq.shop_config,key.eq.station_location')
          .limit(1)
          .maybeSingle();

      if (sysData != null && sysData.isNotEmpty) {
        dynamic val = sysData['value'];
        Map<String, dynamic> configMap = {};
        if (val is Map<String, dynamic>) {
          configMap = Map<String, dynamic>.from(val);
        } else if (val is String) {
          try {
            final decoded = jsonDecode(val);
            if (decoded is Map<String, dynamic>) {
              configMap = decoded;
            }
          } catch (_) {}
        }
        if (configMap.isEmpty) {
          configMap = Map<String, dynamic>.from(sysData);
        }

        final parsed = parseStationData(configMap);
        if (parsed['latitude'] != null && parsed['longitude'] != null) {
          if (accumulatedData != null) {
            return {...accumulatedData, ...parsed};
          }
          return parsed;
        }
        if (accumulatedData != null) {
          accumulatedData = {...accumulatedData, ...parsed};
        } else {
          accumulatedData = parsed;
        }
      }
    } catch (e) {
      debugPrint('fetchShopProfile system_settings query notice: $e');
    }

    // 3. Query public.profiles table for admin role (admin, station_admin, owner, station)
    try {
      final profilesRes = await client
          .from('profiles')
          .select()
          .or('role.eq.admin,role.eq.station_admin,role.eq.owner,role.eq.station')
          .limit(5);

      if (profilesRes.isNotEmpty) {
        for (var p in profilesRes) {
          final Map<String, dynamic> pMap = Map<String, dynamic>.from(p);
          final parsed = parseStationData(pMap);
          if (parsed['latitude'] != null && parsed['longitude'] != null) {
            if (accumulatedData != null) {
              return {...accumulatedData, ...parsed};
            }
            return parsed;
          }
          if (accumulatedData != null) {
            accumulatedData = {...accumulatedData, ...parsed};
          } else {
            accumulatedData = parsed;
          }
        }
      }
    } catch (e) {
      debugPrint('fetchShopProfile profiles admin query notice: $e');
    }

    // 4. Query profiles table fallback for non-null station_latitude
    try {
      final stationProfile = await client
          .from('profiles')
          .select()
          .not('station_latitude', 'is', null)
          .limit(1)
          .maybeSingle();

      if (stationProfile != null) {
        final parsed = parseStationData(Map<String, dynamic>.from(stationProfile));
        if (parsed['latitude'] != null && parsed['longitude'] != null) {
          if (accumulatedData != null) {
            return {...accumulatedData, ...parsed};
          }
          return parsed;
        }
        if (accumulatedData != null) {
          accumulatedData = {...accumulatedData, ...parsed};
        } else {
          accumulatedData = parsed;
        }
      }
    } catch (e) {
      debugPrint('fetchShopProfile fallback notice: $e');
    }

    return accumulatedData;
  }

  /// Realtime channel subscription for automatic station updates.
  /// When Admin modifies station coordinates or geofence radius in Admin Dashboard,
  /// this stream listener fires and re-fetches updated station location.
  static RealtimeChannel subscribeToStationLocation(Function(Map<String, dynamic> stationData) onUpdate) {
    final channel = client.channel('station-location-updates-${DateTime.now().millisecondsSinceEpoch}');

    void handleEvent(dynamic payload) async {
      try {
        final updated = await fetchStationLocation();
        if (updated != null) {
          onUpdate(updated);
        }
      } catch (e) {
        debugPrint('Error handling real-time station update: $e');
      }
    }

    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'station_settings',
      callback: handleEvent,
    );

    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'system_settings',
      callback: handleEvent,
    );

    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'profiles',
      callback: handleEvent,
    );

    channel.subscribe();
    return channel;
  }

  // --- DELIVERIES & ORDERS ---
  static Future<List<Map<String, dynamic>>> fetchDeliveries(String driverId) async {
    final response = await client
        .from('deliveries')
        .select('*, orders(*, order_items(*), profiles:customer_id(*))')
        .eq('driver_id', driverId)
        .order('created_at', ascending: false);
    
    final deliveries = List<Map<String, dynamic>>.from(response);

    for (var d in deliveries) {
      final order = d['orders'];
      if (order is Map<String, dynamic>) {
        final orderId = order['id']?.toString();
        if (orderId != null && orderId.isNotEmpty) {
          try {
            final paymentRecord = await client
                .from('payments')
                .select('method, status')
                .eq('order_id', orderId)
                .maybeSingle();
            if (paymentRecord != null) {
              final method = paymentRecord['method']?.toString();
              if (method != null && method.isNotEmpty) {
                order['payment_method'] = method;
                d['payment_method'] = method;
              }
            }
          } catch (_) {}
        }

        // Support direct embedded profiles or fallback to manual query if needed
        var profile = order['profiles'];
        
        if (profile == null) {
          final customerId = order['customer_id']?.toString();
          if (customerId != null && customerId.isNotEmpty) {
            try {
              profile = await client
                  .from('profiles')
                  .select('full_name, phone, address, latitude, longitude')
                  .eq('id', customerId)
                  .maybeSingle();
            } catch (_) {}
          }
        }

        if (profile != null && profile is Map<String, dynamic>) {
          order['profiles'] = profile;
          order['customer'] = profile;
          order['customer_name'] = profile['full_name'];
          
          if (profile['phone'] != null && profile['phone'].toString().isNotEmpty) {
            order['customer_phone'] = profile['phone'];
          }
          
          // Robust address extraction
          final String? orderAddr = order['delivery_address']?.toString();
          final String? profileAddr = profile['address']?.toString();
          
          bool isInvalid(String? s) {
            if (s == null) return true;
            final trimmed = s.trim();
            return trimmed.isEmpty || trimmed == 'N/A' || trimmed == '—' || trimmed == '-' || trimmed == '–';
          }

          if (isInvalid(orderAddr)) {
            if (!isInvalid(profileAddr)) {
              order['delivery_address'] = profileAddr;
            } else {
              order['delivery_address'] = 'Address not specified';
            }
          }
        }
      }
    }

    return deliveries;
  }

  // Realtime subscription for driver deliveries & orders
  static RealtimeChannel subscribeToDeliveries(String driverId, Function(String eventType, Map<String, dynamic>? payload) onUpdate) {
    final channel = client.channel('driver-updates-$driverId');

    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'deliveries',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'driver_id',
        value: driverId,
      ),
      callback: (payload) {
        onUpdate('deliveries', payload.newRecord);
      },
    );

    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'orders',
      callback: (payload) {
        onUpdate('orders', payload.newRecord);
      },
    );

    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'order_messages',
      callback: (payload) {
        onUpdate('order_messages', payload.newRecord);
      },
    );

    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'notifications',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'user_id',
        value: driverId,
      ),
      callback: (payload) {
        onUpdate('notifications', payload.newRecord);
      },
    );

    channel.subscribe();
    return channel;
  }

  static RealtimeChannel subscribeToReviews(String driverId, Function(Map<String, dynamic>? newRecord) onUpdate) {
    final channel = client.channel('driver-reviews-$driverId');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'reviews',
      callback: (payload) {
        onUpdate(payload.newRecord);
      },
    );
    channel.subscribe();
    return channel;
  }

  static Future<void> removeChannel(RealtimeChannel channel) async {
    await client.removeChannel(channel);
  }

  // Authoritative Delivery Status Update via public.driver_update_delivery_status
  static Future<bool> updateDeliveryStatus(
    String deliveryId,
    String status, {
    String? currentStatus,
    String? proofUrl,
    String? notes,
  }) async {
    final newStatus = status.toLowerCase();

    // Canonical status transition validation
    if (currentStatus != null && currentStatus.isNotEmpty) {
      final curr = currentStatus.toLowerCase();
      bool isValid = false;
      if (curr == 'assigned' && newStatus == 'accepted') {
        isValid = true;
      } else if (curr == 'accepted' && newStatus == 'out_for_delivery') {
        isValid = true;
      } else if (curr == 'out_for_delivery' && newStatus == 'delivered') {
        isValid = true;
      }

      if (!isValid) {
        throw Exception('Invalid delivery status transition from $curr to $newStatus');
      }
    }

    // 1. Try RPC update first (if defined on DB schema)
    try {
      final Map<String, dynamic> rpcParams = {
        'delivery_id': deliveryId,
        'status': newStatus,
      };
      if (proofUrl != null && proofUrl.isNotEmpty) {
        rpcParams['proof_url'] = proofUrl;
      }
      await client.rpc('driver_update_delivery_status', params: rpcParams);
    } catch (e) {
      debugPrint('RPC driver_update_delivery_status error/info: $e');
    }

    // 2. Direct table update to deliveries
    try {
      final Map<String, dynamic> deliveryUpdates = {
        'status': newStatus,
        if (newStatus == 'accepted') 'accepted_at': DateTime.now().toIso8601String(),
        if (newStatus == 'out_for_delivery') 'started_at': DateTime.now().toIso8601String(),
        if (newStatus == 'delivered') 'delivered_at': DateTime.now().toIso8601String(),
      };
      if (proofUrl != null && proofUrl.isNotEmpty) {
        deliveryUpdates['proof_url'] = proofUrl;
      }
      if (notes != null && notes.isNotEmpty) {
        deliveryUpdates['notes'] = notes;
      }

      await client
          .from('deliveries')
          .update(deliveryUpdates)
          .eq('id', deliveryId);
    } catch (e) {
      debugPrint('Direct update to deliveries status error: $e');
      try {
        await client.from('deliveries').update({
          'status': newStatus,
          if (newStatus == 'delivered') 'delivered_at': DateTime.now().toIso8601String(),
        }).eq('id', deliveryId);
      } catch (err2) {
        debugPrint('Fallback update to deliveries error: $err2');
      }
    }

    // 3. Direct table update to orders
    try {
      final delRecord = await client
          .from('deliveries')
          .select('order_id')
          .eq('id', deliveryId)
          .maybeSingle();

      if (delRecord != null && delRecord['order_id'] != null) {
        final orderId = delRecord['order_id'].toString();

        try {
          final Map<String, dynamic> orderUpdates = {
            'status': newStatus,
            'order_status': newStatus,
            if (newStatus == 'delivered') 'delivered_at': DateTime.now().toIso8601String(),
          };
          if (proofUrl != null && proofUrl.isNotEmpty) {
            orderUpdates['proof_url'] = proofUrl;
          }
          await client.from('orders').update(orderUpdates).eq('id', orderId);
        } catch (_) {
          try {
            await client.from('orders').update({
              'order_status': newStatus,
            }).eq('id', orderId);
          } catch (_) {
            try {
              await client.from('orders').update({
                'status': newStatus,
              }).eq('id', orderId);
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      debugPrint('Error syncing orders status: $e');
    }

    return true;
  }

  // --- STORAGE & FULFILLMENT (POD PHOTO & SIGNATURE) ---
  static Future<String> uploadPodPhoto({
    required String deliveryId,
    required Uint8List bytes,
    String? orderId,
    String? fileName,
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final ordId = (orderId != null && orderId.isNotEmpty) ? orderId : deliveryId;
    final name = fileName ?? 'pod_${ordId}_$timestamp.jpg';
    final filePath = name;

    // Primary bucket 'proofs' per Driver POD Photo requirements
    try {
      await client.storage.from('proofs').uploadBinary(
        filePath,
        bytes,
        fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
      );
      final publicUrl = client.storage.from('proofs').getPublicUrl(filePath);
      return publicUrl;
    } catch (e) {
      debugPrint('Error uploading to proofs bucket: $e. Retrying with fallback buckets...');
      try {
        await client.storage.from('deliveries').uploadBinary(
          filePath,
          bytes,
          fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
        );
        return client.storage.from('deliveries').getPublicUrl(filePath);
      } catch (_) {
        await client.storage.from('pod').uploadBinary(
          filePath,
          bytes,
          fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
        );
        return client.storage.from('pod').getPublicUrl(filePath);
      }
    }
  }

  static Future<void> saveProofOfDelivery({
    required String deliveryId,
    required String orderId,
    required String proofUrl,
    String? notes,
  }) async {
    final nowIso = DateTime.now().toIso8601String();

    // 1. Update deliveries table
    if (deliveryId.isNotEmpty) {
      try {
        final Map<String, dynamic> delUpdates = {
          'status': 'delivered',
          'proof_url': proofUrl,
          'delivered_at': nowIso,
        };
        if (notes != null && notes.trim().isNotEmpty) {
          delUpdates['notes'] = notes.trim();
        }
        await client.from('deliveries').update(delUpdates).eq('id', deliveryId);
      } catch (e) {
        debugPrint('Updating deliveries proof_url failed, trying proof_of_delivery: $e');
        try {
          await client.from('deliveries').update({
            'status': 'delivered',
            'proof_of_delivery': proofUrl,
            'delivered_at': nowIso,
          }).eq('id', deliveryId);
        } catch (e2) {
          debugPrint('Updating deliveries status & proof failed: $e2');
        }
      }
    }

    // 2. Update orders table
    if (orderId.isNotEmpty) {
      try {
        await client.from('orders').update({
          'order_status': 'delivered',
          'status': 'delivered',
          'proof_url': proofUrl,
          'delivered_at': nowIso,
        }).eq('id', orderId);
      } catch (e) {
        debugPrint('Updating orders proof_url failed, trying fallback: $e');
        try {
          await client.from('orders').update({
            'proof_of_delivery': proofUrl,
          }).eq('id', orderId);
        } catch (_) {}
      }
    }
  }

  static Future<String> uploadSignature({
    required String deliveryId,
    required Uint8List bytes,
  }) async {
    final filePath = 'signatures/$deliveryId/sig.png';
    try {
      await client.storage.from('pod').uploadBinary(
        filePath,
        bytes,
        fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
      );
      return client.storage.from('pod').getPublicUrl(filePath);
    } catch (_) {
      try {
        await client.storage.from('proofs').uploadBinary(
          filePath,
          bytes,
          fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
        );
        return client.storage.from('proofs').getPublicUrl(filePath);
      } catch (_) {
        return '';
      }
    }
  }

  static Future<void> updateFulfillment({
    required String deliveryId,
    String? podUrl,
    String? signatureData,
  }) async {
    if (podUrl != null && podUrl.isNotEmpty) {
      try {
        await client.from('deliveries').update({
          'pod_image_url': podUrl,
        }).eq('id', deliveryId);
      } catch (_) {}
    }

    if (signatureData != null && signatureData.isNotEmpty) {
      try {
        await client.from('deliveries').update({
          'signature_data': signatureData,
        }).eq('id', deliveryId);
      } catch (_) {}
    }
  }

  // --- PAYMENTS ---
  static Future<void> recordPayment({
    required String orderId,
    required double amount,
    required String paymentMethod,
  }) async {
    final driverId = currentUser?.id;
    if (driverId == null || driverId.isEmpty) {
      throw Exception('Driver not authenticated');
    }

    // 1. Verify current driver is assigned to order through deliveries
    final delivery = await client
        .from('deliveries')
        .select('id')
        .eq('order_id', orderId)
        .eq('driver_id', driverId)
        .maybeSingle();

    if (delivery == null) {
      throw Exception('Order $orderId is not assigned to current driver');
    }

    // 2. Query order to verify total_amount
    final order = await client
        .from('orders')
        .select('id, total_amount, payment_status')
        .eq('id', orderId)
        .maybeSingle();

    if (order == null) {
      throw Exception('Order $orderId not found');
    }

    final orderTotal = (order['total_amount'] as num?)?.toDouble() ?? 0.0;
    if ((amount - orderTotal).abs() > 0.01) {
      throw Exception('Payment amount (₱$amount) does not match order total (₱$orderTotal)');
    }

    // 3. Idempotency check: check if paid payment already exists
    final existingPayment = await client
        .from('payments')
        .select('id, status')
        .eq('order_id', orderId)
        .eq('status', 'paid')
        .maybeSingle();

    if (existingPayment != null) {
      debugPrint('Payment for order $orderId is already recorded as paid.');
      return;
    }

    final methodVal = paymentMethod.toUpperCase().contains('GCASH') ? 'GCash' : 'COD';

    // 4. Insert payment
    await client.from('payments').insert({
      'order_id': orderId,
      'amount': orderTotal,
      'method': methodVal,
      'status': 'paid',
      'paid_at': DateTime.now().toIso8601String(),
    });

    // 5. Update orders payment_status
    await client.from('orders').update({
      'payment_status': 'paid',
    }).eq('id', orderId);
  }

  // --- GALLON VERIFICATION & TRANSACTIONS ---

  /// Query container record by `gallon_code` directly or via `rfid_qr_records.code`.
  /// Returns container record with fields: id, gallon_code, status, customer_id, borrowed_at, returned_at, updated_at, customer_name.
  static Future<Map<String, dynamic>?> fetchContainerByCode(String scannedCode) async {
    final cleanCode = scannedCode.trim();
    if (cleanCode.isEmpty) return null;

    Map<String, dynamic>? gallonRecord;

    try {
      // 1. Query public.gallons directly by gallon_code
      final response = await client
          .from('gallons')
          .select('id, gallon_code, status, customer_id, borrowed_at, returned_at, updated_at')
          .eq('gallon_code', cleanCode)
          .maybeSingle();

      if (response != null) {
        gallonRecord = Map<String, dynamic>.from(response);
      }
    } catch (e) {
      debugPrint('fetchContainerByCode gallons query error: $e');
    }

    // 2. Query public.rfid_qr_records table by code
    if (gallonRecord == null) {
      try {
        final rfidRecord = await client
            .from('rfid_qr_records')
            .select('gallon_id')
            .eq('code', cleanCode)
            .maybeSingle();

        if (rfidRecord != null && rfidRecord['gallon_id'] != null) {
          final gallonId = rfidRecord['gallon_id'].toString();
          final response = await client
              .from('gallons')
              .select('id, gallon_code, status, customer_id, borrowed_at, returned_at, updated_at')
              .eq('id', gallonId)
              .maybeSingle();

          if (response != null) {
            gallonRecord = Map<String, dynamic>.from(response);
          }
        }
      } catch (e) {
        debugPrint('fetchContainerByCode rfid_qr_records query error: $e');
      }
    }

    // 3. Resolve assigned customer name if customer_id exists
    if (gallonRecord != null && gallonRecord['customer_id'] != null && gallonRecord['customer_id'].toString().isNotEmpty) {
      final custId = gallonRecord['customer_id'].toString();
      try {
        final profile = await fetchProfile(custId);
        if (profile != null) {
          gallonRecord['customer_name'] = profile['full_name'] ?? 'Unknown Customer';
        }
      } catch (_) {}
    }

    return gallonRecord;
  }

  /// Backward-compatible wrapper for fetchContainerByCode
  static Future<Map<String, dynamic>?> verifyGallon(String gallonCode) async {
    return await fetchContainerByCode(gallonCode);
  }

  /// Executes real-time status toggle and logs transaction in Supabase following exact specifications.
  /// Case A (available/not borrowed -> borrowed):
  ///   - Updates public.gallons: status='borrowed', customer_id=<customer_id>, borrowed_at=NOW(), updated_at=NOW()
  ///   - Inserts public.gallon_transactions: gallon_id, customer_id, action='borrowed', notes='Container delivered and scanned by Driver [Driver Name/ID]'
  /// Case B (borrowed -> available):
  ///   - Updates public.gallons: status='available', customer_id=NULL, returned_at=NOW(), updated_at=NOW()
  ///   - Inserts public.gallon_transactions: gallon_id, customer_id=NULL, action='returned', notes='Empty container collected and returned to station by Driver [Driver Name/ID]'
  static Future<Map<String, dynamic>> executeGallonStatusToggle({
    required String gallonId,
    required String gallonCode,
    required String currentStatus,
    String? customerId,
    String? customerName,
    String? driverNameOrId,
    String? orderId,
  }) async {
    final nowIso = DateTime.now().toIso8601String();

    // 1. Resolve Driver Name / Identifier for Notes
    final driverId = currentUser?.id ?? '';
    String driverIdentifier = driverNameOrId ?? '';
    if (driverIdentifier.isEmpty && driverId.isNotEmpty) {
      try {
        final profile = await fetchProfile(driverId);
        driverIdentifier = profile?['full_name'] ?? currentUser?.email ?? driverId;
      } catch (_) {
        driverIdentifier = currentUser?.email ?? driverId;
      }
    }
    if (driverIdentifier.isEmpty) {
      driverIdentifier = 'Driver';
    }

    final isCurrentlyBorrowed = (currentStatus.toLowerCase() == 'borrowed');

    if (!isCurrentlyBorrowed) {
      // --- CASE A: Container is currently 'available' -> Delivering / Lending to Customer ---
      String? targetCustomerId = (customerId != null && customerId.isNotEmpty) ? customerId : null;
      String targetCustomerName = (customerName != null && customerName.isNotEmpty) ? customerName : 'Customer';

      // If customerId is null or empty but orderId is provided, attempt to fetch customer_id from orders or deliveries table
      if ((targetCustomerId == null || targetCustomerId.isEmpty) && orderId != null && orderId.isNotEmpty) {
        try {
          final ordData = await client
              .from('orders')
              .select('id, customer_id, customer_name, profiles:customer_id(full_name)')
              .or('id.eq.$orderId,order_number.eq.$orderId')
              .maybeSingle();

          if (ordData != null) {
            targetCustomerId = ordData['customer_id']?.toString();
            final profile = ordData['profiles'];
            if (targetCustomerName == 'Customer' || targetCustomerName.isEmpty) {
              targetCustomerName = ordData['customer_name']?.toString()
                  ?? (profile is Map ? profile['full_name']?.toString() : null)
                  ?? 'Customer';
            }
          } else {
            final delivData = await client
                .from('deliveries')
                .select('orders(id, customer_id, customer_name, profiles:customer_id(full_name))')
                .or('id.eq.$orderId,order_id.eq.$orderId')
                .maybeSingle();
            if (delivData != null && delivData['orders'] != null) {
              final ord = delivData['orders'];
              targetCustomerId = ord['customer_id']?.toString();
              final profile = ord['profiles'];
              if (targetCustomerName == 'Customer' || targetCustomerName.isEmpty) {
                targetCustomerName = ord['customer_name']?.toString()
                    ?? (profile is Map ? profile['full_name']?.toString() : null)
                    ?? 'Customer';
              }
            }
          }
        } catch (e) {
          debugPrint('Error resolving customer_id from orderId ($orderId): $e');
        }
      }

      final notesText = 'Container delivered and scanned by Driver $driverIdentifier';

      // 1. Update public.gallons
      await client.from('gallons').update({
        'status': 'borrowed',
        'customer_id': targetCustomerId,
        'borrowed_at': nowIso,
        'updated_at': nowIso,
      }).eq('id', gallonId);

      // 2. Insert into public.gallon_transactions
      await client.from('gallon_transactions').insert({
        'gallon_id': gallonId,
        'customer_id': targetCustomerId,
        'action': 'borrowed',
        'notes': notesText,
        'created_at': nowIso,
      });

      // Call RPC function if configured in Supabase
      try {
        await client.rpc('driver_gallon_action', params: {
          'p_gallon_id': gallonId,
          'p_order_id': orderId ?? '',
          'p_action': 'borrow',
        });
      } catch (e) {
        debugPrint('RPC driver_gallon_action (borrow) note: $e');
      }

      return {
        'success': true,
        'gallon_id': gallonId,
        'gallon_code': gallonCode,
        'previous_status': currentStatus,
        'new_status': 'borrowed',
        'action': 'borrowed',
        'customer_id': targetCustomerId,
        'customer_name': targetCustomerName,
        'notes': notesText,
        'display_message': 'Gallon $gallonCode marked as BORROWED to $targetCustomerName',
      };
    } else {
      // --- CASE B: Container is currently 'borrowed' -> Collecting / Returning Empty Container ---
      final notesText = 'Empty container collected and returned to station by Driver $driverIdentifier';

      // 1. Update public.gallons
      await client.from('gallons').update({
        'status': 'available',
        'customer_id': null,
        'returned_at': nowIso,
        'updated_at': nowIso,
      }).eq('id', gallonId);

      // 2. Insert into public.gallon_transactions
      await client.from('gallon_transactions').insert({
        'gallon_id': gallonId,
        'customer_id': null,
        'action': 'returned',
        'notes': notesText,
        'created_at': nowIso,
      });

      // Call RPC function if configured in Supabase
      try {
        await client.rpc('driver_gallon_action', params: {
          'p_gallon_id': gallonId,
          'p_order_id': orderId ?? '',
          'p_action': 'return',
        });
      } catch (e) {
        debugPrint('RPC driver_gallon_action (return) note: $e');
      }

      return {
        'success': true,
        'gallon_id': gallonId,
        'gallon_code': gallonCode,
        'previous_status': 'borrowed',
        'new_status': 'available',
        'action': 'returned',
        'customer_id': null,
        'customer_name': customerName ?? 'Station',
        'notes': notesText,
        'display_message': 'Gallon $gallonCode returned and marked as AVAILABLE in station',
      };
    }
  }

  static Future<List<Map<String, dynamic>>> fetchOrderGallonTransactions(String orderId) async {
    final response = await client
        .from('gallon_transactions')
        .select('*, gallons(id, gallon_code)')
        .eq('order_id', orderId);
    return List<Map<String, dynamic>>.from(response);
  }

  // Authoritative driver gallon action via public.driver_gallon_action
  static Future<void> driverGallonAction({
    required String gallonId,
    required String orderId,
    required String action, // 'borrow' or 'return'
  }) async {
    final canonicalAction = (action == 'borrow' || action == 'borrowed') ? 'borrow' : 'return';
    final gallonStatus = canonicalAction == 'borrow' ? 'borrowed' : 'available';

    try {
      await client.rpc('driver_gallon_action', params: {
        'p_gallon_id': gallonId,
        'p_order_id': orderId,
        'p_action': canonicalAction,
      });
    } catch (e) {
      debugPrint('RPC driver_gallon_action error: $e');
    }

    await client.from('gallons').update({
      'status': gallonStatus,
    }).eq('id', gallonId);
  }

  // --- REVIEWS & NOTIFICATIONS ---
  static Future<List<Map<String, dynamic>>> fetchDriverReviews(String driverId) async {
    final Set<Map<String, dynamic>> collectedReviews = {};

    try {
      // 1. Try querying reviews directly by driver_id
      final res1 = await client
          .from('reviews')
          .select('*, profiles:customer_id(full_name, phone)')
          .eq('driver_id', driverId)
          .order('created_at', ascending: false);
      for (var r in res1) {
        collectedReviews.add(Map<String, dynamic>.from(r));
      }
    } catch (e) {
      debugPrint('fetchDriverReviews by driver_id error: $e');
    }

    try {
      // 2. Query deliveries assigned to this driver to get order_ids and delivery_ids
      final deliveriesRes = await client
          .from('deliveries')
          .select('id, order_id')
          .eq('driver_id', driverId);

      final orderIds = <String>[];
      final deliveryIds = <String>[];
      for (var d in deliveriesRes) {
        if (d['order_id'] != null) orderIds.add(d['order_id'].toString());
        if (d['id'] != null) deliveryIds.add(d['id'].toString());
      }

      // 3. Query reviews by order_ids if any
      if (orderIds.isNotEmpty) {
        final resOrders = await client
            .from('reviews')
            .select('*, profiles:customer_id(full_name, phone)')
            .inFilter('order_id', orderIds);
        for (var r in resOrders) {
          collectedReviews.add(Map<String, dynamic>.from(r));
        }
      }

      // 4. Query reviews by delivery_ids if any
      if (deliveryIds.isNotEmpty) {
        final resDeliveries = await client
            .from('reviews')
            .select('*, profiles:customer_id(full_name, phone)')
            .inFilter('delivery_id', deliveryIds);
        for (var r in resDeliveries) {
          collectedReviews.add(Map<String, dynamic>.from(r));
        }
      }
    } catch (e) {
      debugPrint('fetchDriverReviews by order/delivery ids error: $e');
    }

    // If still empty, try fetching all reviews as a fallback
    if (collectedReviews.isEmpty) {
      try {
        final allReviews = await client
            .from('reviews')
            .select('*, profiles:customer_id(full_name, phone)')
            .order('created_at', ascending: false)
            .limit(50);
        for (var r in allReviews) {
          collectedReviews.add(Map<String, dynamic>.from(r));
        }
      } catch (e) {
        debugPrint('fetchDriverReviews fallback all reviews error: $e');
      }
    }

    // Enrich profiles if missing
    final list = collectedReviews.toList();
    for (var r in list) {
      if (r['profiles'] == null && r['customer_id'] != null) {
        try {
          final custProfile = await client
              .from('profiles')
              .select('full_name, phone')
              .eq('id', r['customer_id'])
              .maybeSingle();
          if (custProfile != null) {
            r['profiles'] = custProfile;
          }
        } catch (_) {}
      }
    }

    // Sort by created_at descending
    list.sort((a, b) {
      final aDate = DateTime.tryParse(a['created_at']?.toString() ?? '') ?? DateTime(0);
      final bDate = DateTime.tryParse(b['created_at']?.toString() ?? '') ?? DateTime(0);
      return bDate.compareTo(aDate);
    });

    return list;
  }

  static Future<List<Map<String, dynamic>>> fetchNotifications(String userId) async {
    final response = await client
        .from('notifications')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  static Future<int> fetchUnreadNotificationCount(String userId) async {
    try {
      final response = await client
          .from('notifications')
          .select('id')
          .eq('user_id', userId)
          .eq('is_read', false);
      return (response as List).length;
    } catch (e) {
      debugPrint('Error fetching unread notification count: $e');
      return 0;
    }
  }

  static Future<void> markNotificationAsRead(String notificationId) async {
    await client.from('notifications').update({'is_read': true}).eq('id', notificationId);
  }

  static Future<void> markAllNotificationsAsRead(String userId) async {
    await client.from('notifications').update({'is_read': true}).eq('user_id', userId).eq('is_read', false);
  }

  static Future<void> deleteNotification(String notificationId) async {
    await client.from('notifications').delete().eq('id', notificationId);
  }

  static Future<void> deleteAllNotifications(String userId) async {
    await client.from('notifications').delete().eq('user_id', userId);
  }

  static Future<void> createNotification({
    required String userId,
    required String title,
    required String message,
    String type = 'info',
  }) async {
    try {
      await client.from('notifications').insert({
        'user_id': userId,
        'title': title,
        'message': message,
        'type': type,
        'is_read': false,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Error creating notification: $e');
    }
  }

  // --- ORDER MESSAGING (order_messages) ---
  static Future<List<Map<String, dynamic>>> fetchMessages(String orderId) async {
    final response = await client
        .from('order_messages')
        .select('order_id, sender_id, message, created_at')
        .eq('order_id', orderId)
        .order('created_at', ascending: true);
    return List<Map<String, dynamic>>.from(response);
  }

  static Future<void> sendMessage({
    required String senderId,
    required String orderId,
    required String message,
  }) async {
    await client.from('order_messages').insert({
      'order_id': orderId,
      'sender_id': senderId,
      'message': message,
      'created_at': DateTime.now().toIso8601String(),
    });
  }
}
