import 'package:flutter/material.dart';

/// A round white button with an emoji, used for home/reset actions.
class RoundButton extends StatelessWidget {
  const RoundButton({
    super.key,
    required this.emoji,
    required this.onTap,
    this.fontSize = 22,
  });

  final String emoji;
  final VoidCallback onTap;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Text(emoji, style: TextStyle(fontSize: fontSize)),
        ),
      ),
    );
  }
}
