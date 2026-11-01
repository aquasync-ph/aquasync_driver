import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'theme.dart';

class DeliveryMapPoint {
  final String orderId;
  final String orderNumber;
  final String customerName;
  final String address;
  final LatLng location;
  final String status;
  final String phone;

  DeliveryMapPoint({
    required this.orderId,
    required this.orderNumber,
    required this.customerName,
    required this.address,
    required this.location,
    this.status = 'assigned',
    this.phone = '',
  });
}

class InAppMapWidget extends StatefulWidget {
  final LatLng? driverLocation;
  final LatLng? destinationLocation;
  final String? destinationAddress;
  final String? customerName;
  final String? orderNumber;
  final String? driverName;
  final String? stationName;
  final String? stationAddress;
  final LatLng? stationLocation;
  final List<DeliveryMapPoint> multiDeliveryPoints;
  final bool showControls;
  final bool isInteractive;
  final double initialZoom;
  final Function(DeliveryMapPoint)? onMarkerTap;

  const InAppMapWidget({
    super.key,
    this.driverLocation,
    this.destinationLocation,
    this.destinationAddress,
    this.customerName,
    this.orderNumber,
    this.driverName,
    this.stationName,
    this.stationAddress,
    this.stationLocation,
    this.multiDeliveryPoints = const [],
    this.showControls = true,
    this.isInteractive = true,
    this.initialZoom = 14.5,
    this.onMarkerTap,
  });

