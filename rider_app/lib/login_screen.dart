import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'main.dart'; // Import to navigate to the map

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  bool _isLoading = false;

  Future<void> doLogin() async {
    String name = _nameController.text.trim();
    String phone = _phoneController.text.trim();

    if (name.isEmpty || phone.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter valid Name & Phone"))
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await http.post(
        // Uri.parse("https://equinox-server-backend.onrender.com/api/login"),
        Uri.parse("https://equinox-server-backend.onrender.com/api/login"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "name": name,
          "phone": phone,
          "role": "rider"
        })
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final decoded = jsonDecode(response.body);
        final userData = decoded['user'];
        final String returnedName = userData['name'] ?? name;
        final String returnedPhone = userData['phone'] ?? phone;

        // NEW: Save directly to SharedPreferences for persistent sessions
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_name', returnedName);
        await prefs.setString('user_phone', returnedPhone);

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => RiderHomeScreen(userName: returnedName, userPhone: returnedPhone),
          ),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Login failed. Please try again."))
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Network error: $e"))
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0B),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.local_taxi, size: 80, color: Color(0xFFC9A96E)),
                  const SizedBox(height: 24),
                  Text("Orbit Mobility", style: GoogleFonts.cormorantGaramond(fontSize: 40, fontWeight: FontWeight.w400, color: const Color(0xFFE8E2D9))),
                  const SizedBox(height: 8),
                  Text("Rider Login", style: GoogleFonts.dmSans(color: const Color(0xFF6B6556), fontSize: 18)),
                  const SizedBox(height: 48),
                  
                  // Name Field
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F0F0D),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF1E1C17), width: 1),
                    ),
                    child: TextField(
                      controller: _nameController,
                      style: GoogleFonts.dmSans(color: const Color(0xFFE8E2D9)),
                      decoration: InputDecoration(
                        hintText: "Your Name",
                        hintStyle: GoogleFonts.dmSans(color: const Color(0xFF6B6556)),
                        prefixIcon: const Icon(Icons.person, color: Color(0xFFC9A96E)),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Phone Field
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F0F0D),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF1E1C17), width: 1),
                    ),
                    child: TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      style: GoogleFonts.dmSans(color: const Color(0xFFE8E2D9)),
                      decoration: InputDecoration(
                        hintText: "Phone Number",
                        hintStyle: GoogleFonts.dmSans(color: const Color(0xFF6B6556)),
                        prefixIcon: const Icon(Icons.phone, color: Color(0xFFC9A96E)),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),

                  // Login Button
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
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      onPressed: _isLoading ? null : doLogin,
                      child: _isLoading 
                          ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Color(0xFF0A0A0B), strokeWidth: 3))
                          : Text("CONTINUE", style: GoogleFonts.dmSans(fontSize: 16, fontWeight: FontWeight.w500, letterSpacing: 0.08)),
                    ),
                  )
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
