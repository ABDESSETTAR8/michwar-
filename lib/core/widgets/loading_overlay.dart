import 'package:flutter/material.dart';

/// Full-screen translucent loading indicator overlay, used while waiting
/// for OTP verification, ride matching, or Cloud Function calls.
class LoadingOverlay extends StatelessWidget {
  const LoadingOverlay({super.key, required this.show, required this.child, this.message});

  final bool show;
  final Widget child;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (show)
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.25),
              child: Center(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        if (message != null) ...[
                          const SizedBox(height: 16),
                          Text(message!),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
