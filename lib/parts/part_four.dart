import 'package:flutter/material.dart';

class Part4 extends StatefulWidget {
  const Part4({super.key});

  @override
  _Part4State createState() => _Part4State();
}

class _Part4State extends State<Part4> {
  int _selectedIndex = -1;

  @override
  Widget build(BuildContext context) {
    bool isSmallScreen = MediaQuery.of(context).size.width < 650;

    return isSmallScreen
        ? Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 40),
            const Text(
              'RESOURCE REQUIREMENTS',
              style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildTopButton('Part IV.A', Icons.computer, 0),
                    const SizedBox(width: 16),
                    _buildTopButton('Part IV.B', Icons.business, 1),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    )
        : Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text(
          'RESOURCE REQUIREMENTS',
          style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 24),

        // Layout for larger screens
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildTopButton('Part IV.A', Icons.computer, 0),
            const SizedBox(width: 16),
            _buildTopButton('Part IV.B', Icons.business, 1),
          ],
        ),
      ],
    );
  }

  Widget _buildTopButton(String text, IconData icon, int index) {
    return ElevatedButton.icon(
      onPressed: () {
        setState(() {
          _selectedIndex = index;
        });
      },
      icon: Icon(icon, color: _selectedIndex == index ? Colors.white : Colors.black),
      label: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: _selectedIndex == index ? Colors.white : Colors.black,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: _selectedIndex == index ? const Color(0xff021e84) : Colors.transparent,
        foregroundColor: Colors.black,
        side: const BorderSide(color: Colors.black),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}
