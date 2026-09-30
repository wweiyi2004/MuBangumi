String draftAutosaveLabel({
  required bool saving,
  required bool saved,
  bool unsaved = false,
}) => saving
    ? '正在保存草稿…'
    : unsaved
    ? '草稿尚未保存'
    : saved
    ? '草稿已保存在本机'
    : '草稿会自动保存在本机';
