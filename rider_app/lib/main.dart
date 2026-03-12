import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'dart:ui';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:math' as math;
import 'login_screen.dart';
import 'ride_history_screen.dart';
import 'checkout_screen.dart';

void main() {
  runApp(const RiderApp());
}

class RiderApp extends StatelessWidget {
  const RiderApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true, 
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00FF7F), // Neon Green
          surface: Color(0xFF1E1E1E), // Dark Grey components
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: IconThemeData(color: Colors.white),
          titleTextStyle: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
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

    if (phone != null && phone.isNotEmpty) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => RiderHomeScreen(userName: name, userPhone: phone)),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF121212),
      body: Center(
        child: CircularProgressIndicator(color: Color(0xFF00FF7F)),
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

class _RiderHomeScreenState extends State<RiderHomeScreen> with TickerProviderStateMixin {
  late IO.Socket socket;
  
  // -- CONTROLLERS --
  final TextEditingController _pickupController = TextEditingController();
  final TextEditingController _dropController = TextEditingController();

  // -- STATE VARIABLES --
  List<dynamic> _searchResults = [];
  bool _isSearchingPickup = true; 
  Timer? _debounce;
  
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
  int _basePrice = 0;
  String _distance = "0 km";
  bool _calculating = false;
  String _status = "Enter Trip Details";
  
  // Tier Data
  String _selectedTier = 'Fair-Mini';
  final Map<String, double> _tierMultipliers = {'Fair-Auto': 0.8, 'Fair-Mini': 1.0, 'Fair-Prime': 1.5};
  
  String? _driverPhone;
  
  final MapController _mapController = MapController();
  LatLng _currentLocation = const LatLng(12.9716, 77.5946); // Default
  List<LatLng> _routePoints = []; 
  LatLng? _driverLocation; 

  // History State
  List<dynamic> _rideHistory = [];
  String _rideState = "IDLE";

  // Animation State
  late AnimationController _driverAnimController;
  LatLng? _oldDriverLocation;
  double _driverBearing = 0.0;

  LatLng get _animDriverLocation {
    if (_oldDriverLocation != null && _driverLocation != null) {
      final t = _driverAnimController.value;
      return LatLng(
        _oldDriverLocation!.latitude + (_driverLocation!.latitude - _oldDriverLocation!.latitude) * t,
        _oldDriverLocation!.longitude + (_driverLocation!.longitude - _oldDriverLocation!.longitude) * t,
      );
    }
    return _driverLocation ?? const LatLng(0,0);
  }

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
    _driverAnimController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));
    _driverAnimController.addListener(() {
      setState(() {});
    });
    _determinePosition();
    connectToServer();
    fetchMyRides();
  }

  Future<void> fetchMyRides() async {
    final url = Uri.parse("${const String.fromEnvironment('SUPABASE_URL')}/rest/v1/rides?rider_phone=eq.${widget.userPhone}&order=created_at.desc");
    try {
      final response = await http.get(
        url,
        headers: {
          "apikey": const String.fromEnvironment('SUPABASE_KEY'),
          "Authorization": "Bearer ${const String.fromEnvironment('SUPABASE_KEY')}"
        }
      );
      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            _rideHistory = jsonDecode(response.body);
          });
        }
      }
    } catch (e) {
      // ignore
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
    socket = IO.io('http://localhost:3000', <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
    });
    socket.connect();

    socket.on("ride_accepted", (data) {
      if (mounted) {
        setState(() {
          _rideState = "ACCEPTED";
          _driverPhone = data['driverPhone'];
          _status = "✅ DRIVER ON THE WAY!\nCar: ${data['carNumber']}";
        });
      }
    });

    socket.on("ride_status_change", (data) {
      if (data['status'] == 'ACCEPTED' || data['status'] == 'ARRIVED') {
        Vibration.vibrate(duration: 500);
      }
      if (mounted) {
        setState(() {
           _rideState = data['status'];
           _status = data['message'] ?? data['status'];
        });
      }
      if (data['status'] == 'COMPLETED') {
         fetchMyRides(); // Keep strictly fresh automatically 
         Navigator.push(
           context, 
           MaterialPageRoute(
             builder: (context) => CheckoutScreen(
               fare: _fare, 
               riderPhone: widget.userPhone, 
               driverPhone: _driverPhone ?? "Unknown", 
               rideId: data['rideId']?.toString() ?? "0"
             )
           )
         ).then((_) {
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
         });
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
          _oldDriverLocation = _driverLocation;
          _driverLocation = newLoc;
          _driverBearing = _calculateBearing(_oldDriverLocation!, _driverLocation!);
          _driverAnimController.forward(from: 0.0);
        }
      }
    });
  }

  // --- 1. SEARCH PLACES (PHOTON API WITH PROXIMITY BIAS) ---
  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      searchAddress(query);
    });
  }

  Future<void> searchAddress(String query) async {
    if (query.length < 3) {
      if (_searchResults.isNotEmpty) setState(() => _searchResults = []);
      return;
    }

    // PHOTON API + Proximity Biasing using Geolocator's _currentLocation
    final url = Uri.parse(
      "https://photon.komoot.io/api/?q=$query&lat=${_currentLocation.latitude}&lon=${_currentLocation.longitude}&limit=5"
    );

    try {
      final response = await http.get(url, headers: {"User-Agent": "RideFair_Project/1.0"});
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final features = data['features'] as List<dynamic>? ?? [];
        
        setState(() {
          // Map Photon GeoJSON to the existing UI's expected format
          _searchResults = features.map((f) {
            final props = f['properties'] ?? {};
            final coords = f['geometry']['coordinates'] ?? [0.0, 0.0]; // [lon, lat]
            
            String primaryText = props['name']?.toString() ?? props['street']?.toString() ?? props['locality']?.toString() ?? props['neighbourhood']?.toString() ?? 'Unknown Location';
            
            final secParts = <String>[];
            if (props['street'] != null && props['street'] != primaryText) secParts.add(props['street'].toString());
            if (props['locality'] != null && props['locality'] != primaryText) secParts.add(props['locality'].toString());
            if (props['neighbourhood'] != null && props['neighbourhood'] != primaryText) secParts.add(props['neighbourhood'].toString());
            if (props['city'] != null && props['city'] != primaryText) secParts.add(props['city'].toString());
            if (props['state'] != null && props['state'] != primaryText) secParts.add(props['state'].toString());
            
            String secondaryText = secParts.isNotEmpty ? secParts.join(', ') : 'Details unavailable';
            String displayName = '$primaryText, $secondaryText';
            
            return {
              'display_name': displayName,
              'primary_text': primaryText,
              'secondary_text': secondaryText,
              'lat': coords[1].toString(), // Lat is index 1
              'lon': coords[0].toString(), // Lon is index 0
            };
          }).toList();
        });
      }
    } catch (e) {
      // ignore
    }
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
        
        // PRICING LOGIC: Base Fare (50) + (Kilometers * 15) + (Minutes * 2)
        int price = (50 + (km * 15) + (minutes * 2)).round();

        // ROUTE PARSING
        final List<dynamic> coords = data['routes'][0]['geometry']['coordinates'];
        List<LatLng> points = coords.map((c) => LatLng(c[1], c[0])).toList();

        setState(() {
          _distance = "${km.toStringAsFixed(1)} km • ${minutes.toStringAsFixed(0)} mins";
          _fare = price.toString();
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
      print("Routing Error: $e");
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
              decoration: BoxDecoration(
                color: const Color(0xFF121212),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 20, spreadRadius: 5)
                ]
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    height: 5,
                    width: 40,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade700,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: Text("My Rides", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                  Expanded(
                    child: _rideHistory.isEmpty
                      ? const Center(child: Text("No past rides found", style: TextStyle(color: Colors.grey, fontSize: 16)))
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
                              color: const Color(0xFF1E1E1E),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFF2A2A2A))),
                              margin: const EdgeInsets.only(bottom: 16),
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(formattedDate, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                                        Text("₹${ride['fare']}", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF00FF7F))),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    Row(
                                      children: [
                                        const Icon(Icons.my_location, color: Color(0xFF00FF7F), size: 18),
                                        const SizedBox(width: 12),
                                        Expanded(child: Text(ride['pickup'] ?? "Unknown", maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white))),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        const Icon(Icons.flag, color: Colors.white, size: 18),
                                        const SizedBox(width: 12),
                                        Expanded(child: Text(ride['dropoff'] ?? "Unknown", maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white))),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: ride['status'] == 'PAID' ? const Color(0xFF00FF7F).withOpacity(0.1) : Colors.grey.shade900,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: ride['status'] == 'PAID' ? const Color(0xFF00FF7F) : Colors.grey.shade700)
                                        ),
                                        child: Text(ride['status'] ?? "UNKNOWN", style: TextStyle(color: ride['status'] == 'PAID' ? const Color(0xFF00FF7F) : Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                                      ),
                                    )
                                  ],
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
      backgroundColor: const Color(0xFF121212),
      body: Stack(
        children: [
          // THE MAP (Bottom Layer)
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentLocation,
              initialZoom: 15.0,
            ),
            children: [
              TileLayer(
                urlTemplate: "https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png",
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
                      color: const Color(0xFF00FF7F).withOpacity(0.8),
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
                        decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF00FF7F).withOpacity(0.2)),
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
                        color: const Color(0xFF00FF7F).withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: const Color(0xFF00FF7F),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.black, width: 3),
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
                      child: const Icon(Icons.location_on, color: Colors.blueAccent, size: 40),
                    ),
                    
                  // Dropoff Flag
                  if (_dropLat != null)
                    Marker(
                      point: LatLng(_dropLat!, _dropLng!),
                      width: 50, height: 50,
                      child: const Icon(Icons.flag, color: Colors.orange, size: 40),
                    ),
                    
                  // Driver Car (Live Tracking)
                  if (_driverLocation != null)
                     Marker(
                        point: _animDriverLocation,
                        width: 60, height: 60,
                        child: Transform.rotate(
                          angle: _driverBearing,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10)]
                            ),
                            child: const Icon(Icons.navigation, color: Colors.blueAccent, size: 40)
                          )
                        )
                     )
                ],
              ),
            ],
          ),

          // FLOATING SEARCH UI (Top Layer)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  // HEADER ROW
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Hello, ${widget.userName}", style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                      Row(
                        children: [
                          Container(
                            decoration: const BoxDecoration(
                              color: Color(0xFF2C2C2C),
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              icon: const Icon(Icons.history, color: Color(0xFF00FF7F)),
                              onPressed: _showRideHistory,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            decoration: const BoxDecoration(
                              color: Color(0xFF2C2C2C),
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              icon: const Icon(Icons.logout, color: Colors.redAccent),
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
                    decoration: BoxDecoration(color: const Color(0xFF2C2C2C), borderRadius: BorderRadius.circular(16)),
                    child: TextField(
                      controller: _pickupController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: "Pickup Location", hintStyle: TextStyle(color: Colors.grey.shade600),
                        prefixIcon: const Icon(Icons.my_location, color: Color(0xFF00FF7F)),
                        border: InputBorder.none, contentPadding: const EdgeInsets.all(16)
                      ),
                      onTap: () => setState(() => _isSearchingPickup = true),
                      onChanged: _onSearchChanged,
                    ),
                  ),
                  const SizedBox(height: 12),

                    // DROP INPUT
                    Container(
                      decoration: BoxDecoration(color: const Color(0xFF2C2C2C), borderRadius: BorderRadius.circular(16)),
                      child: TextField(
                        controller: _dropController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: "Where to?", hintStyle: TextStyle(color: Colors.grey.shade600),
                          prefixIcon: const Icon(Icons.flag, color: Color(0xFF00FF7F)),
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
                            backgroundColor: const Color(0xFF2C2C2C),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide.none),
                            avatar: const Icon(Icons.home, color: Colors.white, size: 16),
                            label: const Text("Home", style: TextStyle(color: Colors.white)),
                            onPressed: () {
                              _dropController.text = "Home";
                              searchAddress("Home");
                            },
                          ),
                          const SizedBox(width: 8),
                          ActionChip(
                            backgroundColor: const Color(0xFF2C2C2C),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide.none),
                            avatar: const Icon(Icons.work, color: Colors.white, size: 16),
                            label: const Text("Work", style: TextStyle(color: Colors.white)),
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
                          color: const Color(0xFF2C2C2C), 
                          borderRadius: BorderRadius.circular(16), 
                          border: Border.all(color: const Color(0xFF00FF7F).withOpacity(0.3))
                        ),
                        child: _calculating 
                          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00FF7F)))
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                Column(children: [const Text("Distance", style: TextStyle(color: Colors.grey)), Text(_distance, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white))]),
                                Column(children: [const Text("Estimated Fare", style: TextStyle(color: Colors.grey)), Text("₹$_fare", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 24, color: Color(0xFF00FF7F)))]),
                              ],
                            ),
                      ),
                    
                    // STATUS TEXT
                    Text(_status, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey), textAlign: TextAlign.center),
                    const SizedBox(height: 16),

                    // BOOK BUTTON
                    Container(
                      width: double.infinity,
                      height: 60,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(color: const Color(0xFF00FF7F).withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))
                        ],
                      ),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00FF7F), 
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: (_fare == "0") ? null : bookRide,
                        child: const Text("REQUEST RIDE", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // DROP INPUT
                    Container(
                      decoration: BoxDecoration(color: const Color(0xFF2C2C2C), borderRadius: BorderRadius.circular(16)),
                      child: TextField(
                        controller: _dropController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: "Where to?", hintStyle: TextStyle(color: Colors.grey.shade600),
                          prefixIcon: const Icon(Icons.flag, color: Color(0xFF00FF7F)),
                          border: InputBorder.none, contentPadding: const EdgeInsets.all(16)
                        ),
                        onTap: () => setState(() => _isSearchingPickup = false),
                        onChanged: _onSearchChanged,
                      ),
                    ),
                    // SEARCH LIST OVERLAY (Inside the top container to float perfectly below inputs)
                    if (_searchResults.isNotEmpty)
                      Container(
                        height: 250,
                        margin: const EdgeInsets.only(top: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1E1E), // Sleek secondary dark background
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFF2A2A2A)),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10, offset: const Offset(0, 5))
                          ]
                        ),
                        child: ListView.separated(
                          padding: EdgeInsets.zero,
                          itemCount: _searchResults.length,
                          separatorBuilder: (context, index) => const Divider(color: Color(0xFF2A2A2A), height: 1),
                          itemBuilder: (ctx, i) {
                            final place = _searchResults[i];
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              leading: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00FF7F).withOpacity(0.1), 
                                  shape: BoxShape.circle
                                ),
                                child: const Icon(Icons.location_on, color: Color(0xFF00FF7F)),
                              ),
                              title: Text(
                                place['primary_text'] ?? place['display_name'].split(',')[0], 
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)
                              ),
                              subtitle: Text(
                                place['secondary_text'] ?? '', 
                                maxLines: 1, 
                                overflow: TextOverflow.ellipsis, 
                                style: const TextStyle(color: Colors.grey, fontSize: 13)
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
            
          // DYNAMIC STATUS PILL (Top Center)
          if (['ACCEPTED', 'ARRIVED', 'IN_PROGRESS'].contains(_rideState))
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              left: 20, right: 20,
              child: Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: Colors.white.withOpacity(0.2)),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10)]
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 10, height: 10,
                            decoration: const BoxDecoration(color: Color(0xFF00FF7F), shape: BoxShape.circle),
                          ).animate(onPlay: (c) => c.repeat()).fade(duration: 800.ms),
                          const SizedBox(width: 12),
                          Text(_status.split('\n').first, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                        ]
                      )
                    )
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
                      decoration: const BoxDecoration(color: Color(0xFF1E1E1E), borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
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
                            decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.2), borderRadius: BorderRadius.circular(30)),
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

          // DRIVER IDENTITY CARD
          if (['ACCEPTED', 'ARRIVED', 'IN_PROGRESS'].contains(_rideState))
            Align(
              alignment: Alignment.bottomCenter,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
                  child: Container(
                    padding: const EdgeInsets.all(24.0),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E1E).withOpacity(0.85),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                      border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20, spreadRadius: 5)]
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            const CircleAvatar(
                              radius: 30,
                              backgroundColor: Colors.grey,
                              child: Icon(Icons.person, color: Colors.white, size: 40),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(_status.contains("DRIVER ON THE WAY") ? "Rajesh K." : "Driver", style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(color: const Color(0xFF2C2C2C), borderRadius: BorderRadius.circular(8)),
                                        child: const Row(children: [Icon(Icons.star, color: Colors.amber, size: 14), Text("4.9", style: TextStyle(color: Colors.white, fontSize: 12))]),
                                      )
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
                                    child: const Text("TN 38 CX 1234 • Maruti Suzuki Dzire", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12)),
                                  )
                                ],
                              )
                            ),
                          ]
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildActionButton(Icons.call, "Call", const Color(0xFF00FF7F)),
                            _buildActionButton(Icons.message, "Message", Colors.blueAccent),
                          ]
                        )
                      ]
                    )
                  )
                )
              )
            ).animate().slideY(begin: 1.0, end: 0.0, curve: Curves.easeOutExpo, duration: 500.ms).fadeIn(),

          // BOTTOM SHEET / FARE OVERLAY
          if ((_fare != "0" || _calculating || _status != "Enter Trip Details") && !['ACCEPTED', 'ARRIVED', 'IN_PROGRESS'].contains(_rideState))
            Align(
              alignment: Alignment.bottomCenter,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
                  child: Container(
                    padding: const EdgeInsets.all(24.0),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E1E).withOpacity(0.85),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                      border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20, spreadRadius: 5)
                      ]
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_fare != "0" || _calculating)
                          Container(
                            padding: const EdgeInsets.all(20),
                            margin: const EdgeInsets.only(bottom: 20),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2C2C2C).withOpacity(0.6), 
                              borderRadius: BorderRadius.circular(16), 
                              border: Border.all(color: const Color(0xFF00FF7F).withOpacity(0.3))
                            ),
                            child: _calculating 
                              ? const Center(child: CircularProgressIndicator(color: Color(0xFF00FF7F)))
                              : Column(
                                  children: [
                                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Base Fare", style: TextStyle(color: Colors.grey)), const Text("₹50", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))]),
                                    const SizedBox(height: 8),
                                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Distance", style: TextStyle(color: Colors.grey)), Text(_distance.split(' • ').first, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))]),
                                    const SizedBox(height: 8),
                                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Time", style: TextStyle(color: Colors.grey)), Text(_distance.contains(' • ') ? _distance.split(' • ').last : "0 mins", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))]),
                                    const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(color: Color(0xFF2A2A2A))),
                                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Total Estimate", style: TextStyle(color: Colors.grey, fontSize: 16)), Text("₹$_fare", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 24, color: Color(0xFF00FF7F)))]),
                                  ],
                                ),
                          ),
                          
                        // TIER SELECTOR
                        if (_fare != "0" && !_calculating)
                          Container(
                            height: 100,
                            margin: const EdgeInsets.only(bottom: 20),
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: [
                                _buildTierCard('Fair-Auto', Icons.electric_rickshaw, '0.8x'),
                                const SizedBox(width: 12),
                                _buildTierCard('Fair-Mini', Icons.directions_car, '1.0x'),
                                const SizedBox(width: 12),
                                _buildTierCard('Fair-Prime', Icons.local_taxi, '1.5x'),
                              ],
                            ),
                          ),
                        
                        // STATUS TEXT
                        Text(_status, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey), textAlign: TextAlign.center),
                        const SizedBox(height: 16),

                        // BOOK BUTTON
                        Container(
                          width: double.infinity,
                          height: 60,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(color: const Color(0xFF00FF7F).withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))
                            ],
                          ),
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00FF7F), 
                              foregroundColor: Colors.black,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            onPressed: (_fare == "0") ? null : bookRide,
                            child: const Text("REQUEST RIDE", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          ),
                        )
                      ],
                    ),
                  ),
                ),
              ).animate().slideY(begin: 1.0, end: 0.0, curve: Curves.easeOutExpo, duration: 500.ms).fadeIn(),
            ),
        ],
      ),
    );
  }

  Widget _buildTierCard(String tier, IconData icon, String multiplierStr) {
    bool isSelected = _selectedTier == tier;
    return GestureDetector(
      onTap: () => _updateFareForTier(tier),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 110,
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF00FF7F).withOpacity(0.2) : const Color(0xFF2C2C2C).withOpacity(0.6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isSelected ? const Color(0xFF00FF7F) : Colors.transparent, width: 2),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: isSelected ? const Color(0xFF00FF7F) : Colors.grey, size: 32),
            const SizedBox(height: 8),
            Text(tier, style: TextStyle(color: isSelected ? Colors.white : Colors.grey, fontWeight: FontWeight.bold)),
            Text(multiplierStr, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String label, Color color) {
    return Column(
      children: [
        Container(
          width: 50, height: 50,
          decoration: BoxDecoration(color: const Color(0xFF2C2C2C), shape: BoxShape.circle, border: Border.all(color: color.withOpacity(0.3))),
          child: Icon(icon, color: color),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }
}