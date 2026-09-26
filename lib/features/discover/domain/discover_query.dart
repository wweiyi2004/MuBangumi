import '../../../models/bangumi_models.dart';

enum DiscoverSearchTarget { subject, character, person }

const discoverEarliestAnimeYear = 1906;
const discoverEarliestOtherYear = 1900;

enum DiscoverQueryMode {
  browse,
  subjectSearch,
  characterPrompt,
  characterSearch,
  personPrompt,
  personSearch,
}

DiscoverQueryMode resolveDiscoverQueryMode({
  required DiscoverSearchTarget target,
  required String keyword,
  required String tag,
  List<String> metaTags = const [],
  bool filterSearch = false,
}) {
  final hasKeyword = keyword.trim().isNotEmpty;
  return switch (target) {
    DiscoverSearchTarget.subject =>
      hasKeyword || tag.trim().isNotEmpty || metaTags.isNotEmpty || filterSearch
          ? DiscoverQueryMode.subjectSearch
          : DiscoverQueryMode.browse,
    DiscoverSearchTarget.character =>
      hasKeyword
          ? DiscoverQueryMode.characterSearch
          : DiscoverQueryMode.characterPrompt,
    DiscoverSearchTarget.person =>
      hasKeyword
          ? DiscoverQueryMode.personSearch
          : DiscoverQueryMode.personPrompt,
  };
}

/// A request captures filters before asynchronous reads begin.
class DiscoverQuery {
  DiscoverQuery({
    this.target = DiscoverSearchTarget.subject,
    this.keyword = '',
    this.tag = '',
    List<String> metaTags = const [],
    this.filterSearch = false,
    this.subjectType = SubjectType.anime,
    required this.browseYear,
    required this.browseQuarter,
    this.browseSort = 'rank',
    this.searchSort = 'match',
    this.minimumRating = 0,
    this.ratingExclusive = false,
    this.startYear = 0,
    this.endYear = 0,
  }) : metaTags = List.unmodifiable(metaTags);
  final DiscoverSearchTarget target;
  final String keyword, tag, browseSort, searchSort;
  final List<String> metaTags;
  final bool filterSearch, ratingExclusive;
  final SubjectType subjectType;
  final int browseYear, browseQuarter, startYear, endYear;
  final double minimumRating;
  bool get supportsSeason =>
      subjectType == SubjectType.anime || subjectType == SubjectType.real;
  DiscoverQueryMode get mode => resolveDiscoverQueryMode(
    target: target,
    keyword: keyword,
    tag: tag,
    metaTags: metaTags,
    filterSearch: filterSearch,
  );
}