  static void showDriverLiveMapModal(
    BuildContext context, {
    LatLng? location,
    String? driverName,
    String? stationName,
    String? stationAddress,
    LatLng? stationLocation,
    List<DeliveryMapPoint> multiDeliveryPoints = const [],
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.82,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          driverName != null && driverName.isNotEmpty
                              ? "$driverName's Live Location"
                              : 'Your Real-time GPS Location',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: AppColors.midnightBlue,
                          ),
                        ),
                        const Text(
                          'Synced in real-time with Admin & Customer',
                          style: TextStyle(fontSize: 11, color: AppColors.grayText),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.successBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.successBorder),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.circle, color: AppColors.successGreen, size: 8),
                          SizedBox(width: 4),
                          Text(
                            'LIVE GPS',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppColors.successGreen,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
                  child: InAppMapWidget(
                    driverLocation: location,
                    driverName: driverName,
                    stationName: stationName,
                    stationAddress: stationAddress,
                    stationLocation: stationLocation,
                    multiDeliveryPoints: multiDeliveryPoints,
                    showControls: true,
                    isInteractive: true,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  State<InAppMapWidget> createState() => _InAppMapWidgetState();
}

class _InAppMapWidgetState extends State<InAppMapWidget> {
  final MapController _mapController = MapController();
  LatLng? _currentDriverPos;
  LatLng? _resolvedDestination;
  LatLng? _resolvedStationLocation;
  List<DeliveryMapPoint> _resolvedMultiPoints = [];
  List<LatLng> _osrmRoutePoints = [];
  StreamSubscription<Position>? _positionSubscription;
  double _calculatedDistanceKm = 0.0;
  bool _isLoadingLocation = true;

  // Default fallback center (Victoria, Calabarzon / Laguna region)
  static const LatLng _defaultCenter = LatLng(14.2272, 121.3283);

  @override
  void initState() {
    super.initState();
    _currentDriverPos = widget.driverLocation;
    _resolvedMultiPoints = List.from(widget.multiDeliveryPoints);
    _resolvedStationLocation = widget.stationLocation;
    _geocodeMultiDeliveryPoints();
    if (widget.destinationLocation != null) {
      final isStation = _resolvedStationLocation != null &&
          (widget.destinationLocation!.latitude - _resolvedStationLocation!.latitude).abs() < 0.0001 &&
          (widget.destinationLocation!.longitude - _resolvedStationLocation!.longitude).abs() < 0.0001;
      if (isStation && widget.destinationAddress != null && widget.destinationAddress!.isNotEmpty) {
        _resolveDestinationFromAddress(widget.destinationAddress);
      } else {
        _resolvedDestination = widget.destinationLocation;
      }
    } else {
      _resolveDestinationFromAddress(widget.destinationAddress);
    }
    if (_resolvedStationLocation == null && widget.stationAddress != null) {
      _resolveStationFromAddress(widget.stationAddress);
    }
    _initLiveLocation();
    _updateOsrmRoutes();
  }

  Future<void> _updateOsrmRoutes() async {
    final start = _currentDriverPos ?? _resolvedStationLocation;
    final end = _resolvedDestination ?? (_resolvedMultiPoints.isNotEmpty ? _resolvedMultiPoints.first.location : null);
    if (start == null || end == null) return;

    try {
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?overview=full&geometries=geojson',
      );
      final response = await http.get(
        url,
        headers: {'User-Agent': 'com.example.aquasync_driver_app/1.0'},
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final routes = data['routes'] as List?;
        if (routes != null && routes.isNotEmpty) {
          final geometry = routes[0]['geometry'];
          final coords = geometry['coordinates'] as List?;
          if (coords != null && coords.isNotEmpty && mounted) {
            final points = coords.map<LatLng>((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())).toList();
            setState(() {
              _osrmRoutePoints = points;
            });
            return;
          }
        }
      }
    } catch (e) {
      debugPrint('OSRM routing fetch error: $e');
    }

    if (mounted) {
      setState(() {
        _osrmRoutePoints = [];
      });
    }
  }

  Future<void> _resolveStationFromAddress(String? address) async {
    if (address == null || address.trim().isEmpty) return;
    try {
      final LatLng? geocoded = await _geocodeAddress(address);
      if (geocoded != null && mounted) {
        setState(() {
          _resolvedStationLocation = geocoded;
        });
        _updateOsrmRoutes();
        _autoCenterMap();
      }
    } catch (e) {
      debugPrint('Geocoding error for station address "$address": $e');
    }
  }

  @override
  void didUpdateWidget(covariant InAppMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    bool shouldAutoCenter = false;

    if (widget.multiDeliveryPoints != oldWidget.multiDeliveryPoints) {
      setState(() {
        _resolvedMultiPoints = List.from(widget.multiDeliveryPoints);
      });
      _geocodeMultiDeliveryPoints();
      shouldAutoCenter = true;
    }

    if (widget.driverLocation != null && widget.driverLocation != oldWidget.driverLocation) {
      if (_currentDriverPos == null) shouldAutoCenter = true;
      setState(() {
        _currentDriverPos = widget.driverLocation;
      });
      _recalculateDistance();
      _updateOsrmRoutes();
    }
    if (widget.destinationLocation != oldWidget.destinationLocation ||
        widget.destinationAddress != oldWidget.destinationAddress) {
      if (widget.destinationLocation != null) {
        setState(() {
          _resolvedDestination = widget.destinationLocation;
        });
        _recalculateDistance();
        _updateOsrmRoutes();
        shouldAutoCenter = true;
      } else {
        _resolveDestinationFromAddress(widget.destinationAddress);
      }
    }

    if (shouldAutoCenter) {
      _autoCenterMap();
    }
  }

  Future<void> _geocodeMultiDeliveryPoints() async {
    if (_resolvedMultiPoints.isEmpty) return;

    for (int i = 0; i < _resolvedMultiPoints.length; i++) {
      final pt = _resolvedMultiPoints[i];
      final isManilaDefault = (pt.location.latitude - 14.5995).abs() < 0.05 && (pt.location.longitude - 120.9842).abs() < 0.05;
      final isDefaultCenter = (pt.location.latitude - _defaultCenter.latitude).abs() < 0.001 && (pt.location.longitude - _defaultCenter.longitude).abs() < 0.001;
      final isStationLoc = _resolvedStationLocation != null &&
          (pt.location.latitude - _resolvedStationLocation!.latitude).abs() < 0.0001 &&
          (pt.location.longitude - _resolvedStationLocation!.longitude).abs() < 0.0001;

      if (isManilaDefault || isDefaultCenter || isStationLoc || pt.address.contains('+') || pt.location.latitude == 0) {
        final geocoded = await _geocodeAddress(pt.address);
        if (geocoded != null && mounted) {
          setState(() {
            _resolvedMultiPoints[i] = DeliveryMapPoint(
              orderId: pt.orderId,
              orderNumber: pt.orderNumber,
              customerName: pt.customerName,
              address: pt.address,
              location: geocoded,
              status: pt.status,
              phone: pt.phone,
            );
          });
          _autoCenterMap();
        }
      }
    }
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  void _autoCenterMap() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.multiDeliveryPoints.isNotEmpty || _resolvedDestination != null) {
        _fitAllPins();
      } else if (_currentDriverPos != null) {
        _centerOnRider();
      }
    });
  }

  Future<void> _resolveDestinationFromAddress(String? address) async {
    if (address == null || address.trim().isEmpty || address == 'Address not specified') {
      if (mounted && _resolvedDestination == null) {
        setState(() => _resolvedDestination = _resolvedStationLocation ?? _currentDriverPos ?? _defaultCenter);
        _updateOsrmRoutes();
      }
      return;
    }

    try {
      final LatLng? geocoded = await _geocodeAddress(address);
      if (geocoded != null && mounted) {
        setState(() {
          _resolvedDestination = geocoded;
        });
        _recalculateDistance();
        _updateOsrmRoutes();
        _autoCenterMap();
        return;
      }
    } catch (e) {
      debugPrint('Geocoding error for "$address": $e');
    }

    if (mounted && _resolvedDestination == null) {
      setState(() {
        _resolvedDestination = _resolvedStationLocation ?? _currentDriverPos ?? _defaultCenter;
      });
      _recalculateDistance();
      _updateOsrmRoutes();
      _autoCenterMap();
    }
  }

  Future<LatLng?> _geocodeAddress(String address) async {
    final cleanAddr = address.trim();
    if (cleanAddr.isEmpty) return null;

    Future<LatLng?> queryNominatim(String query) async {
      final q = query.trim();
      if (q.isEmpty) return null;
      try {
        final encoded = Uri.encodeComponent(q);
        final url = Uri.parse('https://nominatim.openstreetmap.org/search?q=$encoded&format=json&limit=1&countrycodes=ph');
        final response = await http.get(
          url,
          headers: {'User-Agent': 'com.example.aquasync_driver_app/1.0'},
        ).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final List data = jsonDecode(response.body);
          if (data.isNotEmpty) {
            final lat = double.tryParse(data[0]['lat']?.toString() ?? '');
            final lon = double.tryParse(data[0]['lon']?.toString() ?? '');
            if (lat != null && lon != null && lat != 0 && lon != 0) {
              return LatLng(lat, lon);
            }
          }
        }
      } catch (e) {
        debugPrint('Nominatim query error for "$q": $e');
      }
      return null;
    }

    // 1. Strip Plus Codes (e.g., "68HH+H76, Victoria, Calabarzon, Philippines")
    String queryAddr = cleanAddr;
    if (cleanAddr.contains('+')) {
      final parts = cleanAddr.split(',');
      if (parts.length > 1) {
        queryAddr = parts.sublist(1).join(',').trim();
      } else {
        queryAddr = cleanAddr.replaceAll(RegExp(r'^[A-Z0-9]{4,8}\+[A-Z0-9]{2,4}\s*'), '').trim();
      }
    }

    if (!queryAddr.toLowerCase().contains('philippines')) {
      queryAddr = '$queryAddr, Philippines';
    }

    // Query stripped address first
    LatLng? result = await queryNominatim(queryAddr);
    if (result != null) return result;

    String origWithCountry = cleanAddr;
    if (!origWithCountry.toLowerCase().contains('philippines')) {
      origWithCountry = '$origWithCountry, Philippines';
    }
    if (origWithCountry != queryAddr) {
      result = await queryNominatim(origWithCountry);
      if (result != null) return result;
    }

    // Fallback to individual parts (e.g., "Victoria, Laguna, Philippines")
    final parts = cleanAddr.split(',');
    for (var part in parts) {
      final trimmed = part.trim();
      if (trimmed.length > 3 && !trimmed.contains('+') && trimmed.toLowerCase() != 'philippines') {
        result = await queryNominatim('$trimmed, Laguna, Philippines');
        if (result != null) return result;
      }
    }

    return null;
  }

  Future<void> _initLiveLocation() async {
    if (_currentDriverPos != null) return;
    try {
      Position? pos = await Geolocator.getLastKnownPosition();
      if (pos != null && mounted) {
        final localPos = pos;
        setState(() {
          _currentDriverPos = LatLng(localPos.latitude, localPos.longitude);
          _isLoadingLocation = false;
        });
        _recalculateDistance();
        _updateOsrmRoutes();
        _autoCenterMap();
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission != LocationPermission.deniedForever && permission != LocationPermission.denied) {
        Position? freshPos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 8),
          ),
        );
        if (mounted && freshPos != null) {
          setState(() {
            _currentDriverPos = LatLng(freshPos.latitude, freshPos.longitude);
            _isLoadingLocation = false;
          });
          _recalculateDistance();
          _updateOsrmRoutes();
          _autoCenterMap();
        }

        // Listen to live GPS stream as rider moves
        _positionSubscription = Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5,
          ),
        ).listen((Position position) {
          if (mounted) {
            final isFirstFix = _currentDriverPos == null;
            setState(() {
              _currentDriverPos = LatLng(position.latitude, position.longitude);
            });
            _recalculateDistance();
            _updateOsrmRoutes();
            if (isFirstFix) {
              _autoCenterMap();
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Location stream error in map widget: $e');
    }

    if (_currentDriverPos == null && mounted) {
      setState(() {
        _currentDriverPos = widget.multiDeliveryPoints.isNotEmpty
            ? widget.multiDeliveryPoints.first.location
            : _defaultCenter;
        _isLoadingLocation = false;
      });
      _updateOsrmRoutes();
      _autoCenterMap();
    }
  }

  void _recalculateDistance() {
    if (_currentDriverPos != null && _resolvedDestination != null) {
      final meters = Geolocator.distanceBetween(
        _currentDriverPos!.latitude,
        _currentDriverPos!.longitude,
        _resolvedDestination!.latitude,
        _resolvedDestination!.longitude,
      );
      setState(() {
        _calculatedDistanceKm = meters / 1000.0;
      });
    }
  }

  void _centerOnRider() {
    if (_currentDriverPos != null) {
      _mapController.move(_currentDriverPos!, 16.0);
    }
  }

  void _centerOnDestination() {
    if (_resolvedDestination != null) {
      _mapController.move(_resolvedDestination!, 16.0);
    }
  }

  void _fitAllPins() {
    final List<LatLng> points = [];
    if (_currentDriverPos != null && !_currentDriverPos!.latitude.isNaN && !_currentDriverPos!.longitude.isNaN) {
      points.add(_currentDriverPos!);
    }
    if (_resolvedDestination != null && !_resolvedDestination!.latitude.isNaN && !_resolvedDestination!.longitude.isNaN) {
      points.add(_resolvedDestination!);
    }
    if (_resolvedStationLocation != null && !_resolvedStationLocation!.latitude.isNaN && !_resolvedStationLocation!.longitude.isNaN) {
      points.add(_resolvedStationLocation!);
    }
    for (var p in _resolvedMultiPoints) {
      if (!p.location.latitude.isNaN && !p.location.longitude.isNaN && !p.location.latitude.isInfinite && !p.location.longitude.isInfinite) {
        points.add(p.location);
      }
    }

    if (points.isEmpty) return;
    if (points.length == 1) {
      try {
        _mapController.move(points.first, 15.0);
      } catch (_) {}
      return;
    }

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (var p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    if ((maxLat - minLat).abs() < 0.00001 && (maxLng - minLng).abs() < 0.00001) {
      try {
        _mapController.move(LatLng(minLat, minLng), 15.0);
      } catch (_) {}
      return;
    }

    try {
      final bounds = LatLngBounds(LatLng(minLat, minLng), LatLng(maxLat, maxLng));
      _mapController.fitCamera(CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(50)));
    } catch (e) {
      debugPrint('Fit camera bounds error: $e');
      try {
        _mapController.move(points.first, 15.0);
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final driverPos = _currentDriverPos ?? _defaultCenter;
    final destPos = _resolvedDestination;

    final List<Marker> markers = [];

    // Station / Business Marker
    if (_resolvedStationLocation != null) {
      markers.add(
        Marker(
          point: _resolvedStationLocation!,
          width: 140,
          height: 70,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.darkNavy,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                ),
                child: Text(
                  widget.stationName ?? 'Water Station',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Icon(Icons.store_rounded, color: Colors.white, size: 18),
              ),
            ],
          ),
        ),
      );
    }

    // Driver Marker (Clean, no big circle aura)
    if (_currentDriverPos != null) {
      final nameToShow = (widget.driverName != null && widget.driverName!.isNotEmpty)
          ? widget.driverName!
          : 'Driver';
      markers.add(
        Marker(
          point: driverPos,
          width: 130,
          height: 75,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.successGreen,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                ),
                child: Text(
                  nameToShow,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.successGreen,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.5),
                ),
                child: const Icon(Icons.two_wheeler_rounded, color: Colors.white, size: 18),
              ),
            ],
          ),
        ),
      );
    }

    // Single Destination Marker
    if (destPos != null) {
      markers.add(
        Marker(
          point: destPos,
          width: 140,
          height: 70,
          child: GestureDetector(
            onTap: () {
              if (widget.customerName != null) {
                _showPointDetailsSheet(
                  DeliveryMapPoint(
                    orderId: '',
                    orderNumber: widget.orderNumber ?? 'N/A',
                    customerName: widget.customerName ?? 'Customer',
                    address: widget.destinationAddress ?? 'Delivery Location',
                    location: destPos,
                  ),
                );
              }
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.navy,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                  ),
                  child: Text(
                    widget.customerName ?? 'Destination',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
                const Icon(Icons.location_on_rounded, color: AppColors.errorRed, size: 36),
              ],
            ),
          ),
        ),
      );
    }

    // Multi Delivery Markers
    for (var pt in _resolvedMultiPoints) {
      final isOutForDelivery = pt.status.toLowerCase() == 'out_for_delivery';
      markers.add(
        Marker(
          point: pt.location,
          width: 130,
          height: 65,
          child: GestureDetector(
            onTap: () {
              if (widget.onMarkerTap != null) {
                widget.onMarkerTap!(pt);
              } else {
                _showPointDetailsSheet(pt);
              }
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: isOutForDelivery ? AppColors.tertiary : AppColors.darkText,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                  ),
                  child: Text(
                    '${pt.orderNumber} • ${pt.customerName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                ),
                Icon(
                  Icons.location_on_rounded,
                  color: isOutForDelivery ? AppColors.warningAmber : AppColors.primary,
                  size: 32,
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Polylines (Routes: OSRM Turn-by-Turn Real Road Route or Clean Direct Line Fallback)
    final List<Polyline> polylines = [];

    if (_osrmRoutePoints.isNotEmpty) {
      polylines.add(
        Polyline(
          points: _osrmRoutePoints,
          color: AppColors.primary,
          strokeWidth: 4.5,
        ),
      );
    } else if (_currentDriverPos != null && destPos != null) {
      polylines.add(
        Polyline(
          points: [_currentDriverPos!, destPos],
          color: AppColors.primary,
          strokeWidth: 4.5,
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentDriverPos ?? destPos ?? _defaultCenter,
              initialZoom: widget.initialZoom,
              interactionOptions: InteractionOptions(
                flags: widget.isInteractive ? InteractiveFlag.all : InteractiveFlag.drag,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.aquasync_driver_app',
              ),
              if (polylines.isNotEmpty) PolylineLayer(polylines: polylines),
              MarkerLayer(markers: markers),
            ],
          ),

          // Loading Overlay
          if (_isLoadingLocation)
            Positioned(
              top: 10,
              left: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 8),
                    Text('Fetching Live GPS...', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),

          // Distance Overlay Badge (Single Delivery Mode)
          if (destPos != null && _calculatedDistanceKm > 0)
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.navy,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.near_me_rounded, color: AppColors.tertiary, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      '${_calculatedDistanceKm.toStringAsFixed(1)} km away',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),

          // Controls Panel
          if (widget.showControls)
            Positioned(
              bottom: 12,
              right: 12,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _mapControlBtn(
                    icon: Icons.my_location_rounded,
                    tooltip: 'Center Driver',
                    onTap: _centerOnRider,
                  ),
                  const SizedBox(height: 8),
                  if (destPos != null) ...[
                    _mapControlBtn(
                      icon: Icons.pin_drop_rounded,
                      tooltip: 'Center Destination',
                      onTap: _centerOnDestination,
                    ),
                    const SizedBox(height: 8),
                  ],
                  _mapControlBtn(
                    icon: Icons.zoom_out_map_rounded,
                    tooltip: 'Fit All Pins',
                    onTap: _fitAllPins,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _mapControlBtn({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      elevation: 4,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: AppColors.navy, size: 20),
        ),
      ),
    );
  }

  void _showPointDetailsSheet(DeliveryMapPoint pt) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.person_pin_circle_rounded, color: AppColors.primary, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(pt.customerName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      Text('Order ${pt.orderNumber}', style: const TextStyle(color: AppColors.grayText, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 18, color: AppColors.grayText),
                const SizedBox(width: 8),
                Expanded(child: Text(pt.address, style: const TextStyle(fontSize: 13, color: AppColors.darkText))),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.check_rounded),
                label: const Text('CLOSE PREVIEW'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.navy,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
