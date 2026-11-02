import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ScannedGallonItem {
  final String id;
  final String gallonCode;
  final String orderId;
  final String orderNumber;
  final DateTime scannedAt;
  final String status;
  final String customerName;
  final String deliveryAddress;

  ScannedGallonItem({
    required this.id,
    required this.gallonCode,
    this.orderId = '',
    this.orderNumber = '',
    required this.scannedAt,
    this.status = 'scanned_local',
    this.customerName = '',
    this.deliveryAddress = '',
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'gallonCode': gallonCode,
      'orderId': orderId,
      'orderNumber': orderNumber,
      'scannedAt': scannedAt.toIso8601String(),
      'status': status,
      'customerName': customerName,
      'deliveryAddress': deliveryAddress,
    };
  }

  factory ScannedGallonItem.fromJson(Map<String, dynamic> json) {
    return ScannedGallonItem(
      id: json['id']?.toString() ?? '',
      gallonCode: json['gallonCode']?.toString() ?? '',
      orderId: json['orderId']?.toString() ?? '',
      orderNumber: json['orderNumber']?.toString() ?? '',
      scannedAt: DateTime.tryParse(json['scannedAt']?.toString() ?? '') ?? DateTime.now(),
      status: json['status']?.toString() ?? 'scanned_local',
      customerName: json['customerName']?.toString() ?? '',
      deliveryAddress: json['deliveryAddress']?.toString() ?? '',
    );
  }
}

class ScannedItemsManager {
  static final ScannedItemsManager instance = ScannedItemsManager._internal();
  ScannedItemsManager._internal();

  static const String _storageKey = 'aquasync_scanned_gallons_v1';
  final ValueNotifier<List<ScannedGallonItem>> itemsNotifier = ValueNotifier([]);

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? jsonStr = prefs.getString(_storageKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(jsonStr);
        final loadedItems = decoded
            .map((item) => ScannedGallonItem.fromJson(Map<String, dynamic>.from(item)))
            .toList();
        itemsNotifier.value = loadedItems;
      }
      _initialized = true;
    } catch (e) {
      debugPrint('ScannedItemsManager init error: $e');
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(itemsNotifier.value.map((i) => i.toJson()).toList());
      await prefs.setString(_storageKey, encoded);
    } catch (e) {
      debugPrint('ScannedItemsManager persist error: $e');
    }
  }

  Future<bool> saveScannedItem(ScannedGallonItem item) async {
    await init();
    final currentList = List<ScannedGallonItem>.from(itemsNotifier.value);
    
    // Check if already scanned for the same order/gallonCode
    final existingIndex = currentList.indexWhere(
      (i) => i.gallonCode == item.gallonCode && (item.orderId.isEmpty || i.orderId == item.orderId),
    );

    if (existingIndex >= 0) {
      currentList[existingIndex] = item; // Update
    } else {
      currentList.insert(0, item); // Add to top
    }

    itemsNotifier.value = currentList;
    await _persist();
    return true;
  }

  Future<void> removeScannedItem(String gallonCode, {String? orderId}) async {
    await init();
    final currentList = List<ScannedGallonItem>.from(itemsNotifier.value);
    currentList.removeWhere((item) =>
        (item.gallonCode == gallonCode || item.id == gallonCode) && (orderId == null || orderId.isEmpty || item.orderId == orderId));
    itemsNotifier.value = currentList;
    await _persist();
  }

  List<ScannedGallonItem> getScannedForOrder(String orderId) {
    if (orderId.isEmpty) return [];
    return itemsNotifier.value.where((item) => item.orderId == orderId).toList();
  }

  Set<String> getScannedCodesForOrder(String orderId) {
    return getScannedForOrder(orderId).map((e) => e.gallonCode).toSet();
  }

  int getScannedCountForOrder(String orderId) {
    return getScannedForOrder(orderId).length;
  }

  Future<void> clearScansForOrder(String orderId) async {
    if (orderId.isEmpty) return;
    await init();
    final currentList = List<ScannedGallonItem>.from(itemsNotifier.value);
    currentList.removeWhere((item) => item.orderId == orderId);
    itemsNotifier.value = currentList;
    await _persist();
  }

  Future<void> clearAllScans() async {
    await init();
    itemsNotifier.value = [];
    await _persist();
  }

  // --- POD Photo & Signature Cache ---
  Future<void> savePodPhotoCache(String orderId, Uint8List bytes) async {
    if (orderId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final base64Str = base64Encode(bytes);
      await prefs.setString('aquasync_pod_photo_$orderId', base64Str);
    } catch (e) {
      debugPrint('Error saving POD photo cache: $e');
    }
  }

  Future<Uint8List?> getPodPhotoCache(String orderId) async {
    if (orderId.isEmpty) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final base64Str = prefs.getString('aquasync_pod_photo_$orderId');
      if (base64Str != null && base64Str.isNotEmpty) {
        return base64Decode(base64Str);
      }
    } catch (e) {
      debugPrint('Error loading POD photo cache: $e');
    }
    return null;
  }

  Future<void> saveSignatureCache(String orderId, String sigData, [Uint8List? sigBytes]) async {
    if (orderId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('aquasync_sig_data_$orderId', sigData);
      if (sigBytes != null) {
        final base64Str = base64Encode(sigBytes);
        await prefs.setString('aquasync_sig_bytes_$orderId', base64Str);
      }
    } catch (e) {
      debugPrint('Error saving Signature cache: $e');
    }
  }

  Future<Map<String, dynamic>?> getSignatureCache(String orderId) async {
    if (orderId.isEmpty) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final sigData = prefs.getString('aquasync_sig_data_$orderId');
      final sigBytesStr = prefs.getString('aquasync_sig_bytes_$orderId');
      Uint8List? sigBytes;
      if (sigBytesStr != null && sigBytesStr.isNotEmpty) {
        sigBytes = base64Decode(sigBytesStr);
      }
      if (sigData != null || sigBytes != null) {
        return {
          'sigData': sigData ?? 'signed',
          'sigBytes': sigBytes,
        };
      }
    } catch (e) {
      debugPrint('Error loading Signature cache: $e');
    }
    return null;
  }

  Future<void> clearOrderCache(String orderId) async {
    if (orderId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('aquasync_pod_photo_$orderId');
      await prefs.remove('aquasync_sig_data_$orderId');
      await prefs.remove('aquasync_sig_bytes_$orderId');
      await clearScansForOrder(orderId);
    } catch (e) {
      debugPrint('Error clearing order cache: $e');
    }
  }
}
