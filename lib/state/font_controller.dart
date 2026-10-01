import 'dart:async';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/font_repository.dart';
import '../models/app_font.dart';

class FontState {
  const FontState({
    this.selected,
    this.imported = const [],
    this.installed = const {},
    this.downloading,
    this.progress = 0,
    this.error,
  });
  final AppFont? selected;
  final List<AppFont> imported;
  final Set<String> installed;
  final String? downloading, error;
  final double progress;
}

class FontController extends StateNotifier<FontState> {
  FontController(this.repository) : super(const FontState()) {
    ready = _restore();
  }
  final FontRepository repository;
  late final Future<void> ready;
  int _revision = 0;
  CancelToken? _cancel;
  Future<void> _saveTail = Future.value();
  Future<void> _restore() async {
    final revision = _revision;
    try {
      final id = await repository.readSelection();
      final installed = await repository.installed();
      final imported = repository is ImportableFontRepository
          ? await (repository as ImportableFontRepository).importedFonts()
          : <AppFont>[];
      final font = [
        ...downloadableFonts,
        ...imported,
      ].where((font) => font.id == id && installed.contains(id)).firstOrNull;
      if (font != null) await repository.activate(font);
      if (mounted && revision == _revision) {
        state = FontState(
          selected: font,
          installed: installed,
          imported: imported,
        );
      }
    } catch (_) {
      if (mounted && revision == _revision) {
        state = const FontState(error: '字体设置暂时无法读取，已使用默认字体');
      }
    }
  }

  Future<void> choose(AppFont? font) async {
    final revision = ++_revision;
    try {
      if (font != null) await repository.activate(font);
      if (!mounted || revision != _revision) return;
      final save = _saveTail.then((_) async {
        if (mounted && revision == _revision) {
          await repository.saveSelection(font?.id);
        }
      });
      _saveTail = save.then<void>((_) {}, onError: (Object _, StackTrace _) {});
      await save;
      if (!mounted || revision != _revision) return;
      state = FontState(
        selected: font,
        imported: state.imported,
        installed: state.installed,
        downloading: state.downloading,
        progress: state.progress,
      );
    } catch (_) {
      if (mounted && revision == _revision) {
        state = FontState(
          selected: state.selected,
          imported: state.imported,
          installed: state.installed,
          downloading: state.downloading,
          progress: state.progress,
          error: '字体无法使用，请重试或重新下载',
        );
      }
    }
  }

  Future<void> download(AppFont font) async {
    if (state.downloading != null) return;
    final revision = ++_revision;
    final cancel = _cancel = CancelToken();
    state = FontState(
      selected: state.selected,
      imported: state.imported,
      installed: state.installed,
      downloading: font.id,
    );
    try {
      await repository.download(font, cancel, (value) {
        if (mounted) {
          state = FontState(
            selected: state.selected,
            imported: state.imported,
            installed: state.installed,
            downloading: font.id,
            progress: value,
          );
        }
      });
      if (!mounted) return;
      state = FontState(
        selected: state.selected,
        imported: state.imported,
        installed: {...state.installed, font.id},
      );
      if (revision == _revision) await choose(font);
    } catch (error) {
      if (mounted) {
        state = FontState(
          selected: state.selected,
          imported: state.imported,
          installed: state.installed,
          error: error is DioException && CancelToken.isCancel(error)
              ? '已取消下载'
              : '字体下载失败，请检查网络后重试',
        );
      }
    } finally {
      if (identical(_cancel, cancel)) _cancel = null;
    }
  }

  Future<void> importFont(String name, Uint8List bytes) async {
    if (state.downloading != null || repository is! ImportableFontRepository) {
      return;
    }
    final revision = ++_revision;
    state = FontState(
      selected: state.selected,
      imported: state.imported,
      installed: state.installed,
      downloading: 'import',
    );
    try {
      final font = await (repository as ImportableFontRepository).importFont(
        name,
        bytes,
      );
      if (!mounted) return;
      final imported = await (repository as ImportableFontRepository)
          .importedFonts();
      final installed = await repository.installed();
      if (!mounted) return;
      state = FontState(
        selected: state.selected,
        imported: imported,
        installed: installed,
      );
      if (revision == _revision) await choose(font);
    } catch (error) {
      if (mounted) {
        state = FontState(
          selected: state.selected,
          imported: state.imported,
          installed: state.installed,
          error: error.toString().replaceFirst('FormatException: ', ''),
        );
      }
    }
  }

  void cancelDownload() => _cancel?.cancel();
  Future<void> remove(AppFont font) async {
    if (state.downloading != null) return;
    try {
      if (state.selected?.id == font.id) await choose(null);
      if (state.selected?.id == font.id) return;
      await repository.remove(font);
      if (mounted) {
        state = FontState(
          selected: state.selected,
          installed: {...state.installed}..remove(font.id),
          imported: state.imported.where((f) => f.id != font.id).toList(),
        );
      }
    } catch (_) {
      if (mounted) {
        state = FontState(
          selected: state.selected,
          imported: state.imported,
          installed: state.installed,
          error: '字体移除失败，请重试',
        );
      }
    }
  }

  @override
  void dispose() {
    _cancel?.cancel();
    super.dispose();
  }
}

final fontRepositoryProvider = Provider<FontRepository>(
  (ref) => LocalFontRepository(),
);
final fontProvider = StateNotifierProvider<FontController, FontState>(
  (ref) => FontController(ref.watch(fontRepositoryProvider)),
);

ThemeData applyAppFont(ThemeData theme, AppFont? font) {
  if (font == null) return theme;
  ButtonStyle? style(ButtonStyle? value) => value?.copyWith(
    textStyle: WidgetStateProperty.resolveWith(
      (states) => (value.textStyle?.resolve(states) ?? const TextStyle())
          .copyWith(fontFamily: font.family),
    ),
  );
  return theme.copyWith(
    popupMenuTheme: theme.popupMenuTheme.copyWith(
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) =>
            (theme.popupMenuTheme.labelTextStyle?.resolve(s) ??
                    const TextStyle())
                .copyWith(fontFamily: font.family),
      ),
      textStyle: theme.popupMenuTheme.textStyle?.copyWith(
        fontFamily: font.family,
      ),
    ),
    menuButtonTheme: MenuButtonThemeData(
      style: style(theme.menuButtonTheme.style),
    ),
    dropdownMenuTheme: theme.dropdownMenuTheme.copyWith(
      textStyle: theme.dropdownMenuTheme.textStyle?.copyWith(
        fontFamily: font.family,
      ),
    ),
    textTheme: theme.textTheme.apply(fontFamily: font.family),
    primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: font.family),
    filledButtonTheme: FilledButtonThemeData(
      style: style(theme.filledButtonTheme.style),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: style(theme.outlinedButtonTheme.style),
    ),
    textButtonTheme: TextButtonThemeData(
      style: style(theme.textButtonTheme.style),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: style(theme.elevatedButtonTheme.style),
    ),
    chipTheme: theme.chipTheme.copyWith(
      labelStyle: theme.chipTheme.labelStyle?.copyWith(fontFamily: font.family),
      secondaryLabelStyle: theme.chipTheme.secondaryLabelStyle?.copyWith(
        fontFamily: font.family,
      ),
    ),
  );
}
