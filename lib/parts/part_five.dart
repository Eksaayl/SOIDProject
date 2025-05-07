import 'package:flutter/material.dart';

class Part5 extends StatefulWidget {
  const Part5({super.key});

  @override
  _Part5State createState() => _Part5State();
}

class _Part5State extends State<Part5> {
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
              ' DEVELOPMENT AND INVESTMENT PROGRAM',
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
                    _buildTopButton('Part V.A', Icons.calendar_today, 0),
                    const SizedBox(width: 16),
                    _buildTopButton('Part V.B', Icons.event, 1),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildTopButton('Part V.C', Icons.attach_money, 2),
                    const SizedBox(width: 16),
                    _buildTopButton('Part V.D', Icons.pie_chart_outline, 3),
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
          ' DEVELOPMENT AND INVESTMENT PROGRAM',
          style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 24),

        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildTopButton('Part V.A', Icons.calendar_today, 0),
            const SizedBox(width: 16),
            _buildTopButton('Part V.B', Icons.event, 1),
            const SizedBox(width: 16),
            _buildTopButton('Part V.C', Icons.attach_money, 2),
            const SizedBox(width: 16),
            _buildTopButton('Part V.D', Icons.pie_chart_outline, 3),
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
