enum FeedbackCategory {
  problem('problem'),
  suggestion('suggestion'),
  other('other');

  const FeedbackCategory(this.value);
  final String value;
}

class FeedbackDeviceInfo {
  const FeedbackDeviceInfo({
    required this.appVersion,
    required this.buildNumber,
    required this.platform,
  });

  final String appVersion;
  final String buildNumber;
  final String platform;
}

class FeedbackSubmission {
  const FeedbackSubmission({
    required this.category,
    required this.message,
    required this.email,
    required this.includeDeviceInfo,
    required this.deviceInfo,
  });

  final FeedbackCategory category;
  final String message;
  final String email;
  final bool includeDeviceInfo;
  final FeedbackDeviceInfo deviceInfo;

  Map<String, dynamic> toJson() => {
    'category': category.value,
    'message': message.trim(),
    'email': email.trim(),
    'includeDeviceInfo': includeDeviceInfo,
    'appVersion': includeDeviceInfo ? deviceInfo.appVersion : '',
    'buildNumber': includeDeviceInfo ? deviceInfo.buildNumber : '',
    'platform': includeDeviceInfo ? deviceInfo.platform : '',
    'website': '',
  };
}
