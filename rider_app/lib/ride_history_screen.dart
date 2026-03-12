import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

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
      final response = await http.get(Uri.parse("http://localhost:3000/api/rides/${widget.userPhone}"));
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
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text("Ride History"),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _rides.isEmpty
              ? const Center(child: Text("No rides found."))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _rides.length,
                  itemBuilder: (context, index) {
                    final ride = _rides[index];
                    final date = DateTime.parse(ride['created_at']).toLocal();
                    final formattedDate = "${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}";
                    return Card(
                      elevation: 0,
                      color: const Color(0xFF1E1E1E),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                            LayoutBuilder(
                              builder: (context, constraints) {
                                return Flex(
                                  direction: Axis.horizontal,
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: List.generate((constraints.constrainWidth() / 10).floor(), (index) => SizedBox(width: 5, height: 1, child: DecoratedBox(decoration: BoxDecoration(color: Colors.grey.shade800)))),
                                );
                              },
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                const Icon(Icons.my_location, color: Color(0xFF00FF7F), size: 20),
                                const SizedBox(width: 12),
                                Expanded(child: Text(ride['pickup'] ?? "Unknown", maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white))),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                const Icon(Icons.flag, color: Colors.white, size: 20),
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
    );
  }
}
