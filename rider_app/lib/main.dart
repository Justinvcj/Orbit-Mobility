import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'services/location_search_service.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'dart:ui';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'login_screen.dart';
import 'checkout_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shimmer/shimmer.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

void main() {
  runApp(const RiderApp());
}

class RiderApp extends StatelessWidget {
  const RiderApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Equinox',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0A0B),
        textTheme: GoogleFonts.dmSansTextTheme(Theme.of(context).textTheme).apply(
          bodyColor: const Color(0xFFE8E2D9),
          displayColor: const Color(0xFFE8E2D9),
        ),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFC9A96E),
          surface: Color(0xFF0F0F0D),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: Color(0xFFC4BBA8), size: 22),
          titleTextStyle: GoogleFonts.spaceMono(
            color: const Color(0xFFE8E2D9),
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
      ),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('user_phone');
    final name = prefs.getString('user_name') ?? "Rider";

    if (!mounted) return;

    // TESTING MODE: Disable auto-login bypass
    /*
    if (phone != null && phone.isNotEmpty) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => RiderHomeScreen(userName: name, userPhone: phone)),
      );
    } else {
    */
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    // }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF0A0A0B),
      body: Center(
        child: CircularProgressIndicator(color: Color(0xFFC9A96E)),
      ),
    );
  }
}

class RiderHomeScreen extends StatefulWidget {
  final String userName;
  final String userPhone;

  const RiderHomeScreen({super.key, required this.userName, required this.userPhone});
  @override
  State<RiderHomeScreen> createState() => _RiderHomeScreenState();
}

