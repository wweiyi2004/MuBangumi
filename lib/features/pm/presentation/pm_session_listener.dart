import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../state/website_session_controller.dart';

void watchPmSession(WidgetRef ref, VoidCallback onChanged) {
  ref.listenManual(websiteSessionProvider, (previous, next) {
    if (next.ready &&
        previous?.ready == true &&
        (previous?.snapshot?.authenticationKey !=
                next.snapshot?.authenticationKey ||
            previous?.status != next.status &&
                const {
                  WebsiteAccessStatus.expired,
                  WebsiteAccessStatus.mismatch,
                  WebsiteAccessStatus.missing,
                  WebsiteAccessStatus.challenge,
                }.contains(next.status))) {
      onChanged();
    }
  });
}
