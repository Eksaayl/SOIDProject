import 'package:flutter/material.dart';

class MeditationApp extends StatelessWidget {
  const MeditationApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const HorizontalTabsPage(),
    );
  }
}

class HorizontalTabsPage extends StatefulWidget {
  const HorizontalTabsPage({super.key});

  @override
  State<HorizontalTabsPage> createState() => _HorizontalTabsPageState();
}

class _HorizontalTabsPageState extends State<HorizontalTabsPage> {
  int _selectedIndex = 0;

  final List<String> _tabs = ['Part 1', 'Part 2', 'Part 3', 'Part 4', 'Part 5'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF6F3),
      body: Column(
        children: [
          const SizedBox(height: 40),
          const Text(
            'How Monsfer Works',
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),

          // TABS first (swapped up)
          Container(
            height: 60,
            color: const Color(0xFFE0DAD2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: List.generate(_tabs.length, (index) {
                final bool selected = _selectedIndex == index;
                return GestureDetector(
                  onTap: () => setState(() => _selectedIndex = index),
                  child: Container(
                    margin: const EdgeInsets.only(right: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      color: selected ? const Color(0xFFF5F3F1) : const Color(0xFFD0C9C0),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        _tabs[index],
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: selected ? Colors.black : Colors.black54,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),

          const SizedBox(height: 24),

          // 3 Buttons second (below tabs now)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildTopButton('1- Download', Icons.download, false),
              const SizedBox(width: 16),
              _buildTopButton('2- Signup', Icons.person, false),
              const SizedBox(width: 16),
              _buildTopButton('3- Connect', Icons.link, false),
            ],
          ),

          const SizedBox(height: 24),

          // Big main box
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xff021e84), // Bright lime background
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.black),
              ),
              child: Row(
                children: [
                  // Left side: Text
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Text(
                          'Send & Receive\nPayments',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Pay friends & family at other banks choosing them from your contacts.\n'
                              'Create a group to fund a cause or simply participate a gift.\n\n'
                              '✔ Pay in stores using NFC\n'
                              '✔ Receive payments from friends and family\n'
                              '✔ Receive payments from customers',
                          style: TextStyle(fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  // Right side: Image placeholder
                  Expanded(
                    flex: 2,
                    child: Container(
                      color: Colors.white,
                      child: const Center(
                        child: Text(
                          'Image Here',
                          style: TextStyle(fontSize: 18, color: Colors.black45),
                        ),
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

  Widget _buildTopButton(String text, IconData icon, bool selected) {
    return ElevatedButton.icon(
      onPressed: () {},
      icon: Icon(icon, color: selected ? Colors.white : Colors.black),
      label: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: selected ? Colors.white : Colors.black,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: selected ? const Color(0xff021e84) : Colors.transparent,
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
