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
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_fonts/google_fonts.dart';
import 'earnings_screen.dart';
import 'login_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:qr_flutter/qr_flutter.dart';

class MapScreen extends StatefulWidget {
  final String driverName;
  final String driverPhone;

  const MapScreen({
    super.key,
    required this.driverName,
    required this.driverPhone,
  });
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with WidgetsBindingObserver {
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
  bool _isCompletingTrip = false;
  String _rideStatus = "IDLE";
  Map<String, dynamic>? _currentRideData;
  String? _otp;
  String _walletBalance = "0";

  late IO.Socket socket;
  List<Map<String, String>> _chatMessages = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _determinePosition();
    fetchWalletBalance();
    connectToSocket();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    socket.dispose();
    super.dispose();
  }

  Future<void> _makeCall(String phone) async {
    final Uri launchUri = Uri(scheme: 'tel', path: phone);
    if (!await launchUrl(launchUri)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not launch dialer.")),
        );
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!socket.connected) socket.connect();
      if (_isOnline && !_isOnRide) {
        socket.emit('driver_online', {'phone': widget.driverPhone});
      }
      _fetchActiveRide();
      fetchWalletBalance();
    }
  }

  Future<void> _fetchActiveRide() async {
    try {
      final response = await http.get(
        Uri.parse(
          // 'https://equinox-server-backend.onrender.com/api/active-ride/${widget.driverPhone}',
          'https://equinox-server-backend.onrender.com/api/active-ride/${widget.driverPhone}',
        ),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final ride = data['activeRide'];
        if (ride != null && mounted) {
          final status = ride['status']?.toUpperCase() ?? 'IDLE';
          
          // STRICT FILTERING: Discard Ghost Rides or Malformed Payloads
          if (['COMPLETED', 'CANCELLED', 'FAILED', 'PAID'].contains(status) || 
              ride['pickup'] == null || ride['rider_phone'] == null) {
              setState(() {
                _isOnRide = false;
                _isOnline = false; // Absolute default resting state
                _rideStatus = "IDLE";
                _currentRideData = null;
                _routePoints = [];
                _pickupLocation = null;
                _dropLocation = null;
              });
              return;
          }

          if (['ACCEPTED', 'ARRIVED', 'IN_PROGRESS'].contains(status)) {
            setState(() {
              _isOnRide = true;
              _isOnline = true;
              _rideStatus = status;
              _currentRideData = {
                'riderPhone': ride['rider_phone'],
                'pickup': ride['pickup'],
                'drop': ride['dropoff'],
                'fare': ride['fare']?.toString() ?? '0',
                'rideId': ride['id'],
              };
              _otp = ride['otp'];
            });
          }
        }
      }
    } catch (e) {
      // Silently fail
    }
  }

  Future<void> fetchWalletBalance() async {
    try {
      final response = await http.get(Uri.parse("https://equinox-server-backend.onrender.com/api/rides/${widget.driverPhone}"));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final ridesList = data['rides'] ?? [];

        double total = 0;
        for (var ride in ridesList) {
          if (ride['status'] == 'COMPLETED' || ride['status'] == 'PAID') {
            total += double.tryParse(ride['fare']?.toString() ?? '0') ?? 0;
          }
        }

        if (mounted) {
          setState(() {
            _walletBalance = total.toStringAsFixed(0);
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
    socket = IO.io(
      // 'https://equinox-server-backend.onrender.com',
      'https://equinox-server-backend.onrender.com',
      <String, dynamic>{
        'transports': ['websocket'],
        'autoConnect': true,
        'reconnection': true,
      },
    );

    socket.onConnect((_) {
      if (_isOnline) {
        socket.emit("driver_online", {"phone": widget.driverPhone});
      }
    });

    socket.on("new_ride_request", (data) async {
      if (_isOnline && !_isOnRide) {
        if (!kIsWeb && await Vibration.hasVibrator() == true) {
          try { Vibration.vibrate(pattern: [0, 200, 100, 200]); } catch (_) {}
        }
        showRideDialog(data);
      }
    });

    socket.on("payment_successful", (data) {
      if (!mounted) return;
      fetchWalletBalance(); // Instantly update UI when rider pays
      
      // PHASE 5.2: Strictly reset state to avoid "I've Arrived" cyclic bug
      setState(() {
        _isOnRide = false;
        _isCompletingTrip = false;
        _rideStatus = "IDLE";
        _currentRideData = null;
        _routePoints = [];
        _pickupLocation = null;
        _dropLocation = null;
      });
      
      _showPaymentDialog(data['fare'].toString());
    });

    // Phase 16.0: Chat
    socket.on("receive_message", (data) {
      if (mounted) {
        setState(() {
          _chatMessages.add({"sender": data['sender'], "text": data['text']});
        });
        if (!kIsWeb) {
          try { Vibration.vibrate(duration: 50); } catch (_) {}
        }
      }
    });

    // Phase 16.0: QR Pair
    socket.on("qr_paired", (data) {
      if (mounted) {
        setState(() {
          _isOnRide = true;
          _rideStatus = "ACCEPTED";
          _currentRideData = {
             'riderPhone': data['riderPhone'],
             'pickup': 'Street Hail',
             'drop': 'TBD',
             'fare': '0',
             'rideId': data['rideId'],
             'roomId': data['roomId']
          };
        });
        Navigator.popUntil(context, (route) => route.isFirst); // clear popups if any
      }
    });

    // Phase 17.0: Dynamic Route
    socket.on("route_recalculated", (data) {
      if (mounted) {
        setState(() {
          if (_currentRideData != null) {
            _currentRideData!['fare'] = data['newFare']?.toString() ?? _currentRideData!['fare'];
          }
          if (data['polyline'] != null) {
            List<dynamic> coords = data['polyline'];
            _routePoints = coords.map((c) => LatLng(c[1], c[0])).toList();
          }
        });
        if (!kIsWeb) { try { Vibration.vibrate(pattern: [0, 500, 200, 500]); } catch (_) {} }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Route Updated: New Fare ₹${data['newFare']}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontSize: 16)),
            backgroundColor: const Color(0xFFC9A96E),
            duration: const Duration(seconds: 8),
          )
        );
      }
    });

  }

  double _calculateBearing(LatLng start, LatLng end) {
    double lat1 = start.latitude * math.pi / 180;
    double lng1 = start.longitude * math.pi / 180;
    double lat2 = end.latitude * math.pi / 180;
    double lng2 = end.longitude * math.pi / 180;

    double dLon = lng2 - lng1;
    double y = math.sin(dLon) * math.cos(lat2);
    double x =
        math.cos(lat1) * math.sin(lat2) -
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
      if (currentPointIndex >= _routePoints.length - 1 ||
          _rideStatus == "COMPLETED") {
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
        socket.emit("driver_location_update", {
          "lat": _carLocation.latitude,
          "lng": _carLocation.longitude,
          "riderPhone": _currentRideData!['riderPhone'],
          "ride_id": _currentRideData!['rideId'],
        });
      }

      // Keep map centered on car
      _mapController.move(_carLocation, 16.0);
    });
  }

  // --- ACTIONS ---

  Future<void> toggleOnline() async {
    if (!_isOnline) {
      // Trying to go online
      try {
        final response = await http.get(Uri.parse('https://equinox-server-backend.onrender.com/api/driver/subscription/${widget.driverPhone}'));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final expiryStr = data['expiry'];
          if (expiryStr == null) {
            _showSubscriptionDialog();
            return;
          }
          final expiryDate = DateTime.parse(expiryStr);
          if (DateTime.now().isAfter(expiryDate)) {
            _showSubscriptionDialog();
            return;
          }
        }
      } catch (e) {
        // Network error, silently fail but allow login or enforce? Enforce for business pivot.
        debugPrint("Subscription Check Error: $e");
      }
    }

    setState(() => _isOnline = !_isOnline);
    if (_isOnline) {
      if (!socket.connected) socket.connect();
      socket.emit("driver_online", {"phone": widget.driverPhone});
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("You are ONLINE.")));
    } else {
      socket.emit("detach_rooms", {"phone": widget.driverPhone});
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("You are OFFLINE.")));
    }
  }

  void _showSubscriptionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        bool _isProcessing = false;
        String _statusText = "Zero Commission. Infinite Rides. ₹10 for 24 Hours.";
        bool _isSuccess = false;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF0F0F0D),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero, side: const BorderSide(color: Color(0xFF1E1C17), width: 1.5)),
              title: Text(_isSuccess ? "Subscription Activated" : "Subscription Expired", style: GoogleFonts.cormorantGaramond(color: const Color(0xFFE8E2D9), fontSize: 24)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                   if (!_isProcessing && !_isSuccess)
                      Text(_statusText, style: GoogleFonts.dmSans(color: const Color(0xFF6B6556))),
                   if (_isProcessing) ...[
                      const CircularProgressIndicator(color: Color(0xFFC9A96E)),
                      const SizedBox(height: 16),
                      Text(_statusText, style: GoogleFonts.dmSans(color: const Color(0xFFE8E2D9))),
                   ],
                   if (_isSuccess) ...[
                      const Icon(Icons.check_circle, color: Colors.green, size: 48),
                      const SizedBox(height: 16),
                      Text("You are now online.", style: GoogleFonts.dmSans(color: const Color(0xFFE8E2D9))),
                   ]
                ],
              ),
              actions: [
                if (!_isProcessing && !_isSuccess)
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text("CANCEL", style: GoogleFonts.dmSans(color: const Color(0xFF6B6556))),
                  ),
                if (!_isProcessing && !_isSuccess)
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFC9A96E), foregroundColor: const Color(0xFF0A0A0B), elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero)),
                    onPressed: () async {
                      setDialogState(() {
                        _isProcessing = true;
                        _statusText = "Initializing Secure Gateway...";
                      });
                      
                      await Future.delayed(const Duration(milliseconds: 1500));
                      
                      setDialogState(() {
                        _statusText = "Processing UPI Payment...";
                      });
                      
                      await Future.delayed(const Duration(seconds: 2));
                      
                      try {
                        final expiry = DateTime.now().add(const Duration(hours: 24));
                        final response = await http.post(
                          Uri.parse('https://equinox-server-backend.onrender.com/api/driver/pay-subscription'),
                          headers: {'Content-Type': 'application/json'},
                          body: jsonEncode({
                            'phone': widget.driverPhone,
                            'expiry_date': expiry.toIso8601String()
                          })
                        );
                        
                        if (response.statusCode == 200) {
                          setDialogState(() {
                            _isProcessing = false;
                            _isSuccess = true;
                          });
                          
                          await Future.delayed(const Duration(seconds: 1));
                          if (mounted) {
                            Navigator.pop(context); // Dismiss dialog
                            // State Unblock
                            setState(() => _isOnline = true);
                            if (!socket.connected) socket.connect();
                            socket.emit("driver_online", {"phone": widget.driverPhone});
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("You are ONLINE.")));
                          }
                        } else {
                           setDialogState(() {
                              _isProcessing = false;
                              _statusText = "Payment network failed.";
                           });
                        }
                      } catch (e) {
                         setDialogState(() {
                            _isProcessing = false;
                            _statusText = "Payment connection failed. Try again.";
                         });
                      }
                    },
                    child: Text("PAY VIA UPI", style: GoogleFonts.dmSans(fontWeight: FontWeight.w700)),
                  )
              ]
            );
          }
        );
      }
    );
  }

  void updateRideStatus(String newStatus, String message) {
    setState(() => _rideStatus = newStatus);

    final payload = {
      "riderId": _currentRideData!['riderId'],
      "rideId": _currentRideData!['rideId'],
      "status": newStatus,
      "message": message,
      "riderPhone": _currentRideData!['riderPhone'],
      "driverPhone": widget.driverPhone,
      "pickup": _currentRideData!['pickup'],
      "drop": _currentRideData!['drop'],
      "fare": _currentRideData!['fare'],
    };

    if (newStatus == "COMPLETED") {
      // Fire the completion event — the server handles wallet transfer
      // and emits 'payment_successful' back, which triggers _showPaymentDialog
      socket.emit("ride_status_update", payload);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Ride Completed. Processing payment...")),
      );
    } else {
      // Fire-and-forget for non-COMPLETED statuses
      socket.emit("ride_status_update", payload);
    }

    // HANDLE STATUS CHANGES
    if (newStatus == "IN_PROGRESS") {
      simulateMovement();
    }
  }

  // --- ROUTING ---
  Future<void> getRoute(LatLng start, LatLng dest) async {
    final url = Uri.parse(
      "http://router.project-osrm.org/route/v1/driving/${start.longitude},${start.latitude};${dest.longitude},${dest.latitude}?geometries=geojson",
    );

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> coords =
            data['routes'][0]['geometry']['coordinates'];

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
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          padding: const EdgeInsets.all(24.0),
          decoration: BoxDecoration(
            color: const Color(0xFF0F0F0D),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF1E1C17), width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.check_circle,
                color: Color(0xFF4A7C59),
                size: 80,
              ),
              const SizedBox(height: 16),
              Text(
                "Payment Received",
                style: GoogleFonts.cormorantGaramond(
                  color: const Color(0xFFE8E2D9),
                  fontSize: 24,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "₹$fare",
                style: GoogleFonts.cormorantGaramond(
                  color: const Color(0xFFC9A96E),
                  fontSize: 40,
                  fontWeight: FontWeight.w300,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFC9A96E),
                    foregroundColor: const Color(0xFF0A0A0B),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    // Reset UI for next ride
                    setState(() {
                      _isOnRide = false;
                      _isCompletingTrip = false;
                      _rideStatus = "IDLE";
                      _currentRideData = null;
                      _routePoints = [];
                      _pickupLocation = null;
                      _dropLocation = null;
                      _chatMessages.clear();
                    });
                  },
                  child: Text(
                    "DONE",
                    style: GoogleFonts.dmSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.08,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showQrPopup() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16.0, sigmaY: 16.0),
            child: Container(
              padding: const EdgeInsets.all(24.0),
              decoration: BoxDecoration(
                color: const Color(0xFF0F0F0D).withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF1E1C17), width: 1),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("RIDER PAIRING", style: GoogleFonts.dmSans(color: const Color(0xFF6B6556), fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                  const SizedBox(height: 8),
                  Text("Let Rider Scan QR", style: GoogleFonts.cormorantGaramond(color: const Color(0xFFE8E2D9), fontSize: 24)),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                    child: QrImageView(
                      data: widget.driverPhone,
                      version: QrVersions.auto,
                      size: 200.0,
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text("CLOSE", style: GoogleFonts.dmSans(color: const Color(0xFFC9A96E))),
                  )
                ]
              )
            )
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
                         bool isMe = msg['sender'] == 'Driver';
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
                               final targetRoom = _currentRideData!['roomId'] ?? 'rider_${_currentRideData!['riderPhone']}';
                               socket.emit("send_message", {
                                 "room_id": targetRoom,
                                 "sender": "Driver",
                                 "text": msgController.text.trim()
                               });
                               setState(() {
                                 _chatMessages.add({"sender": "Driver", "text": msgController.text.trim()});
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

  // --- UI ---

  void showRideDialog(dynamic data) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          padding: const EdgeInsets.all(24.0),
          decoration: BoxDecoration(
            color: const Color(0xFF0F0F0D),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF1E1C17), width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.notifications_active,
                color: Color(0xFFC9A96E),
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                "New Request: ${data['vehicle_type'] == 'bike' ? 'Bike' : 'Cab'}",
                style: GoogleFonts.cormorantGaramond(
                  color: const Color(0xFFE8E2D9),
                  fontSize: 24,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                "₹${data['fare']}",
                style: GoogleFonts.cormorantGaramond(
                  color: const Color(0xFFC9A96E),
                  fontSize: 40,
                  fontWeight: FontWeight.w300,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.my_location,
                    color: Color(0xFF6B6556),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      data['pickup'],
                      style: GoogleFonts.dmSans(color: const Color(0xFFE8E2D9)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.flag, color: Color(0xFF6B6556), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      data['drop'],
                      style: GoogleFonts.dmSans(color: const Color(0xFFE8E2D9)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        foregroundColor: const Color(0xFFC4BBA8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        "REJECT",
                        style: GoogleFonts.dmSans(color: const Color(0xFF6B6556)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: const Color(0xFFC9A96E),
                        foregroundColor: const Color(0xFF0A0A0B),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () {
                        if (!kIsWeb) { try { Vibration.vibrate(duration: 50); } catch (_) {} }
                        Navigator.pop(context);

                        // 1. EXTRACT REAL COORDINATES
                        double pLat =
                            double.tryParse(data['pickupLat'].toString()) ??
                            12.9716;
                        double pLng =
                            double.tryParse(data['pickupLng'].toString()) ??
                            77.5946;

                        double dLat =
                            double.tryParse(data['dropLat'].toString()) ??
                            12.9800;
                        double dLng =
                            double.tryParse(data['dropLng'].toString()) ??
                            77.6000;

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

                        socket.emitWithAck(
                          "accept_ride",
                          {
                            "riderId": data['riderId'],
                            "riderPhone": data['riderPhone'],
                            "driverPhone": widget.driverPhone,
                            "driverName": widget.driverName,
                            "pickup": data['pickup'],
                            "drop": data['drop'],
                            "fare": data['fare'],
                            "carNumber": "ORBIT-01",
                            "eta": "5 mins",
                          },
                          ack: (response) {
                            if (response != null &&
                                response['success'] == true) {
                              if (mounted) {
                                setState(() {
                                  _currentRideData!['rideId'] =
                                      response['rideId'];
                                  _otp = response['otp'].toString();
                                });
                              }
                            }
                          },
                        );
                      },
                      child: Text(
                        "ACCEPT",
                        style: GoogleFonts.dmSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.08,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showOtpDialog() {
    final TextEditingController otpController = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          padding: const EdgeInsets.all(24.0),
          decoration: BoxDecoration(
            color: const Color(0xFF0F0F0D),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF1E1C17), width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Verify Trip OTP",
                style: GoogleFonts.cormorantGaramond(
                  color: const Color(0xFFE8E2D9),
                  fontWeight: FontWeight.w400,
                  fontSize: 24,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: otpController,
                keyboardType: TextInputType.number,
                maxLength: 4,
                style: GoogleFonts.dmSans(
                  color: const Color(0xFFE8E2D9),
                  fontSize: 32,
                  letterSpacing: 10,
                ),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  counterText: "",
                  hintText: "0000",
                  hintStyle: GoogleFonts.dmSans(color: const Color(0xFF6B6556)),
                  enabledBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0x44C9A96E)),
                  ),
                  focusedBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(
                      color: Color(0xFFC9A96E),
                      width: 2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      "CANCEL",
                      style: GoogleFonts.dmSans(color: const Color(0xFF6B6556)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFC9A96E),
                      foregroundColor: const Color(0xFF0A0A0B),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () {
                      if (otpController.text == _otp) {
                        if (!kIsWeb) { try { Vibration.vibrate(duration: 50); } catch (_) {} }
                        Navigator.pop(context);
                        updateRideStatus("IN_PROGRESS", "Ride Started");
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text("Invalid OTP! Try again.",
                                style: GoogleFonts.dmSans(
                                    color: const Color(0xFFE8E2D9))),
                            backgroundColor:
                                const Color(0xFF7C3A3A).withValues(alpha: 0.8),
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            margin: const EdgeInsets.all(16),
                          ),
                        );
                      }
                    },
                    child: Text(
                      "VERIFY",
                      style: GoogleFonts.dmSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.08,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0B),
      appBar: _isOnRide
          ? null
          : AppBar(
              title: Text("Equinox",
                  style: GoogleFonts.cormorantGaramond(
                      fontSize: 22, color: const Color(0xFFE8E2D9))),
              backgroundColor: Colors.transparent,
              foregroundColor: const Color(0xFFE8E2D9),
              elevation: 0,
              actions: [
                TextButton.icon(
                  onPressed: () async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.clear();
                    if (mounted) {
                      setState(() {
                         _isOnRide = false;
                         _isOnline = false;
                         _rideStatus = "IDLE";
                         _currentRideData = null;
                         _routePoints = [];
                         _pickupLocation = null;
                         _dropLocation = null;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("State Wiped. Restarting flow.", style: TextStyle(color: Colors.white)), backgroundColor: Colors.red)
                      );
                    }
                  },
                  icon: const Icon(Icons.warning, color: Colors.redAccent, size: 14),
                  label: const Text("DEBUG RESET", style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: Text(
                      "₹$_walletBalance",
                      style: GoogleFonts.dmSans(
                        color: const Color(0xFFC9A96E),
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.qr_code_scanner, color: Color(0xFFC9A96E)),
                  onPressed: _showQrPopup,
                  tooltip: "Show QR",
                ),
                IconButton(
                  icon: const Icon(Icons.account_balance_wallet),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            EarningsScreen(driverPhone: widget.driverPhone),
                      ),
                    );
                  },
                  tooltip: "Earnings",
                ),
                IconButton(
                  icon: const Icon(Icons.logout, color: Color(0xFF6B6556)),
                  onPressed: () async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.clear();
                    if (!context.mounted) return;
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (ctx) => const LoginScreen()),
                    );
                  },
                  tooltip: "Logout",
                ),
              ],
            ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _carLocation, 
              initialZoom: 15.0,
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.orbit.driver',
              ),
              if (_isOnRide && _routePoints.isNotEmpty && _routePoints.length > 1)
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
                  if (_dropLocation != null && _isOnRide)
                    Marker(
                      point: _dropLocation!,
                      width: 50,
                      height: 50,
                      child: const Icon(Icons.location_on,
                          color: Color(0xFFC4BBA8), size: 40),
                    ),
                  Marker(
                    point: _carLocation,
                    width: 60,
                    height: 60,
                    child: Transform.rotate(
                      angle: _carBearing + (math.pi / 2),
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1915),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: const Color(0x44C9A96E), width: 1.5),
                        ),
                        child: Image.asset(
                          'assets/icons/${(_currentRideData != null && _currentRideData!['vehicle_type'] != null) ? _currentRideData!['vehicle_type'].toString().toLowerCase().replaceAll('equinox-', '').replaceAll('fair-', '') : 'cab'}.png',
                          width: 48,
                          height: 48,
                          errorBuilder: (context, error, stackTrace) => const Icon(Icons.local_taxi, size: 48),
                        ),
                      ),
                    ),
                  ),
                  if (_pickupLocation != null &&
                      _isOnRide &&
                      _rideStatus == "ACCEPTED")
                    Marker(
                      point: _pickupLocation!,
                      width: 50,
                      height: 50,
                      child: const Icon(Icons.my_location,
                          color: Color(0xFFC9A96E), size: 40),
                    ),
                ],
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
                _mapController.move(_carLocation, 16.0);
              },
              child: const Icon(Icons.my_location, color: Color(0xFF0F0F0D)),
            )
          ),

          if (_isOnRide)
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              left: 20,
              right: 20,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F0F0D),
                    borderRadius: BorderRadius.circular(30),
                    border:
                        Border.all(color: const Color(0xFF1E1C17), width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                  color: Color(0xFFC9A96E),
                                  shape: BoxShape.circle))
                          .animate(onPlay: (c) => c.repeat())
                          .fade(duration: 800.ms),
                      const SizedBox(width: 12),
                      Text("ON DUTY: $_rideStatus",
                          style: GoogleFonts.dmSans(
                              color: const Color(0xFFE8E2D9),
                              fontWeight: FontWeight.w500,
                              fontSize: 13,
                              letterSpacing: 0.1)),
                    ],
                  ),
                ),
              ),
            )
                .animate()
                .slideY(
                  begin: -1.0,
                  end: 0.0,
                  curve: Curves.easeOutExpo,
                  duration: 500.ms,
                )
                .fadeIn(),
          if (!_isOnRide)
            Positioned(
              bottom: 40,
              left: 30,
              right: 30,
              child: SafeArea( // ADDED SafeArea HERE TO PREVENT OVERFLOW
                bottom: true,
                child: SizedBox(
                  height: 60,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          _isOnline ? const Color(0xFF331E1E) : const Color(0xFFC9A96E),
                      foregroundColor:
                          _isOnline ? const Color(0xFFE8E2D9) : const Color(0xFF0A0A0B),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                      side: _isOnline
                          ? const BorderSide(color: Color(0xFF7C3A3A), width: 1)
                          : BorderSide.none,
                    ),
                    onPressed: toggleOnline,
                    child: Text(_isOnline ? "GO OFFLINE" : "GO ONLINE",
                        style: GoogleFonts.dmSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.08)),
                  ),
                ),
              ),
            ),
          if (_isOnRide)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SafeArea( // ADDED SafeArea HERE TO FIX THE BOTTOM OVERFLOW BY 3 PIXELS
                top: false,
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: const BoxDecoration(
                    color: Color(0xFF0F0F0D),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                    border:
                        Border(top: BorderSide(color: Color(0xFF1E1C17), width: 1)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("PICKUP / DESTINATION",
                                  style: GoogleFonts.dmSans(
                                      color: const Color(0xFF6B6556),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: 0.1)),
                              Text(_currentRideData?['drop'] ?? 'Trip in Progress',
                                  style: GoogleFonts.cormorantGaramond(
                                      color: const Color(0xFFE8E2D9),
                                      fontSize: 20)),
                            ],
                          ),
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.chat_bubble_outline, color: Color(0xFFC9A96E)),
                                onPressed: _showChatSheet,
                              ),
                              IconButton(
                                  icon: const Icon(Icons.phone, color: Color(0xFFC9A96E)),
                                  onPressed: () => _makeCall(
                                      _currentRideData?['riderPhone'] ?? '')),
                            ]
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        height: 56,
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _rideStatus == "ACCEPTED"
                                ? const Color(0xFFC9A96E)
                                : const Color(0xFF1A1915),
                            foregroundColor: _rideStatus == "ACCEPTED"
                                ? const Color(0xFF0A0A0B)
                                : const Color(0xFFC9A96E),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: _rideStatus != "ACCEPTED"
                                    ? const BorderSide(
                                        color: Color(0xFF1E1C17), width: 1)
                                    : BorderSide.none),
                          ),
                          onPressed: _isCompletingTrip
                              ? null
                              : () {
                                  if (_rideStatus == "ACCEPTED") {
                                    updateRideStatus("ARRIVED", "Driver Arrived");
                                  } else if (_rideStatus == "ARRIVED") {
                                    _showOtpDialog();
                                  } else if (_rideStatus == "IN_PROGRESS") {
                                    setState(() {
                                      _isCompletingTrip = true;
                                    });
                                    socket.emit("request_payment", {
                                      "rideId": _currentRideData!['rideId'],
                                      "fare": _currentRideData!['fare'],
                                      "riderId": _currentRideData!['riderId'],
                                      "riderPhone": _currentRideData!['riderPhone'],
                                      "driverPhone": widget.driverPhone
                                    });
                                  }
                                },
                          child: _isCompletingTrip
                              ? const CircularProgressIndicator(
                                  color: Color(0xFFC9A96E))
                              : Text(
                                  _rideStatus == "ACCEPTED"
                                      ? "I'VE ARRIVED"
                                      : (_rideStatus == "ARRIVED"
                                          ? "START TRIP"
                                          : "END TRIP"),
                                  style: GoogleFonts.dmSans(
                                      fontWeight: FontWeight.w500)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
