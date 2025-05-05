import 'package:flutter/material.dart';
import 'package:test_project/parts/part_i/part_ia.dart';

import '../landing.dart'; // Import your DocumentPage

class Part1 extends StatefulWidget {
  const Part1({super.key});

  @override
  _Part1State createState() => _Part1State();
}

class _Part1State extends State<Part1> {
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
              'ORGANIZATIONAL PROFILE',
              style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildTopButton('Part I.A', Icons.description, 0, context),
                    const SizedBox(width: 16),
                    _buildTopButton('Part I.B', Icons.people, 1, context),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildTopButton('Part I.C', Icons.public, 2, context),
                    const SizedBox(width: 16),
                    _buildTopButton('Part I.D', Icons.warning, 3, context),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildTopButton('Part I.E', Icons.computer, 4, context),
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
          'ORGANIZATIONAL PROFILE',
          style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildTopButton('Part I.A', Icons.description, 0, context),
            const SizedBox(width: 16),
            _buildTopButton('Part I.B', Icons.people, 1, context),
            const SizedBox(width: 16),
            _buildTopButton('Part I.C', Icons.public, 2, context),
            const SizedBox(width: 16),
            _buildTopButton('Part I.D', Icons.warning, 3, context),
            const SizedBox(width: 16),
            _buildTopButton('Part I.E', Icons.computer, 4, context),
          ],
        ),
      ],
    );
  }

  Widget _buildTopButton(String text, IconData icon, int index, BuildContext context) {
    return ElevatedButton.icon(
      onPressed: () {
        setState(() {
          _selectedIndex = index;
        });
        if (index == 0) {
          // Navigate to DocumentPage when Part I.A button is pressed
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (ctx) => IsspSectionEditor(
                sectionId: 'I.A',
                sectionTitle: 'Organizational Profile',
                documentId: 'document',
                onBackPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
          );
        }
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
