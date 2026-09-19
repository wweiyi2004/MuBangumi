import 'package:flutter/material.dart';

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 52});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFF779D), Color(0xFFE7447A)],
      ),
      borderRadius: BorderRadius.circular(size * .3),
      boxShadow: const [
        BoxShadow(
          color: Color(0x33E95383),
          blurRadius: 20,
          offset: Offset(0, 8),
        ),
      ],
    ),
    child: Icon(
      Icons.play_arrow_rounded,
      color: Colors.white,
      size: size * .64,
    ),
  );
}
