import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';

class RideHistoryScreen extends StatefulWidget {
  final String userPhone;

  const RideHistoryScreen({super.key, required this.userPhone});

  @override
  State<RideHistoryScreen> createState() => _RideHistoryScreenState();
}

class _RideHistoryScreenState extends State<RideHistoryScreen> {
  List<dynamic> _rides = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchRides();
  }

  Future<void> fetchRides() async {
    try {
      // final response = await http.get(Uri.parse("https://equinox-server-backend.onrender.com/api/rides/${widget.userPhone}"));
      final response = await http.get(Uri.parse("https://equinox-server-backend.onrender.com/api/rides/${widget.userPhone}"));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _rides = data['rides'] ?? [];
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to fetch rides")));
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0B),
      appBar: AppBar(
        title: Text("Ride History", style: GoogleFonts.cormorantGaramond(fontSize: 22, fontWeight: FontWeight.w400, color: const Color(0xFFE8E2D9))),
        backgroundColor: Colors.transparent,
        foregroundColor: const Color(0xFFE8E2D9),
        iconTheme: const IconThemeData(color: Color(0xFFC4BBA8)),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFC9A96E)))
          : _rides.isEmpty
              ? Center(child: Text("No rides found.", style: GoogleFonts.dmSans(color: const Color(0xFF6B6556))))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _rides.length,
                  itemBuilder: (context, index) {
                    final ride = _rides[index];
                    final date = DateTime.parse(ride['created_at']).toLocal();
                    final formattedDate = "${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}";
                    return Card(
                      elevation: 0,
                      color: const Color(0xFF161613),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Color(0xFF1E1C17), width: 1)),
                      margin: const EdgeInsets.only(bottom: 16),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(formattedDate, style: GoogleFonts.dmSans(fontWeight: FontWeight.w500, color: const Color(0xFF6B6556))),
                                Text("₹${ride['fare']}", style: GoogleFonts.dmSans(fontWeight: FontWeight.w500, fontSize: 18, color: const Color(0xFFC9A96E))),
                              ],
                            ),
                            const SizedBox(height: 16),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                return Flex(
                                  direction: Axis.horizontal,
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: List.generate((constraints.constrainWidth() / 10).floor(), (index) => SizedBox(width: 5, height: 1, child: DecoratedBox(decoration: BoxDecoration(color: const Color(0xFF1E1C17))))),
                                );
                              },
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                const Icon(Icons.my_location, color: Color(0xFFC9A96E), size: 18),
                                const SizedBox(width: 12),
                                Expanded(child: Text(ride['pickup'] ?? "Unknown", maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.dmSans(color: const Color(0xFFE8E2D9)))),
                              ],
                            ),
                            const SizedBox(height: 12),
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
                    );
                  },
                ),
    );
  }
}
