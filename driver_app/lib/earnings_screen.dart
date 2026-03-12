import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class EarningsScreen extends StatefulWidget {
  final String driverPhone;

  const EarningsScreen({super.key, required this.driverPhone});

  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> {
  List<dynamic> _rides = [];
  bool _isLoading = true;
  double _totalEarnings = 0;

  @override
  void initState() {
    super.initState();
    fetchEarnings();
  }

  Future<void> fetchEarnings() async {
    try {
      final response = await http.get(Uri.parse("http://localhost:3000/api/rides/${widget.driverPhone}"));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final ridesList = data['rides'] ?? [];

        // Fetch precise wallet balance directly from Supabase
        final userUrl = Uri.parse("${const String.fromEnvironment('SUPABASE_URL')}/rest/v1/users?phone=eq.${widget.driverPhone}&select=wallet_balance");
        double newTotal = 0;
        try {
          final userResponse = await http.get(
            userUrl,
            headers: {
              "apikey": const String.fromEnvironment('SUPABASE_KEY'),
              "Authorization": "Bearer ${const String.fromEnvironment('SUPABASE_KEY')}"
            }
          );
          if (userResponse.statusCode == 200) {
            final userData = jsonDecode(userResponse.body);
            if (userData.isNotEmpty) {
              newTotal = double.tryParse(userData[0]['wallet_balance']?.toString() ?? "0") ?? 0;
            }
          }
        } catch (e) {
          print("Error fetching user data: $e");
        }

        setState(() {
          _rides = ridesList;
          _totalEarnings = newTotal;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to fetch earnings")));
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
        title: const Text("Earnings & History"),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  color: const Color(0xFF1E1E1E),
                  padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 32),
                  child: Column(
                    children: [
                      const Icon(Icons.account_balance_wallet, color: Color(0xFF00FF7F), size: 48),
                      const SizedBox(height: 16),
                      const Text("Total Earnings", style: TextStyle(color: Colors.grey, fontSize: 18, letterSpacing: 1.2)),
                      const SizedBox(height: 8),
                      Text("₹${_totalEarnings.toStringAsFixed(2)}", style: const TextStyle(color: Colors.white, fontSize: 56, fontWeight: FontWeight.w900)),
                    ],
                  ),
                ),
                Expanded(
                  child: _rides.isEmpty
                    ? const Center(child: Text("No completed rides yet.", style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _rides.length,
                        itemBuilder: (context, index) {
                          final ride = _rides[index];
                          final date = DateTime.parse(ride['created_at']).toLocal();
                          final formattedDate = "${date.day}/${date.month}/${date.year}";
                          return Card(
                            color: const Color(0xFF1E1E1E),
                            elevation: 0,
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                              leading: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(color: const Color(0xFF00FF7F).withOpacity(0.1), shape: BoxShape.circle),
                                child: const Icon(Icons.check, color: Color(0xFF00FF7F)),
                              ),
                              title: Text("To: ${ride['dropoff']?.split(',')[0] ?? 'Unknown'}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              subtitle: Text(formattedDate, style: const TextStyle(color: Colors.grey)),
                              trailing: Text("₹${ride['fare']}", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF00FF7F))),
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
