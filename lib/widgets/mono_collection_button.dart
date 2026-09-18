import 'dart:async';
import 'package:flutter/material.dart';
import '../core/network/community_service.dart';
import '../models/community_models.dart';

class MonoCollectionButton extends StatefulWidget {
  const MonoCollectionButton({
    super.key,
    required this.kind,
    required this.id,
    this.service,
    this.onChanged,
  });
  final CommunityTimelineTargetKind kind;
  final int id;
  final CommunityService? service;
  final ValueChanged<CommunityMonoCollection>? onChanged;
  @override
  State<MonoCollectionButton> createState() => _MonoCollectionButtonState();
}

class _MonoCollectionButtonState extends State<MonoCollectionButton> {
  CommunityService get _service => widget.service ?? CommunityService.shared;
  CommunityMonoCollection? _value;
  bool _busy = false;
  String? _error;
  int _generation = 0;
  String get _label =>
      widget.kind == CommunityTimelineTargetKind.character ? '角色' : '人物';

  @override
  void initState() {
    super.initState();
    _service.accountChanges.addListener(_reset);
    unawaited(_load());
  }

  void _reset() {
    _generation++;
    scheduleMicrotask(() {
      if (mounted) {
        setState(() {
          _value = null;
          _error = null;
        });
        unawaited(_load());
      }
    });
  }

  @override
  void didUpdateWidget(covariant MonoCollectionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service) {
      (oldWidget.service ?? CommunityService.shared).accountChanges
          .removeListener(_reset);
      _service.accountChanges.addListener(_reset);
    }
    if (oldWidget.service != widget.service ||
        oldWidget.id != widget.id ||
        oldWidget.kind != widget.kind) {
      _reset();
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    if (!_service.isAuthenticated) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _service.loadMonoCollection(
        widget.kind,
        widget.id,
        refresh: true,
      );
      if (!mounted || generation != _generation) return;
      setState(() => _value = result);
      widget.onChanged?.call(result);
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = '$error');
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _toggle() async {
    if (_busy) return;
    if (_value == null) {
      await _load();
      return;
    }
    final generation = _generation;
    final previous = _value!;
    final collected = !previous.collected;
    setState(() => _busy = true);
    try {
      await _service.setMonoCollection(
        widget.kind,
        widget.id,
        collected: collected,
      );
      if (!mounted || generation != _generation) return;
      final result = CommunityMonoCollection(
        collected: collected,
        count: (previous.count + (collected ? 1 : -1)).clamp(0, 1 << 31),
      );
      setState(() {
        _value = result;
        _error = null;
      });
      widget.onChanged?.call(result);
      try {
        final fresh = await _service.loadMonoCollection(
          widget.kind,
          widget.id,
          refresh: true,
        );
        if (!mounted || generation != _generation) return;
        setState(() => _value = fresh);
        widget.onChanged?.call(fresh);
      } catch (_) {
        /* The acknowledged write remains visible if recount fails. */
      }
    } catch (error) {
      if (!mounted || generation != _generation) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error'.replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _generation++;
    _service.accountChanges.removeListener(_reset);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: !_service.isAuthenticated
        ? '登录后收藏$_label'
        : _error != null
        ? '收藏状态加载失败，点击重试'
        : '${_value?.collected == true ? '取消收藏' : '收藏'}$_label${_value == null ? '' : ' · ${_value!.count} 人收藏'}',
    onPressed: !_service.isAuthenticated || _busy ? null : _toggle,
    icon: _busy
        ? const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(
            _error != null
                ? Icons.refresh_rounded
                : _value?.collected == true
                ? Icons.favorite
                : Icons.favorite_border,
          ),
  );
}
