import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class BallInputWidget extends StatelessWidget {
  final Function(String) onInput;

  const BallInputWidget({Key? key, required this.onInput}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("What happened?", style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              _buildBallButton(context, "0", Colors.grey.shade300, Colors.black),
              _buildBallButton(context, "1", Colors.blue.shade100, Colors.blue.shade900),
              _buildBallButton(context, "2", Colors.blue.shade100, Colors.blue.shade900),
              _buildBallButton(context, "3", Colors.blue.shade100, Colors.blue.shade900),
              _buildBallButton(context, "4", Colors.green.shade100, Colors.green.shade900),
              _buildBallButton(context, "6", Colors.purple.shade100, Colors.purple.shade900),
              _buildBallButton(context, "WD", Colors.orange.shade100, Colors.orange.shade900),
              _buildBallButton(context, "WD 4", Colors.orange.shade100, Colors.orange.shade900, fontSize: 14),
              _buildBallButton(context, "NB", Colors.orange.shade100, Colors.orange.shade900),
              _buildBallButton(context, "W", Colors.red.shade100, Colors.red.shade900),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildBallButton(BuildContext context, String label, Color bgColor, Color textColor, {double fontSize = 18}) {
    return GestureDetector(
      onTap: () => onInput(label),
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: bgColor,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            )
          ],
        ),
        child: Center(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }
}
