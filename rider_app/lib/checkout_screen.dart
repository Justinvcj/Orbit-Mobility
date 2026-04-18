import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';

class CheckoutScreen extends StatefulWidget {
  final String fare;
  final String riderPhone;
  final String driverPhone;
  final String rideId;

  const CheckoutScreen({
    super.key,
    required this.fare,
    required this.riderPhone,
    required this.driverPhone,
    required this.rideId,
  });

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  bool _isProcessing = false;

  Future<void> _processPayment() async {
    setState(() => _isProcessing = true);

    try {
      final response = await http.post(
        // Uri.parse("https://equinox-server-backend.onrender.com/api/pay"),
        Uri.parse("https://equinox-server-backend.onrender.com/api/pay"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "rider_phone": widget.riderPhone,
          "driver_phone": widget.driverPhone,
          "fare": widget.fare,
          "ride_id": widget.rideId,
        }),
      );

      if (response.statusCode == 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: const [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 10),
                Text("Payment Successful!", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            backgroundColor: Colors.green.shade800,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(20),
            duration: const Duration(seconds: 3),
          ),
        );
        Navigator.pop(context); // Go back to Home Screen
      } else {
        if (!mounted) return;
        final errorMsg = jsonDecode(response.body)['error'] ?? "Unknown error";
        _showError("Payment failed: $errorMsg");
      }
    } catch (e) {
      if (!mounted) return;
      _showError("Network error: $e");
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0B),
      appBar: AppBar(
        title: Text("Digital Receipt", style: GoogleFonts.cormorantGaramond(fontSize: 22, fontWeight: FontWeight.w400, color: const Color(0xFFE8E2D9))),
        backgroundColor: Colors.transparent,
        foregroundColor: const Color(0xFFE8E2D9),
        iconTheme: const IconThemeData(color: Color(0xFFC4BBA8)),
        elevation: 0,
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Center(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F0F0D),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF1E1C17), width: 1),
                    ),
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.receipt_long, color: Color(0xFFC9A96E), size: 60),
                        const SizedBox(height: 16),
                        Text(
                          "Total Fare",
                          style: GoogleFonts.dmSans(color: const Color(0xFF6B6556), fontSize: 18),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "₹${widget.fare}",
                          style: GoogleFonts.cormorantGaramond(
                            color: const Color(0xFFC9A96E),
                            fontSize: 48,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        const SizedBox(height: 32),
                        // Dashed line
                        LayoutBuilder(
                          builder: (context, constraints) {
                            return Flex(
                              direction: Axis.horizontal,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: List.generate(
                                (constraints.constrainWidth() / 10).floor(),
                                (index) => SizedBox(
                                  width: 5,
                                  height: 1,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(color: const Color(0xFF1E1C17)),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 32),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text("Ride ID", style: GoogleFonts.dmSans(color: const Color(0xFF6B6556), fontSize: 16)),
                            Text("#${widget.rideId.length > 5 ? widget.rideId.substring(widget.rideId.length - 5) : widget.rideId}", style: GoogleFonts.dmSans(color: const Color(0xFFE8E2D9), fontSize: 16, fontWeight: FontWeight.w500)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text("Driver", style: GoogleFonts.dmSans(color: const Color(0xFF6B6556), fontSize: 16)),
                            Text(widget.driverPhone, style: GoogleFonts.dmSans(color: const Color(0xFFE8E2D9), fontSize: 16, fontWeight: FontWeight.w500)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text("Payment", style: GoogleFonts.dmSans(color: const Color(0xFF6B6556), fontSize: 16)),
                            Text("Fair-Fare Wallet", style: GoogleFonts.dmSans(color: const Color(0xFFC9A96E), fontSize: 16, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 60,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFC9A96E),
                    foregroundColor: const Color(0xFF0A0A0B),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  onPressed: _isProcessing ? null : _processPayment,
                  child: _isProcessing
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(color: Color(0xFF0A0A0B), strokeWidth: 3),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.account_balance_wallet, size: 28),
                            const SizedBox(width: 12),
                            Text("Pay from Wallet", style: GoogleFonts.dmSans(fontSize: 18, fontWeight: FontWeight.w500)),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