class _RiderHomeScreenState extends State<RiderHomeScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  late IO.Socket socket;
  
  // -- CONTROLLERS --
  final TextEditingController _pickupController = TextEditingController();
  final TextEditingController _dropController = TextEditingController();

  // -- STATE VARIABLES --
  List<dynamic> _searchResults = [];
  List<Map<String, dynamic>> _recentSearches = [];
  bool _isSearchingPickup = true; 
  bool _isSearching = false;
  // Aegis search service — singleton, manages its own debounce + CancelToken
  final LocationSearchService _locationService = LocationSearchService();
  
  // Pickup Data
  String? _pickupAddress;
  double? _pickupLat;
  double? _pickupLng;

  // Drop Data
  String? _dropAddress;
  double? _dropLat;
  double? _dropLng;

  // Fare Data
  String _fare = "0";
  String _distance = "0 km";
  bool _calculating = false;
  bool _isPaymentProcessing = false;
  String _status = "Enter Trip Details";
  
  // Tier Data
  String _selectedTier = 'Equinox-Bike';
  final Map<String, double> _tierPrices = {'Equinox-Bike': 9.0, 'Fair-Auto': 15.0, 'Fair-Cab': 22.0};
  
  String? _driverPhone;
  List<Map<String, String>> _chatMessages = [];
  String? _weatherAlertMessage; // Phase 18
  
  final MapController _mapController = MapController();
  LatLng _currentLocation = const LatLng(12.9716, 77.5946); // Default
  List<LatLng> _routePoints = []; 
  LatLng? _driverLocation; 

  String? _otp;

  // History State
  List<dynamic> _rideHistory = [];
  bool _isLoadingRides = false;
  String _rideState = "IDLE";
  bool _isHudExpanded = false; // Phase 5.1 HUD Expansion State

  // Animation State
  LatLng? _oldDriverLocation;
  double _driverBearing = 0.0;
  double _lastKnownBearing = 0.0;

  double _calculateBearing(LatLng start, LatLng end) {
    double lat1 = start.latitude * math.pi / 180;
    double lng1 = start.longitude * math.pi / 180;
    double lat2 = end.latitude * math.pi / 180;
    double lng2 = end.longitude * math.pi / 180;

    double dLon = lng2 - lng1;
    double y = math.sin(dLon) * math.cos(lat2);
    double x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    return math.atan2(y, x);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _determinePosition();
    connectToServer();
    fetchMyRides();
    _loadRecentSearches();
  }

  Future<void> _loadRecentSearches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? cached = prefs.getString('recent_searches');
      if (cached != null) {
        final List<dynamic> decoded = jsonDecode(cached);
        setState(() {
          _recentSearches = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
        });
      }
    } catch (e) {
      debugPrint("Error loading recent searches: $e");
    }
  }

  Future<void> _saveRecentSearches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('recent_searches', jsonEncode(_recentSearches));
    } catch (e) {
      debugPrint("Error saving recent searches: $e");
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _locationService.dispose(); // cancels pending debounce + CancelToken
    socket.dispose();
    super.dispose();
  }

  Future<void> _makeCall(String phone) async {
    final Uri launchUri = Uri(scheme: 'tel', path: phone);
    if (!await launchUrl(launchUri)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Could not launch dialer.")));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Rehydrate: reconnect socket and fetch active ride state
      if (!socket.connected) socket.connect();
      _fetchActiveRide();
    }
  }

  Future<void> _fetchActiveRide() async {
    try {
      final response = await http.get(
        // Uri.parse('https://equinox-server-backend.onrender.com/api/active-ride/${widget.userPhone}'),
        Uri.parse('https://equinox-server-backend.onrender.com/api/active-ride/${widget.userPhone}'),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final ride = data['activeRide'];
        if (ride != null && mounted) {
          setState(() {
            _rideState = ride['status'] ?? 'IDLE';
            _fare = ride['fare']?.toString() ?? '0';
            _driverPhone = ride['driver_phone'];
            _pickupAddress = ride['pickup'];
            _dropAddress = ride['dropoff'];
            _status = _rideState == 'COMPLETED'
                ? 'Ride Completed'
                : _rideState == 'IN_PROGRESS'
                    ? 'Ride In Progress'
                    : _rideState == 'ARRIVED'
                        ? 'Driver Has Arrived'
                        : _rideState == 'ACCEPTED'
                            ? '✅ DRIVER ON THE WAY!'
                            : 'Enter Trip Details';
            _otp = ride['otp'];
          });
        }
      }
    } catch (e) {
      // Silently fail — ride state stays as-is
    }
  }

  Future<void> fetchMyRides() async {
    setState(() => _isLoadingRides = true);
    // DIAGNOSTIC TASK 1: Absolute URI routing to local Express API
    final url = Uri.parse("https://equinox-server-backend.onrender.com/api/rides/${widget.userPhone}");
    
    debugPrint('Fetching rides for Rider Phone: ${widget.userPhone}');
    try {
      final response = await http.get(
        url,
        headers: {
          "apikey": const String.fromEnvironment('SUPABASE_KEY'),
          "Authorization": "Bearer ${const String.fromEnvironment('SUPABASE_KEY')}"
        }
      );
      
      debugPrint('Supabase Response Status: ${response.statusCode}');
      debugPrint('Supabase Response Data: ${response.body}');
      
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _rideHistory = decoded['rides'] ?? [];
            _isLoadingRides = false;
          });
        }
      } else {
        debugPrint('Supabase Request Error: ${response.body}');
        if (mounted) setState(() => _isLoadingRides = false);
      }
    } catch (e) {
      debugPrint('Supabase Fetch Exception: $e');
      if (mounted) setState(() => _isLoadingRides = false);
    }
  }

  Future<void> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location services are disabled.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Location permissions are denied');
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      return Future.error('Location permissions are permanently denied, we cannot request permissions.');
    } 

    Position position = await Geolocator.getCurrentPosition();
    setState(() {
      _currentLocation = LatLng(position.latitude, position.longitude);
      _mapController.move(_currentLocation, 15.0);
    });
  }

  void connectToServer() {
    // socket = IO.io('https://equinox-server-backend.onrender.com', <String, dynamic>{
    socket = IO.io('https://equinox-server-backend.onrender.com', <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
    });
    socket.connect();

    // Register rider in a targetable room for location relay
    socket.onConnect((_) {
      socket.emit('register_rider', {'phone': widget.userPhone});
    });

    socket.on("ride_accepted", (data) {
      if (mounted) {
        if (!kIsWeb) { try { Vibration.vibrate(duration: 50); } catch (_) {} }
        setState(() {
          _rideState = "ACCEPTED";
          _driverPhone = data['driverPhone'];
          _otp = data['otp'];
          _status = "✅ DRIVER ON THE WAY!\nCar: ${data['carNumber']}";
        });
      }
    });

    socket.on("ride_status_change", (data) {
      if (['ACCEPTED', 'ARRIVED', 'IN_PROGRESS'].contains(data['status'])) {
        if (!kIsWeb) { try { Vibration.vibrate(duration: 50); } catch (_) {} }
      }
      if (mounted) {
        setState(() {
           _rideState = data['status'];
           _status = data['message'] ?? data['status'];
           
           if (_rideState == 'ACCEPTED' || _rideState == 'IN_PROGRESS') {
             _pickupController.clear();
             _dropController.clear();
             FocusManager.instance.primaryFocus?.unfocus();
           }
        });
      }
    });

    socket.on("payment_requested", (data) {
      if (mounted) {
        if (!kIsWeb) { try { Vibration.vibrate(duration: 500); } catch (_) {} }
        _showPaymentBottomSheet(data);
      }
    });

    socket.on("payment_successful", (data) {
      if (mounted) {
        if (!kIsWeb) { try { Vibration.vibrate(duration: 200); } catch (_) {} }
        if (_isPaymentProcessing) {
          Navigator.pop(context); // Dismiss the strict bottomsheet safely
          _isPaymentProcessing = false;
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Payment Complete!"), backgroundColor: Colors.green),
        );
        fetchMyRides();

        // Reset map
        setState(() {
          _rideState = "IDLE";
          _fare = "0";
          _distance = "0 km";
          _pickupAddress = null;
          _dropAddress = null;
          _pickupLat = null;
          _pickupLng = null;
          _dropLat = null;
          _dropLng = null;
          _status = "Enter Trip Details";
          _pickupController.clear();
          _dropController.clear();
          _driverPhone = null;
          _routePoints = [];
          _driverLocation = null;
        });
      }
    });

    socket.on("receive_message", (data) {
      if (mounted) {
        setState(() {
          _chatMessages.add({"sender": data['sender'], "text": data['text']});
        });
        if (!kIsWeb) { try { Vibration.vibrate(duration: 50); } catch (_) {} }
      }
    });

    socket.on("weather_alert", (data) {
      if (mounted) {
        setState(() {
          _weatherAlertMessage = data['message'];
        });
      }
    });

    socket.on("qr_paired", (data) {
      if (mounted) {
        setState(() {
          _rideState = data['status'];
          _driverPhone = data['driverPhone'];
          _status = "DRIVER PAIRED\nStreet Hail";
          _fare = "0";
        });
        Navigator.popUntil(context, (route) => route.isFirst);
      }
    });

    socket.on("route_recalculated", (data) {
      if (mounted) {
        setState(() {
          _fare = data['newFare']?.toString() ?? _fare;
          if (data['distanceStr'] != null) {
             _distance = "${data['distanceStr']} • updated";
          }
          
          if (data['polyline'] != null) {
            List<dynamic> coords = data['polyline'];
            _routePoints = coords.map((c) => LatLng(c[1], c[0])).toList();
          }

          if (data['waypoint'] != null) {
             _status = "ROUTE UPDATED\nStop Added";
          }
        });
        if (!kIsWeb) { try { Vibration.vibrate(duration: 200); } catch (_) {} }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Route Updated: ₹$_fare", style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)), backgroundColor: const Color(0xFFC9A96E))
        );
        Navigator.popUntil(context, (route) => route.isFirst); // dismiss search sheet if open
      }
    });

    socket.on("driver_location_update", (data) {
      if (mounted) {
        LatLng newLoc = LatLng(data['lat'], data['lng']);
        if (_driverLocation == null) {
          setState(() {
            _driverLocation = newLoc;
          });
        } else {
          setState(() {
            _oldDriverLocation = _driverLocation;
            _driverLocation = newLoc;
            
            double dist = Geolocator.distanceBetween(
              _oldDriverLocation!.latitude, _oldDriverLocation!.longitude,
              _driverLocation!.latitude, _driverLocation!.longitude
            );
            
            if (dist > 1.0) {
              _driverBearing = _calculateBearing(_oldDriverLocation!, _driverLocation!);
              _lastKnownBearing = _driverBearing;
            } else {
              _driverBearing = _lastKnownBearing;
            }
          });
        }
        _mapController.move(newLoc, 16.0);
      }
    });
  }

  // --- 1. SEARCH PLACES (AEGIS: Debounce + CancelToken + Photon→Nominatim cascade) ---
  void _onSearchChanged(String query) {
    if (query.length < 3) {
      // Short query — clear results immediately, no network call needed
      if (mounted) setState(() { _searchResults = []; _isSearching = false; });
      return;
    }

    // Show shimmer immediately so the UI feels responsive
    if (mounted) setState(() => _isSearching = true);

    // Delegate entirely to Aegis — it owns debounce, CancelToken, cache & cascade
    _locationService.searchPlaces(query).then((results) {
      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
    });
  }

  // Thin wrapper kept for backward-compat callers (Quick-Access chips: "Home", "Work")
  Future<void> searchAddress(String query) async {
    if (query.length < 3) {
      if (mounted) setState(() { _searchResults = []; _isSearching = false; });
      return;
    }
    if (mounted) setState(() => _isSearching = true);
    final results = await _locationService.searchPlaces(query);
    if (mounted) setState(() { _searchResults = results; _isSearching = false; });
  }


  void selectLocation(Map<String, dynamic> place) {
    setState(() {
      String address = place['display_name'];
      double lat = double.parse(place['lat']);
      double lng = double.parse(place['lon']);

      if (_isSearchingPickup) {
        _pickupController.text = address.split(',')[0];
        _pickupAddress = address;
        _pickupLat = lat;
        _pickupLng = lng;
      } else {
        _dropController.text = address.split(',')[0];
        _dropAddress = address;
        _dropLat = lat;
        _dropLng = lng;
      }
      _searchResults = []; // Hide search list
    });

    // Save to Recent Searches if it's a Drop destination
    if (!_isSearchingPickup) {
      final newEntry = {
        'display_name': place['display_name'],
        'primary_text': place['primary_text'] ?? place['display_name'].split(',')[0],
        'secondary_text': place['secondary_text'] ?? '',
        'lat': place['lat'].toString(),
        'lon': place['lon'].toString(),
      };

      setState(() {
        // De-duplicate based on lat/lon
        _recentSearches.removeWhere((element) => 
          element['lat'] == newEntry['lat'] && element['lon'] == newEntry['lon']);
        
        _recentSearches.insert(0, newEntry);
        
        // Cap at 5
        if (_recentSearches.length > 5) {
          _recentSearches = _recentSearches.sublist(0, 5);
        }
      });
      _saveRecentSearches();
    }

    if (_pickupLat != null && _dropLat != null) {
       getRoutePrice();
    } else {
       // Just center map on selected location
       if (place['lat'] != null && place['lon'] != null) {
           _mapController.move(LatLng(double.parse(place['lat']), double.parse(place['lon'])), 15.0);
       }
    }
  }

  // --- 2. CALCULATE ROUTE & PRICE (OSRM) ---
  Future<void> getRoutePrice() async {
    if (_pickupLat == null || _dropLat == null) return;

    setState(() => _calculating = true);

    // OSRM Free Routing API (GeoJSON)
    final url = Uri.parse(
      "http://router.project-osrm.org/route/v1/driving/$_pickupLng,$_pickupLat;$_dropLng,$_dropLat?geometries=geojson"
    );

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        // Distance Logic
        double meters = data['routes'][0]['distance'];
        double km = meters / 1000;
        
        // NEW Duration Logic
        double seconds = data['routes'][0]['duration']?.toDouble() ?? 0.0;
        double minutes = seconds / 60;
        
        // ROUTE PARSING
        final List<dynamic> coords = data['routes'][0]['geometry']['coordinates'];
        List<LatLng> points = coords.map((c) => LatLng(c[1], c[0])).toList();

        setState(() {
          _distance = "${km.toStringAsFixed(1)} km • ${minutes.toStringAsFixed(0)} mins";
          
          double pricePerKm = _tierPrices[_selectedTier] ?? 9.0;
          _fare = (km * pricePerKm).round().toString();
          
          _calculating = false;
          _status = "Ready to Book";
          _routePoints = points;
        });

        // Fit map to route
        if (_routePoints.isNotEmpty) {
           _mapController.move(LatLng(_pickupLat!, _pickupLng!), 13.0);
        }
      }
    } catch (e) {
      debugPrint("Routing Error: $e");
      setState(() => _calculating = false);
    }
  }

  // --- 3. BOOK RIDE (FIXED: Sends GPS Coordinates) ---
  void bookRide() {
    if (_fare == "0") return;

    setState(() => _status = "Searching for Drivers...");

    socket.emit("request_ride", {
      "riderName": widget.userName,
      "riderPhone": widget.userPhone,
      "pickup": _pickupAddress,
      "drop": _dropAddress,
      
      // NEW: Sending REAL GPS Coordinates
      "pickupLat": _pickupLat,
      "pickupLng": _pickupLng,
      "dropLat": _dropLat,
      "dropLng": _dropLng,
      "tier": _selectedTier,
      "vehicle_type": _selectedTier,
      "fare": _fare,
      "distance": _distance
    });
  }

  // --- 4. RIDE HISTORY UI ---
  void _showRideHistory() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Color(0xFF0F0F0D),
                borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                border: Border(top: BorderSide(color: Color(0xFF1E1C17), width: 1)),
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    height: 5,
                    width: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A2820),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text("My Rides", style: GoogleFonts.cormorantGaramond(fontSize: 22, fontWeight: FontWeight.w400, color: const Color(0xFFE8E2D9))),
                  ),
                  Expanded(
                    child: _isLoadingRides == true
                      ? const Center(child: CircularProgressIndicator(color: Color(0xFFC9A96E)))
                      : (_rideHistory == null || _rideHistory.isEmpty == true)
                          ? Center(child: Text("No past rides found", style: GoogleFonts.spaceMono(color: const Color(0xFF6B6556), fontSize: 16)))
                          : ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                          itemCount: _rideHistory.length,
                          itemBuilder: (context, index) {
                            final ride = _rideHistory[index];
                            final date = DateTime.tryParse(ride['created_at']?.toString() ?? '')?.toLocal() ?? DateTime.now();
                            final formattedDate = "${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}";
                            return Card(
                              elevation: 0,
                              color: const Color(0xFF161613),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(0), side: const BorderSide(color: Colors.black, width: 1.5)),
                              margin: const EdgeInsets.only(bottom: 16),
                              child: Container(
                                decoration: const BoxDecoration(
                                  boxShadow: [BoxShadow(color: Colors.black, offset: Offset(4, 4))]
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(formattedDate, style: GoogleFonts.spaceMono(fontWeight: FontWeight.w500, color: const Color(0xFF6B6556))),
                                          Text("₹${ride['fare']}", style: GoogleFonts.spaceMono(fontWeight: FontWeight.w700, fontSize: 18, color: const Color(0xFFC9A96E))),
                                        ],
                                      ),
                                    const SizedBox(height: 16),
                                    Row(
                                      children: [
                                        const Icon(Icons.my_location, color: Color(0xFFC9A96E), size: 18),
                                        const SizedBox(width: 12),
                                        Expanded(child: Text(ride['pickup'] ?? "Unknown", maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.dmSans(color: const Color(0xFFE8E2D9)))),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        const Icon(Icons.flag, color: Color(0xFFC4BBA8), size: 18),
                                        const SizedBox(width: 12),
                                        Expanded(child: Text(ride['dropoff'] ?? "Unknown", maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.dmSans(color: const Color(0xFFE8E2D9)))),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: ride['status'] == 'PAID' ? const Color(0x22C9A96E) : const Color(0xFF1A1915),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: ride['status'] == 'PAID' ? const Color(0x44C9A96E) : const Color(0xFF2A2820), width: 1),
                                        ),
                                        child: Text(ride['status'] ?? "UNKNOWN", style: GoogleFonts.dmSans(color: ride['status'] == 'PAID' ? const Color(0xFFC9A96E) : const Color(0xFF6B6556), fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: 0.08)),
                                      ),
                                    )
                                  ],
                                ),
                              ),
                            ),
                          );
                          },
                        ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Stack(
        children: [
          // THE MAP (Bottom Layer)
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentLocation,
              initialZoom: 15.0,
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
            ),
            children: [
              TileLayer(
                urlTemplate: "https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png",
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.ridefair.rider',
              ),
              
              // ROUTE LINE (Neon Green)
              if (_routePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      strokeWidth: 5.0,
                      color: const Color(0xFFC9A96E).withValues(alpha: 0.8),
                    ),
                  ],
                ),
                
              MarkerLayer(
                markers: [
                  // Searching Pulse Animation
                  if (_status == "Searching for Drivers...")
                    Marker(
                      point: _currentLocation,
                      width: 150, height: 150,
                      child: Container(
                        decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFFC9A96E).withValues(alpha: 0.2)),
                      ).animate(onPlay: (controller) => controller.repeat())
                       .scale(begin: const Offset(0.5, 0.5), end: const Offset(1.5, 1.5), duration: 1.seconds)
                       .fadeOut(duration: 1.seconds),
                    ),
                  
                  // Rider Location
                  Marker(
                    point: _currentLocation,
                    width: 60,
                    height: 60,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFC9A96E).withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: const Color(0xFFC9A96E),
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFF0A0A0B), width: 3),
                          ),
                        ),
                      ),
                    ),
                  ),
                  
                  // Pickup Flag
                  if (_pickupLat != null)
                    Marker(
                      point: LatLng(_pickupLat!, _pickupLng!),
                      width: 50, height: 50,
                      child: const Icon(Icons.my_location, color: Color(0xFFC9A96E), size: 40),
                    ),
                    
                  // Dropoff Flag
                  if (_dropLat != null)
                    Marker(
                      point: LatLng(_dropLat!, _dropLng!),
                      width: 50, height: 50,
                      child: const Icon(Icons.location_on, color: Color(0xFFC4BBA8), size: 40),
                    ),
                    
                ],
              ),
              
              // LIVE TRACKING VEHICLE LAYER (Smooth Glide Animation)
              if (_driverLocation != null)
                TweenAnimationBuilder<double>(
                  key: ValueKey(_driverLocation),
                  tween: Tween<double>(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.easeOutCubic,
                  builder: (context, t, child) {
                    LatLng currentLoc = _oldDriverLocation == null ? _driverLocation! : LatLng(
                      _oldDriverLocation!.latitude + (_driverLocation!.latitude - _oldDriverLocation!.latitude) * t,
                      _oldDriverLocation!.longitude + (_driverLocation!.longitude - _oldDriverLocation!.longitude) * t,
                    );
                    
                    return MarkerLayer(
                      markers: [
                        Marker(
                          point: currentLoc,
                          width: 60, height: 60,
                          child: Transform.rotate(
                            angle: _driverBearing + (math.pi / 2),
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF1A1915),
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color(0x44C9A96E), width: 1.5)
                              ),
                              child: Image.asset(
                                'assets/icons/${_selectedTier.contains('Bike') ? 'bike' : _selectedTier.contains('Auto') ? 'auto' : 'cab'}.png',
                                width: 48,
                                height: 48,
                                errorBuilder: (context, error, stackTrace) => const Icon(Icons.local_taxi, size: 48),
                              ),
                            )
                          )
                        )
                      ],
                    );
                  },
                ),
            ],
          ),

          // RECENTER BUTTON
          Positioned(
            right: 20,
            bottom: 300,
            child: FloatingActionButton(
              backgroundColor: const Color(0xFFC9A96E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
                side: const BorderSide(color: Color(0xFF0F0F0D), width: 1.5)
              ),
              elevation: 0,
              onPressed: () {
                if (_driverLocation != null) {
                  _mapController.move(_driverLocation!, 16.0);
                } else {
                  _mapController.move(_currentLocation, 16.0);
                }
              },
              child: const Icon(Icons.my_location, color: Color(0xFF0F0F0D)),
            )
          ),

          // WEATHER ALERT BANNER (Phase 18.0)
          if (_weatherAlertMessage != null)
            Positioned(
              top: 50,
              left: 20,
              right: 20,
              child: SafeArea(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F0F0D).withOpacity(0.9),
                    border: Border.all(color: Colors.blueGrey.withOpacity(0.5)),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10)]
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.water_drop, color: Colors.blueAccent),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _weatherAlertMessage!,
                          style: GoogleFonts.dmSans(color: const Color(0xFFE8E2D9), fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Color(0xFF6B6556), size: 18),
                        constraints: const BoxConstraints(),
                        padding: EdgeInsets.zero,
                        onPressed: () {
                          setState(() { _weatherAlertMessage = null; });
                        }
                      )
                    ]
                  )
                )
              )
            ),

          // FLOATING SEARCH UI (Top Layer)
          if (['IDLE', 'COMPLETED'].contains(_rideState))
            SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                children: [
                  // HEADER ROW
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Hello, ${widget.userName}", style: GoogleFonts.cormorantGaramond(color: const Color(0xFFE8E2D9), fontSize: 20, fontWeight: FontWeight.w400)),
                      Row(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF161613),
                              shape: BoxShape.circle,
                              border: Border.all(color: const Color(0xFF1E1C17), width: 1),
                            ),
                            child: IconButton(
                              icon: const Icon(Icons.history, color: Color(0xFFC9A96E)),
                              onPressed: _showRideHistory,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF161613),
                              shape: BoxShape.circle,
                              border: Border.all(color: const Color(0xFF1E1C17), width: 1),
                            ),
                            child: IconButton(
                              icon: const Icon(Icons.logout, color: Color(0xFF6B6556)),
                              onPressed: () async {
                                final prefs = await SharedPreferences.getInstance();
                                await prefs.clear();
                                if (!context.mounted) return;
                                Navigator.pushReplacement(context, MaterialPageRoute(builder: (ctx) => const LoginScreen()));
                              },
                            ),
                          ),
                        ]
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // PICKUP INPUT
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F0F0D), 
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF1E1C17), width: 1)
                    ),
                    child: TextField(
                      controller: _pickupController,
                      style: GoogleFonts.dmSans(color: const Color(0xFFE8E2D9)),
                      decoration: InputDecoration(
                        hintText: "Pickup Location", hintStyle: GoogleFonts.dmSans(color: const Color(0xFF6B6556)),
                        prefixIcon: const Icon(Icons.my_location, color: Color(0xFFC9A96E)),
                        border: InputBorder.none, contentPadding: const EdgeInsets.all(16)
                      ),
                      onTap: () => setState(() => _isSearchingPickup = true),
                      onChanged: _onSearchChanged,
                    ),
                  ),
                  const SizedBox(height: 12),

                    // DROP INPUT
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F0F0D), 
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF1E1C17), width: 1)
                      ),
                      child: TextField(
                        controller: _dropController,
                        style: GoogleFonts.dmSans(color: const Color(0xFFE8E2D9)),
                        decoration: InputDecoration(
                          hintText: "Where to?", hintStyle: GoogleFonts.dmSans(color: const Color(0xFF6B6556)),
                          prefixIcon: const Icon(Icons.flag, color: Color(0xFFC4BBA8)),
                          border: InputBorder.none, contentPadding: const EdgeInsets.all(16)
                        ),
                        onTap: () => setState(() => _isSearchingPickup = false),
                        onChanged: _onSearchChanged,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // QUICK ACCESS CHIPS
                    if (_fare == "0" && !_calculating && _searchResults.isEmpty)
                      Row(
                        children: [
                          ActionChip(
                            backgroundColor: const Color(0xFF161613),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0xFF1E1C17), width: 1)),
                            avatar: const Icon(Icons.home, color: Color(0xFFC4BBA8), size: 16),
                            label: Text("Home", style: GoogleFonts.dmSans(color: const Color(0xFFE8E2D9))),
                            onPressed: () {
                              _dropController.text = "Home";
                              searchAddress("Home");
                            },
                          ),
                          const SizedBox(width: 8),
                          ActionChip(
                            backgroundColor: const Color(0xFF161613),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0xFF1E1C17), width: 1)),
                            avatar: const Icon(Icons.work, color: Color(0xFFC4BBA8), size: 16),
                            label: Text("Work", style: GoogleFonts.dmSans(color: const Color(0xFFE8E2D9))),
                            onPressed: () {
                              _dropController.text = "Work";
                              searchAddress("Work");
                            },
                          ),
                        ],
                      ),
                    const SizedBox(height: 20),

                    // FARE CARD (Shows Price)
                    if (_fare != "0" || _calculating)
                      Container(
                        padding: const EdgeInsets.all(20),
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: const Color(0xFF161613), 
                          borderRadius: BorderRadius.circular(14), 
                          border: Border.all(color: const Color(0xFF1E1C17), width: 1)
                        ),
                        child: _calculating 
                          ? const Center(child: CircularProgressIndicator(color: Color(0xFFC9A96E)))
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                Column(children: [Text("Distance", style: GoogleFonts.dmSans(color: const Color(0xFF6B6556))), Text(_distance, style: GoogleFonts.dmSans(fontWeight: FontWeight.w500, fontSize: 18, color: const Color(0xFFE8E2D9)))]),
                                Column(children: [Text("Estimated Fare", style: GoogleFonts.dmSans(color: const Color(0xFF6B6556))), Text("₹$_fare", style: GoogleFonts.cormorantGaramond(fontWeight: FontWeight.w400, fontSize: 32, color: const Color(0xFFC9A96E)))]),
                              ],
                            ),
                      ),
                    
                    // STATUS TEXT
                    Text(_status, style: GoogleFonts.dmSans(fontSize: 16, fontWeight: FontWeight.w500, color: const Color(0xFF6B6556)), textAlign: TextAlign.center),
                    const SizedBox(height: 16),

                    // BOOK BUTTON
                    Container(
                      width: double.infinity,
                      height: 60,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFC9A96E), 
                          foregroundColor: const Color(0xFF0A0A0B),
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: (_fare == "0") ? null : bookRide,
                        child: Text("REQUEST RIDE", style: GoogleFonts.dmSans(fontSize: 16, fontWeight: FontWeight.w500, letterSpacing: 0.08)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_fare == "0" && !_calculating)
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFF1E1C17), width: 1.5),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          icon: const Icon(Icons.qr_code_scanner, color: Color(0xFFC4BBA8)),
                          label: Text("Scan to Ride (Street-Hail)", style: GoogleFonts.dmSans(color: const Color(0xFFE8E2D9), fontWeight: FontWeight.w500)),
                          onPressed: _openScanner,
                        ),
                      ),
                    // SEARCH LIST OVERLAY OR LOADING STATE
                    if (_isSearching)
                      Container(
                        height: 250,
                        margin: const EdgeInsets.only(top: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF161613),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFF1E1C17)),
                        ),
                        child: Shimmer.fromColors(
                          baseColor: const Color(0xFF161613),
                          highlightColor: const Color(0xFF1E1C17),
                          child: ListView.separated(
                            padding: EdgeInsets.zero,
                            itemCount: 5,
                            separatorBuilder: (context, index) => const Divider(color: Color(0xFF1E1C17), height: 1),
                            itemBuilder: (context, index) => ListTile(
                              leading: Container(width: 40, height: 40, decoration: const BoxDecoration(color: Color(0xFF0F0F0D), shape: BoxShape.circle)),
                              title: Container(height: 12, width: 100, decoration: BoxDecoration(color: const Color(0xFF0F0F0D), borderRadius: BorderRadius.circular(4))),
                              subtitle: Container(height: 10, width: 150, decoration: BoxDecoration(color: const Color(0xFF0F0F0D), borderRadius: BorderRadius.circular(4))),
                            ),
                          ),
                        ),
                      )
                    else if (_dropController.text.length >= 3 && _searchResults.isEmpty && !_isSearching)
                      Container(
                        height: 150,
                        margin: const EdgeInsets.only(top: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF161613),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFF1E1C17)),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.location_off, color: Color(0xFF6B6556), size: 48),
                            const SizedBox(height: 12),
                            Text("Location not found", style: GoogleFonts.dmSans(color: const Color(0xFFE8E2D9), fontWeight: FontWeight.w500)),
                            Text("Try a different search term", style: GoogleFonts.dmSans(color: const Color(0xFF6B6556), fontSize: 13)),
                          ],
                        ),
                      )
                    else if (_dropController.text.isEmpty && _recentSearches.isNotEmpty && !_isSearching)
                      Container(
                        height: 250,
                        margin: const EdgeInsets.only(top: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF161613),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFF1E1C17)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                              child: Text("RECENT", style: GoogleFonts.dmSans(color: const Color(0xFFC9A96E), fontWeight: FontWeight.w500, fontSize: 12, letterSpacing: 1.2)),
                            ),
                            Expanded(
                              child: ListView.separated(
                                padding: EdgeInsets.zero,
                                itemCount: _recentSearches.length,
                                separatorBuilder: (context, index) => const Divider(color: Color(0xFF1E1C17), height: 1),
                                itemBuilder: (ctx, i) {
                                  final place = _recentSearches[i];
                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    leading: Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF0F0F0D), 
                                        shape: BoxShape.circle
                                      ),
                                      child: const Icon(Icons.history, color: Color(0xFF6B6556)),
                                    ),
                                    title: Text(
                                      place['primary_text'] ?? place['display_name'].split(',')[0], 
                                      style: GoogleFonts.dmSans(fontWeight: FontWeight.w500, fontSize: 16, color: const Color(0xFFE8E2D9))
                                    ),
                                    subtitle: Text(
                                      place['secondary_text'] ?? '', 
                                      maxLines: 1, 
                                      overflow: TextOverflow.ellipsis, 
                                      style: GoogleFonts.dmSans(color: const Color(0xFF6B6556), fontSize: 13)
                                    ),
                                    onTap: () => selectLocation(place),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      )
                    else if (_searchResults.isNotEmpty)
                      Container(
                        height: 250,
                        margin: const EdgeInsets.only(top: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF161613), // Sleek secondary dark background
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFF1E1C17)),
                        ),
                        child: ListView.separated(
                          padding: EdgeInsets.zero,
                          itemCount: _searchResults.length,
                          separatorBuilder: (context, index) => const Divider(color: Color(0xFF1E1C17), height: 1),
                          itemBuilder: (ctx, i) {
                            final place = _searchResults[i];
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              leading: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: const BoxDecoration(
                                  color: Color(0x22C9A96E), 
                                  shape: BoxShape.circle
                                ),
                                child: const Icon(Icons.location_on, color: Color(0xFFC9A96E)),
                              ),
                              title: Text(
                                place['primary_text'] ?? place['display_name'].split(',')[0], 
                                style: GoogleFonts.dmSans(fontWeight: FontWeight.w500, fontSize: 16, color: const Color(0xFFE8E2D9))
                              ),
                              subtitle: Text(
                                place['secondary_text'] ?? '', 
                                maxLines: 1, 
                                overflow: TextOverflow.ellipsis, 
                                style: GoogleFonts.dmSans(color: const Color(0xFF6B6556), fontSize: 13)
                              ),
                              onTap: () => selectLocation(place),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
            
          // DYNAMIC STATUS PILL (Top Center)
          if (['ACCEPTED', 'ARRIVED', 'IN_PROGRESS'].contains(_rideState))
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              left: 20, right: 20,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xCC0F0F0D),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: const Color(0xFF2A2820), width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10, height: 10,
                        decoration: const BoxDecoration(color: Color(0xFFC9A96E), shape: BoxShape.circle),
                      ).animate(onPlay: (c) => c.repeat()).fade(duration: 800.ms),
                      const SizedBox(width: 12),
                      Text(_status.split('\n').first, style: GoogleFonts.dmSans(color: const Color(0xFFE8E2D9), fontWeight: FontWeight.w500, fontSize: 14, letterSpacing: 0.04)),
                    ]
                  )
                )
              )
            ).animate().slideY(begin: -1.0, end: 0.0, curve: Curves.easeOutExpo, duration: 500.ms).fadeIn(),

          // TRUST & SAFETY MODULE (SOS)
          if (_rideState == 'IN_PROGRESS')
            Positioned(
              right: 16,
              bottom: 150,
              child: FloatingActionButton(
                backgroundColor: Colors.red.shade900,
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    backgroundColor: Colors.transparent,
                    builder: (ctx) => Container(
                      padding: const EdgeInsets.all(24),
                      decoration: const BoxDecoration(color: Color(0xFF1A1A1A), borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 60),
                          const SizedBox(height: 16),
                          const Text("Emergency SOS", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          const Text("Slide to cancel the ride and alert local authorities immediately.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                          const SizedBox(height: 30),
                          Container(
                            height: 60,
                            decoration: BoxDecoration(color: Colors.redAccent.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(30)),
                            child: Row(
                              children: [
                                Container(margin: const EdgeInsets.all(4), width: 52, height: 52, decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle), child: const Icon(Icons.local_police, color: Colors.white)),
                                const Expanded(child: Center(child: Text("SLIDE TO ALERT", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)))),
                                const SizedBox(width: 52),
                              ]
                            )
                          )
                        ]
                      )
                    )
                  );
                },
                child: const Icon(Icons.shield, color: Colors.white),
              ).animate(onPlay: (c) => c.repeat(reverse: true)).scale(begin: const Offset(1,1), end: const Offset(1.1,1.1), duration: 2.seconds)
            ),

          // BOTTOM PANELS (Driver Identity or Fare Overlay)
          Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation, 
                child: SlideTransition(position: Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(animation), child: child)
              ),
              child: ['ACCEPTED', 'ARRIVED', 'IN_PROGRESS'].contains(_rideState)
                ? KeyedSubtree(
                    key: const ValueKey('driver_card'),
                    child: GestureDetector(
                      onVerticalDragUpdate: (details) {
                        if (details.delta.dy < -5 && !_isHudExpanded) setState(() => _isHudExpanded = true);
                        if (details.delta.dy > 5 && _isHudExpanded) setState(() => _isHudExpanded = false);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        padding: const EdgeInsets.all(24.0),
                        decoration: const BoxDecoration(
                          color: Color(0xFF0F0F0D),
                          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                          border: Border(top: BorderSide(color: Color(0xFF1E1C17), width: 1)),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Drag Indicator
                            Center(
                              child: GestureDetector(
                                onTap: () => setState(() => _isHudExpanded = !_isHudExpanded),
                                child: Container(
                                  width: 40, height: 4,
                                  margin: const EdgeInsets.only(bottom: 20),
                                  decoration: BoxDecoration(color: const Color(0xFF2A2820), borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ),
                            Row(
                              children: [
                                const CircleAvatar(
                                  radius: 30,
                                  backgroundColor: Color(0xFF161613),
                                  child: Icon(Icons.person, color: Color(0xFFC4BBA8), size: 40),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(_status.contains("DRIVER ON THE WAY") ? "Rajesh K." : "Driver", style: GoogleFonts.cormorantGaramond(color: const Color(0xFFE8E2D9), fontSize: 24, fontWeight: FontWeight.w400)),
                                          IconButton(
                                            icon: Icon(_isHudExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up, color: const Color(0xFFC9A96E)),
                                            onPressed: () => setState(() => _isHudExpanded = !_isHudExpanded),
                                            constraints: const BoxConstraints(),
                                            padding: EdgeInsets.zero,
                                          )
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(color: const Color(0xFFE8E2D9), borderRadius: BorderRadius.circular(4)),
                                              child: Text("TN 38 CX 1234 • Suzuki Dzire", overflow: TextOverflow.ellipsis, maxLines: 1, style: GoogleFonts.dmSans(color: const Color(0xFF0A0A0B), fontWeight: FontWeight.w500, fontSize: 12)),
                                            ),
                                          ),
                                          if (_otp != null && ['ACCEPTED', 'ARRIVED'].contains(_rideState)) ...[
                                            const SizedBox(width: 12),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(color: const Color(0xFFC9A96E), borderRadius: BorderRadius.circular(4)),
                                              child: Text("OTP: $_otp", style: GoogleFonts.dmSans(color: const Color(0xFF0A0A0B), fontWeight: FontWeight.w500, fontSize: 12)),
                                            )
                                          ]
                                        ]
                                      )
                                    ],
                                  )
                                ),
                              ]
                            ),
                            // EXPANDED STATE
                            if (_isHudExpanded) ...[
                              const SizedBox(height: 24),
                              const Divider(color: Color(0xFF1E1C17)),
                              const SizedBox(height: 16),
                                if (_pickupAddress != null) ...[
                                  Row(
                                    children: [
                                      const Icon(Icons.my_location, color: Color(0xFFC9A96E), size: 18),
                                      const SizedBox(width: 12),
                                      Expanded(child: Text(_pickupAddress!, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.dmSans(color: const Color(0xFFE8E2D9)))),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                if (_dropAddress != null) ...[
                                  Row(
                                    children: [
                                      const Icon(Icons.flag, color: Color(0xFFC4BBA8), size: 18),
                                      const SizedBox(width: 12),
                                      Expanded(child: Text(_dropAddress!, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.dmSans(color: const Color(0xFFE8E2D9)))),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                ],
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text("Fare", style: GoogleFonts.dmSans(color: const Color(0xFF6B6556))),
                                    Text("₹$_fare", style: GoogleFonts.cormorantGaramond(color: const Color(0xFFE8E2D9), fontSize: 24, fontWeight: FontWeight.w400)),
                                  ],
                                ),
                            ],
                            const SizedBox(height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _buildActionButton(Icons.call, "Call", const Color(0xFFC9A96E), onTap: () => _makeCall(_driverPhone ?? '')),
                                _buildActionButton(Icons.message, "Message", const Color(0xFFE8E2D9), onTap: _showChatSheet),
                                _buildActionButton(Icons.add_location_alt, "Add Stop", const Color(0xFFC4BBA8), onTap: _showAddStopSheet),
                                _buildActionButton(Icons.report_problem_rounded, "Report", Colors.redAccent, onTap: _showReportModal),
                              ]
                            )
                          ]
                        )
                      )
                    )
                  )
                : ((_fare != "0" || _calculating || _status != "Enter Trip Details") 
                    ? KeyedSubtree(
                        key: const ValueKey('fare_overlay'),
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 16.0, sigmaY: 16.0),
                            child: Container(
                              padding: const EdgeInsets.all(24.0),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0A0A0B).withValues(alpha: 0.7),
                                border: const Border(top: BorderSide(color: Color(0x33E8E2D9), width: 1)),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_fare != "0" || _calculating)
                                    Container(
                                        padding: const EdgeInsets.all(20),
                                        margin: const EdgeInsets.only(bottom: 20),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF161613), 
                                          borderRadius: BorderRadius.circular(14), 
                                          border: Border.all(color: const Color(0xFF1E1C17), width: 1)
                                        ),
                                        child: _calculating 
                                          ? const Center(child: CircularProgressIndicator(color: Color(0xFFC9A96E)))
                                          : Column(
                                              children: [
                                                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("Distance Mode (Zero Surge)", style: GoogleFonts.dmSans(color: const Color(0xFFC9A96E))), Text("₹${_tierPrices[_selectedTier] ?? 9}/km", style: GoogleFonts.dmSans(color: const Color(0xFFC9A96E), fontWeight: FontWeight.w700))]),
                                                const SizedBox(height: 8),
                                                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("Distance", style: GoogleFonts.dmSans(color: const Color(0xFF6B6556))), Text(_distance.split(' • ').first, style: GoogleFonts.dmSans(color: const Color(0xFFE8E2D9), fontWeight: FontWeight.w500))]),
                                                const SizedBox(height: 8),
                                                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("Time estimate", style: GoogleFonts.dmSans(color: const Color(0xFF6B6556))), Text(_distance.contains(' • ') ? _distance.split(' • ').last : "0 mins", style: GoogleFonts.dmSans(color: const Color(0xFFE8E2D9), fontWeight: FontWeight.w500))]),
                                                const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(color: Color(0xFF1E1C17))),
                                                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("Total Estimate", style: GoogleFonts.dmSans(color: const Color(0xFF6B6556), fontSize: 16)), Text("₹$_fare", style: GoogleFonts.cormorantGaramond(fontWeight: FontWeight.w400, fontSize: 24, color: const Color(0xFFC9A96E)))]),
                                              ],
                                            ),
                                      ),
                                  
                                  if (_fare != "0" && !_calculating)
                                    Container(
                                      height: 100,
                                      margin: const EdgeInsets.only(bottom: 20),
                                      child: ListView(
                                        scrollDirection: Axis.horizontal,
                                        children: [
                                          _buildTierCard('Equinox-Bike', Icons.motorcycle, '₹9/km'),
                                          const SizedBox(width: 12),
                                          _buildTierCard('Fair-Auto', Icons.electric_rickshaw, '₹15/km'),
                                          const SizedBox(width: 12),
                                          _buildTierCard('Fair-Cab', Icons.local_taxi, '₹22/km'),
                                        ],
                                      ),
                                    ),

                                  if (_fare != "0" && !_calculating)
                                    Column(
                                      children: [
                                        Container(
                                          height: 6,
                                          width: double.infinity,
                                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(3)),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                flex: 30,
                                                child: Container(
                                                  decoration: const BoxDecoration(
                                                    color: Color(0xFF6B6556),
                                                    borderRadius: BorderRadius.horizontal(left: Radius.circular(3))
                                                  )
                                                ),
                                              ),
                                              Expanded(
                                                flex: 70,
                                                child: Container(
                                                  decoration: const BoxDecoration(
                                                    color: Color(0xFF4ADE80),
                                                    borderRadius: BorderRadius.horizontal(right: Radius.circular(3))
                                                  )
                                                ),
                                              ),
                                            ]
                                          )
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text("Fuel Cost (30%)", style: GoogleFonts.dmSans(color: const Color(0xFF6B6556), fontSize: 13, fontWeight: FontWeight.w500)),
                                            Text("Driver Profit (70%)", style: GoogleFonts.dmSans(color: const Color(0xFF4ADE80), fontSize: 13, fontWeight: FontWeight.w500)),
                                          ],
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          "Zero Surge. Zero Commission. Pure Physics.",
                                          style: GoogleFonts.spaceMono(color: const Color(0xFFC9A96E), fontSize: 11, letterSpacing: 0.5),
                                          textAlign: TextAlign.center,
                                        ),
                                        const SizedBox(height: 16),
                                      ],
                                    ),
                                  
                                  Text(_status, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey), textAlign: TextAlign.center),
                                  const SizedBox(height: 16),

                                  Container(
                                    width: double.infinity,
                                    height: 60,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(color: const Color(0xFFC9A96E).withValues(alpha: 0.1), blurRadius: 20, offset: const Offset(0, 10))
                                      ],
                                    ),
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFFC9A96E), 
                                        foregroundColor: Colors.black,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                      ),
                                      onPressed: (_fare == "0") ? null : bookRide,
                                      child: const Text("CONFIRM RIDE", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                    ),
                                  )
                                ],
                              ),
                            ),
                          ),
                        ),
                      )
                    : const SizedBox.shrink()),
            ),
          ),
        ],
      ),
    );
  }

  void _updateFareForTier(dynamic tier) {
    setState(() {
      _selectedTier = tier.toString();
      if (_distance.contains(' • ')) {
        final parts = _distance.split(' • ');
        double km = double.tryParse(parts[0].replaceAll(' km', '').trim()) ?? 0.0;
        double pricePerKm = _tierPrices[_selectedTier] ?? 9.0;
        _fare = (km * pricePerKm).round().toString();
      }
    });
  }

  Widget _buildTierCard(String tier, IconData icon, String multiplierStr) {
    bool isSelected = _selectedTier == tier;
    return GestureDetector(
      onTap: () {
        if (!kIsWeb) { try { Vibration.vibrate(duration: 50, amplitude: 50); } catch (_) {} }
        _updateFareForTier(tier);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 110,
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFC9A96E) : const Color(0xFF161613),
          borderRadius: BorderRadius.circular(0),
          border: Border.all(color: Colors.black, width: 1.5),
          boxShadow: const [BoxShadow(color: Colors.black, offset: Offset(4, 4))]
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: isSelected ? Colors.black : const Color(0xFF6B6556), size: 32),
            const SizedBox(height: 8),
            Text(tier, style: TextStyle(color: isSelected ? Colors.black : const Color(0xFFE8E2D9), fontWeight: FontWeight.bold, fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily)),
            Text(multiplierStr, style: TextStyle(color: isSelected ? Colors.black87 : const Color(0xFF6B6556), fontSize: 12, fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily)),
          ]
        ),
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String label, Color color, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: () {
        if (!kIsWeb) { try { Vibration.vibrate(duration: 50, amplitude: 50); } catch (_) {} }
        if (onTap != null) onTap();
      },
      child: Column(
        children: [
          Container(
            width: 50, height: 50,
            decoration: BoxDecoration(color: const Color(0xFF161613), shape: BoxShape.circle, border: Border.all(color: const Color(0xFF1E1C17), width: 1)),
            child: Icon(icon, color: const Color(0xFFC9A96E)),
          ),
          const SizedBox(height: 8),
          Text(label, style: GoogleFonts.dmSans(color: const Color(0xFF6B6556), fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  void _showAddStopSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          return Container(
            height: MediaQuery.of(ctx).size.height * 0.85,
            decoration: const BoxDecoration(
              color: Color(0xFF0F0F0D),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  children: [
                    Text("Add Mid-Trip Stop", style: GoogleFonts.cormorantGaramond(color: const Color(0xFFE8E2D9), fontSize: 24)),
                    const SizedBox(height: 16),
                    TextField(
                      autofocus: true,
                      style: GoogleFonts.dmSans(color: const Color(0xFFE8E2D9)),
                      decoration: InputDecoration(
                        hintText: "Search location...", hintStyle: GoogleFonts.dmSans(color: const Color(0xFF6B6556)),
                        prefixIcon: const Icon(Icons.search, color: Color(0xFFC9A96E)),
                        filled: true, fillColor: const Color(0xFF1E1C17),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none)
                      ),
                      onChanged: (val) async {
                        if (val.length >= 3) {
                          final results = await _locationService.searchPlaces(val);
                          setSheetState(() {
                            _searchResults = results;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: ListView.separated(
                        itemCount: _searchResults.length,
                        separatorBuilder: (ctx, i) => const Divider(color: Color(0xFF1E1C17)),
                        itemBuilder: (ctx, i) {
                          final place = _searchResults[i];
                          return ListTile(
                            leading: const Icon(Icons.add_location_alt, color: Color(0xFFC9A96E)),
                            title: Text(place['primary_text'] ?? place['display_name'].split(',')[0], style: GoogleFonts.dmSans(color: Colors.white)),
                            subtitle: Text(place['secondary_text'] ?? '', style: GoogleFonts.dmSans(color: Colors.grey)),
                            onTap: () {
                              double newLat = double.parse(place['lat']);
                              double newLng = double.parse(place['lon']);
                              
                              socket.emit("update_route", {
                                "rideId": _rideHistory.isNotEmpty ? _rideHistory.first['id'] : null, // Not strictly true if _rideHistory isn't updated. Hmm. Wait, rider app doesn't save active rideId in state? It is active!
                                "riderPhone": widget.userPhone,
                                "driverPhone": _driverPhone,
                                "dropLat": _dropLat,
                                "dropLng": _dropLng,
                                "tierMultiplier": _tierPrices[_selectedTier],
                                "waypoint": {
                                   "lat": newLat,
                                   "lng": newLng,
                                   "address": place['display_name']
                                }
                              });
                              setState(() {
                                _status = "Recalculating routing physics...";
                                _searchResults = [];
                              });
                              Navigator.pop(ctx);
                            },
                          );
                        }
                      )
                    )
                  ]
                )
              )
            )
          );
        }
      )
    );
  }

  void _openScanner() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.7,
        decoration: const BoxDecoration(
          color: Color(0xFF0F0F0D),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Text("Scan Driver QR", style: GoogleFonts.cormorantGaramond(color: const Color(0xFFE8E2D9), fontSize: 24)),
            ),
            Expanded(
              child: MobileScanner(
                onDetect: (capture) {
                  final List<Barcode> barcodes = capture.barcodes;
                  if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
                    final driverPhone = barcodes.first.rawValue!;
                    socket.emit("qr_pair_request", {
                      "riderPhone": widget.userPhone,
                      "driverPhone": driverPhone,
                    });
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Pairing with driver...")));
                  }
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text("CANCEL", style: GoogleFonts.dmSans(color: const Color(0xFF6B6556))),
              ),
            )
          ]
        )
      )
    );
  }

  void _showReportModal() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF0F0F0D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0xFF1E1C17))),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.report_problem, color: Colors.redAccent, size: 48),
              const SizedBox(height: 16),
              Text("Report Driver", style: GoogleFonts.cormorantGaramond(color: Colors.white, fontSize: 24)),
              const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E1C17),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                ),
                onPressed: () {
                  socket.emit("report_driver", {
                    "driverPhone": _driverPhone,
                    "riderPhone": widget.userPhone,
                    "reason": "Extra Money Demanded"
                  });
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Report submitted anonymously.")));
                },
                child: const Text("Extra Money Demanded"),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("CANCEL", style: TextStyle(color: Colors.grey)),
              )
            ],
          )
        )
      )
    );
  }

  void _showChatSheet() {
    final TextEditingController msgController = TextEditingController();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Container(
            height: MediaQuery.of(ctx).size.height * 0.6,
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            decoration: BoxDecoration(
              color: const Color(0xFF0F0F0D).withOpacity(0.95),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: const Border(top: BorderSide(color: Color(0xFF1E1C17), width: 1)),
            ),
            child: SafeArea(
              child: Column(
                children: [
                   Padding(
                     padding: const EdgeInsets.all(16.0),
                     child: Text("Active Chat", style: GoogleFonts.dmSans(color: const Color(0xFFE8E2D9), fontSize: 18, fontWeight: FontWeight.bold)),
                   ),
                   Expanded(
                     child: ListView.builder(
                       reverse: true,
                       itemCount: _chatMessages.length,
                       itemBuilder: (ctx, index) {
                         final msg = _chatMessages[_chatMessages.length - 1 - index];
                         bool isMe = msg['sender'] == 'Rider';
                         return Align(
                           alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                           child: Container(
                             margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
                             padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                             decoration: BoxDecoration(
                               color: isMe ? const Color(0xFFC9A96E) : const Color(0xFF1E1C17),
                               borderRadius: BorderRadius.circular(16),
                             ),
                             child: Text(msg['text'] ?? '', style: GoogleFonts.dmSans(color: isMe ? const Color(0xFF0A0A0B) : const Color(0xFFE8E2D9))),
                           ),
                         );
                       }
                     ),
                   ),
                   Padding(
                     padding: const EdgeInsets.all(12.0),
                     child: Row(
                       children: [
                         Expanded(
                           child: TextField(
                             controller: msgController,
                             style: const TextStyle(color: Colors.white),
                             decoration: InputDecoration(
                               hintText: "Enter message...",
                               hintStyle: const TextStyle(color: Colors.white54),
                               filled: true,
                               fillColor: const Color(0xFF1E1C17),
                               border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                               contentPadding: const EdgeInsets.symmetric(horizontal: 20)
                             ),
                           )
                         ),
                         const SizedBox(width: 8),
                         CircleAvatar(
                           backgroundColor: const Color(0xFFC9A96E),
                           child: IconButton(
                             icon: const Icon(Icons.send, color: Color(0xFF0A0A0B)),
                             onPressed: () {
                               if (msgController.text.trim().isEmpty) return;
                               final targetRoom = _rideState == 'ACCEPTED' && _status.contains('Street Hail') 
                                                ? 'room_qr_${widget.userPhone}_$_driverPhone' 
                                                : 'driver_$_driverPhone';
                               socket.emit("send_message", {
                                 "room_id": targetRoom,
                                 "sender": "Rider",
                                 "text": msgController.text.trim()
                               });
                               setState(() {
                                 _chatMessages.add({"sender": "Rider", "text": msgController.text.trim()});
                               });
                               setSheetState((){});
                               msgController.clear();
                             }
                           )
                         )
                       ]
                     )
                   )
                ]
              )
            )
          );
        }
      )
    );
  }

  void _showPaymentBottomSheet(dynamic data) {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  color: Color(0xFF0F0F0D),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                  border: Border(top: BorderSide(color: Color(0xFF1E1C17), width: 1)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text("Trip Ended", style: GoogleFonts.cormorantGaramond(color: const Color(0xFFE8E2D9), fontSize: 24, fontWeight: FontWeight.w400)),
                    const SizedBox(height: 16),
                    Text("Total: ₹${data['fare']}", style: GoogleFonts.cormorantGaramond(color: const Color(0xFFC9A96E), fontSize: 40, fontWeight: FontWeight.w400)),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFC9A96E),
                          foregroundColor: const Color(0xFF0A0A0B),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: _isPaymentProcessing ? null : () {
                          setSheetState(() => _isPaymentProcessing = true);
                          
                          // Timer setup for Phase 5.1
                          bool handled = false;
                          
                          socket.once("payment_failed", (failData) {
                            handled = true;
                            if (mounted) {
                              setSheetState(() => _isPaymentProcessing = false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(failData['error'] ?? "Payment failed"), backgroundColor: Colors.red)
                              );
                            }
                          });

                          socket.once("payment_successful", (_) {
                             handled = true;
                          });

                          socket.emit("process_payment", {
                            "rideId": data['rideId'],
                            "fare": data['fare'],
                            "riderPhone": widget.userPhone,
                            "driverPhone": data['driverPhone'],
                            "riderId": socket.id
                          });

                          Future.delayed(const Duration(seconds: 10), () {
                            if (!handled && mounted && _isPaymentProcessing) {
                               // Reset state after 10s deadlock
                               setSheetState(() => _isPaymentProcessing = false);
                               ScaffoldMessenger.of(context).showSnackBar(
                                 const SnackBar(content: Text("Payment network timeout."), backgroundColor: Colors.red)
                               );
                            }
                          });
                        },
                        child: _isPaymentProcessing 
                          ? const CircularProgressIndicator(color: Color(0xFF0A0A0B))
                          : Text("PAY FOR RIDE", style: GoogleFonts.dmSans(color: const Color(0xFF0A0A0B), fontWeight: FontWeight.w500, fontSize: 18, letterSpacing: 0.08)),
                      ),
                    )
                  ],
                )
              );
          }
        );
      }
    );
  }
}
