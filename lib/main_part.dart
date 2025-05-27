import 'package:flutter/material.dart';
import 'Parts/part_five.dart';
import 'Parts/part_four.dart';
import 'Parts/part_one.dart';
import 'Parts/part_three.dart';
import 'Parts/part_two.dart';

class HorizontalTabsPage extends StatefulWidget {
  const HorizontalTabsPage({super.key});

  @override
  State<HorizontalTabsPage> createState() => _HorizontalTabsPageState();
}

class _HorizontalTabsPageState extends State<HorizontalTabsPage> {
  int _selectedIndex = 0;

  final List<Map<String, dynamic>> _tabs = [
    {'label': 'Part I', 'content': const Part1()},
    {'label': 'Part II', 'content': const Part2()},
    {'label': 'Part III', 'content': const Part3()},
    {'label': 'Part IV', 'content': const Part4()},
    {'label': 'Part V', 'content': const Part5()},
  ];

  @override
  Widget build(BuildContext context) {
    // Determine screen width
    final bool isSmallScreen = MediaQuery.of(context).size.width < 650;
    final bool isSmallerScreen = MediaQuery.of(context).size.width < 450;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // Tab Section
          Container(
            height: isSmallScreen ? 50 : 60,
            color: const Color(0xFFE0DAD2),
            child: Row(
              children: List.generate(_tabs.length, (index) {
                final bool selected = _selectedIndex == index;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedIndex = index;
                    });
                  },
                  child: Expanded(
                    child: Container(
                      width: isSmallScreen ? 70 : 120,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: selected ? Colors.white : const Color(0xFFD0C9C0),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          _tabs[index]['label'],
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: isSmallScreen ? 14 : 16,
                            color: selected ? Colors.black : Colors.black54,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 16),

          Expanded(
            child: _tabs[_selectedIndex]['content'],
          ),
        ],
      ),
    );
  }
}
