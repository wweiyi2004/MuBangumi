import 'bangumi_models.dart';

/// Numeric constraints shared by API requests and the visible result list.
class SubjectSearchFilter {
  const SubjectSearchFilter({
    this.minimumRating = 0,
    this.ratingExclusive = false,
    this.startYear = 0,
    this.endYear = 0,
  });

  final num minimumRating;
  final bool ratingExclusive;
  final int startYear;
  final int endYear;
  bool get hasRating => minimumRating > 0 || ratingExclusive;

  void validate() {
    if (!minimumRating.isFinite || minimumRating < 0 || minimumRating > 10) {
      throw ArgumentError.value(
        minimumRating,
        'minimumRating',
        'Expected 0–10',
      );
    }
    if (startYear < 0 ||
        endYear < 0 ||
        startYear > 9998 ||
        endYear > 9998 ||
        (startYear > 0 && endYear > 0 && startYear > endYear)) {
      throw ArgumentError('Invalid inclusive year range');
    }
  }

  bool permits(Subject subject) {
    if (hasRating) {
      final rating = subject.score;
      if (!rating.isFinite ||
          rating <= 0 ||
          (ratingExclusive
              ? rating <= minimumRating
              : rating < minimumRating)) {
        return false;
      }
    }
    if (startYear > 0 || endYear > 0) {
      final match = RegExp(r'^(\d{4})(?:-|$)').firstMatch(subject.date.trim());
      final year = match == null ? null : int.tryParse(match[1]!);
      if (year == null ||
          year <= 0 ||
          (startYear > 0 && year < startYear) ||
          (endYear > 0 && year > endYear)) {
        return false;
      }
    }
    return true;
  }
}
