import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../widgets/friend_qr_scan_overlay.dart';

class FriendQrScanPage extends StatefulWidget {
  const FriendQrScanPage({super.key});

  @override
  State<FriendQrScanPage> createState() => _FriendQrScanPageState();
}

class _FriendQrScanPageState extends State<FriendQrScanPage> {
  bool _handled = false;

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue?.trim() ?? '';
      if (value.isEmpty) continue;
      _handled = true;
      Navigator.of(context).pop(value);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('扫描好友二维码'),
        actions: [
          IconButton(
            tooltip: '从图片识别',
            onPressed: () => Navigator.of(context).pop('__pick_image__'),
            icon: const Icon(Icons.photo_outlined),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(onDetect: _onDetect),
          const FriendQrScanOverlay(),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
              child: Text(
                '将对方的 MuBangumi 二维码放入框内',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
