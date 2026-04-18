import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';

class EarningsScreen extends StatefulWidget {
  final String driverPhone;

  const EarningsScreen({super.key, required this.driverPhone});

  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> {
  List<dynamic> _rides = [];
  bool _isLoading = true;
  double get totalEarnings {
    double total = 0;
    for (var ride in _rides) {
      if (ride['status'] == 'COMPLETED' || ride['status'] == 'PAID') {
        total += double.tryParse(ride['fare']?.toString() ?? '0') ?? 0;
      }
    }
    return total;
  }

  @override
  void initState() {
    super.initState();
    fetchEarnings();
  }

  Future<void> fetchEarnings() async {
    try {
      final response = await http.get(Uri.parse("https://equinox-server-backend.onrender.com/api/rides/${widget.driverPhone}"));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final ridesList = data['rides'] ?? [];

        setState(() {
          _rides = ridesList;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to fetch earnings", style: GoogleFonts.dmSans(color: const Color(0xFFE8E2D9))), backgroundColor: const Color(0xFF7C3A3A).withOpacity(0.8), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), margin: const EdgeInsets.all(16)));
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e", style: GoogleFonts.dmSans(color: const Color(0xFFE8E2D9))), backgroundColor: const Color(0xFF7C3A3A).withOpacity(0.8), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), margin: const EdgeInsets.all(16)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0B),
      appBar: AppBar(
        title: const Text("Earnings & History"),
        backgroundColor: Colors.transparent,
        foregroundColor: const Color(0xFFE8E2D9),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFC9A96E)))
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  color: const Color(0xFF0F0F0D),
                  padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 32),
                  child: Column(
                    children: [
                      const Icon(Icons.account_balance_wallet, color: Color(0xFFC9A96E), size: 40),
                      const SizedBox(height: 16),
                      Text("Total Earnings", style: GoogleFonts.dmSans(color: const Color(0xFF6B6556), fontSize: 14, letterSpacing: 0.08)),
                      Text("₹${totalEarnings.toStringAsFixed(2)}", style: GoogleFonts.cormorantGaramond(color: const Color(0xFFE8E2D9), fontSize: 52, fontWeight: FontWeight.w300)),
                    ],
                  ),
                ),
                Expanded(
                  child: _rides.isEmpty
                    ? Center(child: Text("No completed rides yet.", style: GoogleFonts.dmSans(color: const Color(0xFF6B6556))))
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _rides.length,
                        itemBuilder: (context, index) {
                          final ride = _rides[index];
                          final date = DateTime.parse(ride['created_at']).toLocal();
                          final formattedDate = "${date.day}/${date.month}/${date.year}";
                          return Card(
                            color: const Color(0xFF161613),
                            elevation: 0,
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: const BorderSide(color: Color(0xFF1E1C17), width: 1),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                              leading: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: const BoxDecoration(
                                  color: Color(0x22C9A96E), 
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.check, color: Color(0xFFC9A96E)),
                              ),
                              title: Text(
                                "To: ${ride['dropoff']?.split(',')[0] ?? 'Unknown'}", 
                                style: GoogleFonts.dmSans(color: const Color(0xFFE8E2D9), fontWeight: FontWeight.w500),
                              ),
                              subtitle: Text(
                                formattedDate, 
                                style: GoogleFonts.dmSans(color: const Color(0xFF6B6556), fontSize: 12),
                              ),
                              trailing: Text(
                                "₹${ride['fare']}", 
                                style: GoogleFonts.dmSans(fontWeight: FontWeight.w500, fontSize: 18, color: const Color(0xFFC9A96E)),
                              ),
                            ),
                          );
                        },
                      ),
                )
              ],
            ),
    );
  }
}
