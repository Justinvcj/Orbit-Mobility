import 'dart:async'; // For the timer
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';
import 'dart:ui';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:math' as math;
import 'earnings_screen.dart';
import 'login_screen.dart';

class MapScreen extends StatefulWidget {
  final String driverName;
  final String driverPhone;

  const MapScreen({super.key, required this.driverName, required this.driverPhone});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // CONTROLLERS
  final MapController _mapController = MapController();
  
  // LOCATION STATE
  LatLng _carLocation = const LatLng(12.9716, 77.5946); // Default
  double _carBearing = 0.0;
  LatLng? _pickupLocation;
  LatLng? _dropLocation;
  List<LatLng> _routePoints = []; // The blue line path

  bool _isOnline = false;
  bool _isOnRide = false;
  String _rideStatus = "IDLE"; 
  Map<String, dynamic>? _currentRideData;
  String _walletBalance = "0";
  
  late IO.Socket socket; 

  @override
  void initState() {
    super.initState();
    _determinePosition();
    fetchWalletBalance();
    connectToSocket();
  }

  Future<void> fetchWalletBalance() async {
    final url = Uri.parse("${const String.fromEnvironment('SUPABASE_URL')}/rest/v1/users?phone=eq.${widget.driverPhone}&select=wallet_balance");
    try {
      final response = await http.get(
        url,
        headers: {
          "apikey": const String.fromEnvironment('SUPABASE_KEY'),
          "Authorization": "Bearer ${const String.fromEnvironment('SUPABASE_KEY')}"
        }
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data.isNotEmpty) {
          setState(() {
            _walletBalance = data[0]['wallet_balance']?.toString() ?? "0";
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
    if (!serviceEnabled) return;

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    
    if (permission == LocationPermission.deniedForever) return;

    Position position = await Geolocator.getCurrentPosition();
    setState(() {
      _carLocation = LatLng(position.latitude, position.longitude);
      _mapController.move(_carLocation, 16.0);
    });
  }

  void connectToSocket() {
    socket = IO.io('http://localhost:3000', <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
      'reconnection': true,
    });

    socket.onConnect((_) {
      if (_isOnline) socket.emit("driver_online", {"phone": widget.driverPhone});
    });

    socket.on("new_ride_request", (data) async {
      if (_isOnline && !_isOnRide) {
        if (await Vibration.hasVibrator() ?? false) {
           Vibration.vibrate(pattern: [0, 200, 100, 200]);
        }
        showRideDialog(data);
      }
    });

    socket.on("payment_successful", (data) {
      if (!mounted) return;
      fetchWalletBalance(); // Instantly update UI when rider pays
      _showPaymentDialog(data['fare'].toString());
    });
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

  // --- 1. SIMULATION LOGIC (THE MAGIC) ---
  void simulateMovement() {
    if (_pickupLocation == null || _dropLocation == null) return;
    if (_routePoints.isEmpty) return;

    int currentPointIndex = 0;

    // Move the car every 500 milliseconds along the route path
    Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (currentPointIndex >= _routePoints.length - 1 || _rideStatus == "COMPLETED") {
        timer.cancel();
        return;
      }

      currentPointIndex++;
      setState(() {
        LatLng oldLocation = _carLocation;
        _carLocation = _routePoints[currentPointIndex];
        _carBearing = _calculateBearing(oldLocation, _carLocation);
      });
      
      // Emit live location via Socket.io
      if (socket.connected) {
         socket.emit("driver_location", {
            "lat": _carLocation.latitude,
            "lng": _carLocation.longitude,
            "riderPhone": _currentRideData!['riderPhone']
         });
      }
      
      // Keep map centered on car
      _mapController.move(_carLocation, 16.0);
    });
  }

  // --- ACTIONS ---

  void toggleOnline() {
    setState(() => _isOnline = !_isOnline);
    if (_isOnline) {
      if (!socket.connected) socket.connect();
      socket.emit("driver_online", {"phone": widget.driverPhone});
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("You are ONLINE.")));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("You are OFFLINE.")));
    }
  }

  void updateRideStatus(String newStatus, String message) {
    setState(() => _rideStatus = newStatus);
    
    // Server Sync
    socket.emit("ride_status_update", {
      "riderId": _currentRideData!['riderId'],
      "status": newStatus,
      "message": message,
      "riderPhone": _currentRideData!['riderPhone'],
      "driverPhone": widget.driverPhone,
      "pickup": _currentRideData!['pickup'],
      "drop": _currentRideData!['drop'],
      "fare": _currentRideData!['fare']
    });

    // HANDLE STATUS CHANGES
    if (newStatus == "IN_PROGRESS") {
      simulateMovement(); // <--- START THE AUTO-PILOT
    } 
    else if (newStatus == "COMPLETED") {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ride Completed. Waiting for Payment...")));
    }
  }

  // --- ROUTING ---
  Future<void> getRoute(LatLng start, LatLng dest) async {
    final url = Uri.parse(
      "http://router.project-osrm.org/route/v1/driving/${start.longitude},${start.latitude};${dest.longitude},${dest.latitude}?geometries=geojson"
    );

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> coords = data['routes'][0]['geometry']['coordinates'];
        
        setState(() {
           _routePoints = coords.map((c) => LatLng(c[1], c[0])).toList();
        });
      }
    } catch (e) {
      // ignore
    }
  }

  void _showPaymentDialog(String fare) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: const Color(0xFF1E1E1E),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, color: Colors.greenAccent, size: 80),
              const SizedBox(height: 16),
              const Text("Payment Received", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text("₹$fare", style: const TextStyle(color: Colors.greenAccent, fontSize: 40, fontWeight: FontWeight.w900)),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.greenAccent,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    // Reset UI for next ride
                    setState(() {
                      _isOnRide = false;
                      _rideStatus = "IDLE";
                      _currentRideData = null;
                      _routePoints = []; 
                      _pickupLocation = null;
                      _dropLocation = null;
                    });
                  },
                  child: const Text("Done", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  // --- UI ---

  void showRideDialog(data) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: const Color(0xFF1E1E1E),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.notifications_active, color: Color(0xFF00FF7F), size: 48),
              const SizedBox(height: 16),
              const Text("New Ride Alert!", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Text("₹${data['fare']}", style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: Color(0xFF00FF7F))),
              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.my_location, color: Colors.grey, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(data['pickup'], style: const TextStyle(color: Colors.white))),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.flag, color: Colors.grey, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(data['drop'], style: const TextStyle(color: Colors.white))),
                ],
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: () => Navigator.pop(context), 
                      child: const Text("REJECT", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))
                    )
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: const Color(0xFF00FF7F),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        
                        // 1. EXTRACT REAL COORDINATES
                        // Use the data sent by Rider, or fallback to Bangalore if something breaks
                        double pLat = double.tryParse(data['pickupLat'].toString()) ?? 12.9716;
                        double pLng = double.tryParse(data['pickupLng'].toString()) ?? 77.5946;
                        
                        double dLat = double.tryParse(data['dropLat'].toString()) ?? 12.9800;
                        double dLng = double.tryParse(data['dropLng'].toString()) ?? 77.6000;

                        setState(() {
                          _isOnRide = true;
                          _rideStatus = "ACCEPTED";
                          _currentRideData = data;
                          
                          
                          // Set Precise Locations
                          _pickupLocation = LatLng(pLat, pLng);
                          _dropLocation = LatLng(dLat, dLng);
                          
                          // Teleport Car to Pickup
                          _carLocation = _pickupLocation!;
                          
                          // Move Camera to Pickup
                          _mapController.move(_carLocation, 16.0);
                        });
                        
                        // Get Actual Route
                        getRoute(_pickupLocation!, _dropLocation!);
                        
                        socket.emit("accept_ride", {
                          "riderId": data['riderId'], 
                          "riderPhone": data['riderPhone'],
                          "driverPhone": widget.driverPhone,
                          "driverName": widget.driverName,
                          "carNumber": "KA-01-EQ-9999",
                          "eta": "5 mins"
                        });
                      }, 
                      child: const Text("ACCEPT", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold))
                    )
                  )
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: _isOnRide ? null : AppBar(
        title: const Text("Waiting for Rides"),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Text(
                "₹$_walletBalance",
                style: const TextStyle(color: Color(0xFF00FF7F), fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.account_balance_wallet),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => EarningsScreen(driverPhone: widget.driverPhone)),
              );
            },
            tooltip: "Earnings",
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              if (!mounted) return;
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (ctx) => const LoginScreen()));
            },
            tooltip: "Logout",
          )
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController, // Added Controller
            options: MapOptions(initialCenter: _carLocation, initialZoom: 15.0),
            children: [
              TileLayer(
                urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png', 
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.driver.app'
              ),
              
              // ROUTE LINE (Glowing Green for Driver Theme)
              if (_isOnRide)
                PolylineLayer(
                  polylines: [
                    Polyline(points: _routePoints, strokeWidth: 5.0, color: const Color(0xFF00FF7F).withOpacity(0.8)),
                  ],
                ),

              MarkerLayer(markers: [
                // Dropoff Flag
                if (_dropLocation != null && _isOnRide)
                  Marker(
                    point: _dropLocation!, 
                    width: 50, height: 50, 
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10)]
                      ),
                      child: const Icon(Icons.location_on, color: Color(0xFF00FF7F), size: 40)
                    )
                  ),
                // Driver Car
                Marker(
                  point: _carLocation, 
                  width: 60, height: 60, 
                  child: Transform.rotate(
                    angle: _carBearing,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10)]
                      ),
                      child: const Icon(Icons.navigation, color: Colors.blueAccent, size: 40)
                    )
                  )
                ),
                // Show Pickup Flag
                if (_pickupLocation != null && _isOnRide && _rideStatus == "ACCEPTED")
                  Marker(
                    point: _pickupLocation!, 
                    width: 50, height: 50, 
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10)]
                      ),
                      child: const Icon(Icons.my_location, color: Colors.blueAccent, size: 40)
                    )
                  ),
              ]),
            ],
          ),

          // DYNAMIC STATUS PILL (Top Center)
          if (_isOnRide)
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
                          Text("On Duty: $_rideStatus", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                        ]
                      )
                    )
                  )
                )
              )
            ).animate().slideY(begin: -1.0, end: 0.0, curve: Curves.easeOutExpo, duration: 500.ms).fadeIn(),

          if (!_isOnRide)
            Positioned(
              bottom: 40, left: 30, right: 30,
              child: Container(
                height: 60,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: (_isOnline ? Colors.redAccent : const Color(0xFF00FF7F)).withOpacity(0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    )
                  ],
                ),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isOnline ? Colors.redAccent : const Color(0xFF00FF7F),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    elevation: 0,
                  ),
                  onPressed: toggleOnline,
                  child: Text(_isOnline ? "GO OFFLINE" : "GO ONLINE", style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          
          // TRIP CONTROL PANEL
          if (_isOnRide) 
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 20, spreadRadius: 5)]
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("CURRENT DESTINATION", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(_currentRideData?['drop'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold), maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 60,
                      width: double.infinity, 
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _rideStatus == "ACCEPTED" ? Colors.orange : (_rideStatus == "ARRIVED" ? const Color(0xFF00FF7F) : Colors.redAccent),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: () {
                          if (_rideStatus == "ACCEPTED") updateRideStatus("ARRIVED", "Driver Arrived");
                          else if (_rideStatus == "ARRIVED") updateRideStatus("IN_PROGRESS", "Ride Started");
                          else if (_rideStatus == "IN_PROGRESS") updateRideStatus("COMPLETED", "Ride Ended");
                        },
                        child: Text(
                          _rideStatus == "ACCEPTED" ? "I'VE ARRIVED" : (_rideStatus == "ARRIVED" ? "START TRIP (AUTO)" : "END TRIP"),
                          style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold)
                        ),
                      ),
                    ),

                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}