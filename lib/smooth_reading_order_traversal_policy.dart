// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

void _focusAndEnsureVisible(
  FocusNode node, {
  ScrollPositionAlignmentPolicy alignmentPolicy = ScrollPositionAlignmentPolicy.explicit,
}) {
  node.requestFocus();
  Scrollable.ensureVisible(node.context!, alignment: 1.0, alignmentPolicy: alignmentPolicy);
}

BuildContext? _getAncestor(BuildContext context, {int count = 1}) {
  BuildContext? target;
  context.visitAncestorElements((Element ancestor) {
    count--;
    if (count == 0) {
      target = ancestor;
      return false;
    }
    return true;
  });
  return target;
}

class _DirectionalPolicyDataEntry {
  const _DirectionalPolicyDataEntry({required this.direction, required this.node});

  final TraversalDirection direction;
  final FocusNode node;
}

class _DirectionalPolicyData {
  const _DirectionalPolicyData({required this.history});

  final List<_DirectionalPolicyDataEntry> history;
}

mixin SmoothDirectionalFocusTraversalPolicyMixin on FocusTraversalPolicy {
  final Map<FocusScopeNode, _DirectionalPolicyData> _policyData = <FocusScopeNode, _DirectionalPolicyData>{};
  late final void Function(FocusNode node, {ScrollPositionAlignmentPolicy alignmentPolicy}) requestFocusCallback;

  @override
  void invalidateScopeData(FocusScopeNode node) {
    super.invalidateScopeData(node);
    _policyData.remove(node);
  }

  @override
  void changedScope({FocusNode? node, FocusScopeNode? oldScope}) {
    super.changedScope(node: node, oldScope: oldScope);
    if (oldScope != null) {
      _policyData[oldScope]?.history.removeWhere((_DirectionalPolicyDataEntry entry) {
        return entry.node == node;
      });
    }
  }

  @override
  FocusNode? findFirstFocusInDirection(FocusNode currentNode, TraversalDirection direction) {
    switch (direction) {
      case TraversalDirection.up:
        return _sortAndFindInitial(currentNode, vertical: true, first: false);
      case TraversalDirection.down:
        return _sortAndFindInitial(currentNode, vertical: true, first: true);
      case TraversalDirection.left:
        return _sortAndFindInitial(currentNode, vertical: false, first: false);
      case TraversalDirection.right:
        return _sortAndFindInitial(currentNode, vertical: false, first: true);
    }
  }

  FocusNode? _sortAndFindInitial(FocusNode currentNode, {required bool vertical, required bool first}) {
    final Iterable<FocusNode> nodes = currentNode.nearestScope!.traversalDescendants;
    final List<FocusNode> sorted = nodes.toList();
    mergeSort<FocusNode>(sorted, compare: (FocusNode a, FocusNode b) {
      if (vertical) {
        if (first) {
          return a.rect.top.compareTo(b.rect.top);
        } else {
          return b.rect.bottom.compareTo(a.rect.bottom);
        }
      } else {
        if (first) {
          return a.rect.left.compareTo(b.rect.left);
        } else {
          return b.rect.right.compareTo(a.rect.right);
        }
      }
    });

    if (sorted.isNotEmpty) {
      return sorted.first;
    }

    return null;
  }

  Iterable<FocusNode>? _sortAndFilterHorizontally(
    TraversalDirection direction,
    Rect target,
    FocusNode nearestScope,
  ) {
    assert(direction == TraversalDirection.left || direction == TraversalDirection.right);
    final Iterable<FocusNode> nodes = nearestScope.traversalDescendants;
    assert(!nodes.contains(nearestScope));
    final List<FocusNode> sorted = nodes.toList();
    mergeSort<FocusNode>(sorted, compare: (FocusNode a, FocusNode b) => a.rect.center.dx.compareTo(b.rect.center.dx));
    Iterable<FocusNode>? result;
    switch (direction) {
      case TraversalDirection.left:
        result = sorted.where((FocusNode node) => node.rect != target && node.rect.center.dx <= target.left);
        break;
      case TraversalDirection.right:
        result = sorted.where((FocusNode node) => node.rect != target && node.rect.center.dx >= target.right);
        break;
      case TraversalDirection.up:
      case TraversalDirection.down:
        break;
    }
    return result;
  }

  Iterable<FocusNode>? _sortAndFilterVertically(
    TraversalDirection direction,
    Rect target,
    Iterable<FocusNode> nodes,
  ) {
    final List<FocusNode> sorted = nodes.toList();
    mergeSort<FocusNode>(sorted, compare: (FocusNode a, FocusNode b) => a.rect.center.dy.compareTo(b.rect.center.dy));
    switch (direction) {
      case TraversalDirection.up:
        return sorted.where((FocusNode node) => node.rect != target && node.rect.center.dy <= target.top);
      case TraversalDirection.down:
        return sorted.where((FocusNode node) => node.rect != target && node.rect.center.dy >= target.bottom);
      case TraversalDirection.left:
      case TraversalDirection.right:
        break;
    }
    assert(direction == TraversalDirection.up || direction == TraversalDirection.down);
    return null;
  }

  bool _popPolicyDataIfNeeded(TraversalDirection direction, FocusScopeNode nearestScope, FocusNode focusedChild) {
    final _DirectionalPolicyData? policyData = _policyData[nearestScope];
    if (policyData != null && policyData.history.isNotEmpty && policyData.history.first.direction != direction) {
      if (policyData.history.last.node.parent == null) {
        invalidateScopeData(nearestScope);
        return false;
      }

      bool popOrInvalidate(TraversalDirection direction) {
        final FocusNode lastNode = policyData.history.removeLast().node;
        if (Scrollable.of(lastNode.context!) != Scrollable.of(primaryFocus!.context!)) {
          invalidateScopeData(nearestScope);
          return false;
        }
        final ScrollPositionAlignmentPolicy alignmentPolicy;
        switch (direction) {
          case TraversalDirection.up:
          case TraversalDirection.left:
            alignmentPolicy = ScrollPositionAlignmentPolicy.keepVisibleAtStart;
            break;
          case TraversalDirection.right:
          case TraversalDirection.down:
            alignmentPolicy = ScrollPositionAlignmentPolicy.keepVisibleAtEnd;
            break;
        }
        requestFocusCallback(
          lastNode,
          alignmentPolicy: alignmentPolicy,
        );
        return true;
      }

      switch (direction) {
        case TraversalDirection.down:
        case TraversalDirection.up:
          switch (policyData.history.first.direction) {
            case TraversalDirection.left:
            case TraversalDirection.right:
              invalidateScopeData(nearestScope);
              break;
            case TraversalDirection.up:
            case TraversalDirection.down:
              if (popOrInvalidate(direction)) {
                return true;
              }
              break;
          }
          break;
        case TraversalDirection.left:
        case TraversalDirection.right:
          switch (policyData.history.first.direction) {
            case TraversalDirection.left:
            case TraversalDirection.right:
              if (popOrInvalidate(direction)) {
                return true;
              }
              break;
            case TraversalDirection.up:
            case TraversalDirection.down:
              invalidateScopeData(nearestScope);
              break;
          }
      }
    }
    if (policyData != null && policyData.history.isEmpty) {
      invalidateScopeData(nearestScope);
    }
    return false;
  }

  void _pushPolicyData(TraversalDirection direction, FocusScopeNode nearestScope, FocusNode focusedChild) {
    final _DirectionalPolicyData? policyData = _policyData[nearestScope];
    final _DirectionalPolicyDataEntry newEntry = _DirectionalPolicyDataEntry(node: focusedChild, direction: direction);
    if (policyData != null) {
      policyData.history.add(newEntry);
    } else {
      _policyData[nearestScope] = _DirectionalPolicyData(history: <_DirectionalPolicyDataEntry>[newEntry]);
    }
  }

  @mustCallSuper
  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    final FocusScopeNode nearestScope = currentNode.nearestScope!;
    final FocusNode? focusedChild = nearestScope.focusedChild;
    if (focusedChild == null) {
      final FocusNode firstFocus = findFirstFocusInDirection(currentNode, direction) ?? currentNode;
      switch (direction) {
        case TraversalDirection.up:
        case TraversalDirection.left:
          requestFocusCallback(
            firstFocus,
            alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
          );
          break;
        case TraversalDirection.right:
        case TraversalDirection.down:
          requestFocusCallback(
            firstFocus,
            alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          );
          break;
      }
      return true;
    }
    if (_popPolicyDataIfNeeded(direction, nearestScope, focusedChild)) {
      return true;
    }
    FocusNode? found;
    final ScrollableState? focusedScrollable = Scrollable.of(focusedChild.context!);
    switch (direction) {
      case TraversalDirection.down:
      case TraversalDirection.up:
        Iterable<FocusNode>? eligibleNodes = _sortAndFilterVertically(
          direction,
          focusedChild.rect,
          nearestScope.traversalDescendants,
        );
        if (focusedScrollable != null && !focusedScrollable.position.atEdge) {
          final Iterable<FocusNode> filteredEligibleNodes =
              eligibleNodes!.where((FocusNode node) => Scrollable.of(node.context!) == focusedScrollable);
          if (filteredEligibleNodes.isNotEmpty) {
            eligibleNodes = filteredEligibleNodes;
          }
        }
        if (eligibleNodes!.isEmpty) {
          break;
        }
        List<FocusNode> sorted = eligibleNodes.toList();
        if (direction == TraversalDirection.up) {
          sorted = sorted.reversed.toList();
        }
        final Rect band =
            Rect.fromLTRB(focusedChild.rect.left, -double.infinity, focusedChild.rect.right, double.infinity);
        final Iterable<FocusNode> inBand = sorted.where((FocusNode node) => !node.rect.intersect(band).isEmpty);
        if (inBand.isNotEmpty) {
          found = inBand.first;
          break;
        }
        mergeSort<FocusNode>(sorted, compare: (FocusNode a, FocusNode b) {
          return (a.rect.center.dx - focusedChild.rect.center.dx)
              .abs()
              .compareTo((b.rect.center.dx - focusedChild.rect.center.dx).abs());
        });
        found = sorted.first;
        break;
      case TraversalDirection.right:
      case TraversalDirection.left:
        Iterable<FocusNode>? eligibleNodes = _sortAndFilterHorizontally(direction, focusedChild.rect, nearestScope);
        if (focusedScrollable != null && !focusedScrollable.position.atEdge) {
          final Iterable<FocusNode> filteredEligibleNodes =
              eligibleNodes!.where((FocusNode node) => Scrollable.of(node.context!) == focusedScrollable);
          if (filteredEligibleNodes.isNotEmpty) {
            eligibleNodes = filteredEligibleNodes;
          }
        }
        if (eligibleNodes!.isEmpty) {
          break;
        }
        List<FocusNode> sorted = eligibleNodes.toList();
        if (direction == TraversalDirection.left) {
          sorted = sorted.reversed.toList();
        }
        final Rect band =
            Rect.fromLTRB(-double.infinity, focusedChild.rect.top, double.infinity, focusedChild.rect.bottom);
        final Iterable<FocusNode> inBand = sorted.where((FocusNode node) => !node.rect.intersect(band).isEmpty);
        if (inBand.isNotEmpty) {
          found = inBand.first;
          break;
        }
        mergeSort<FocusNode>(sorted, compare: (FocusNode a, FocusNode b) {
          return (a.rect.center.dy - focusedChild.rect.center.dy)
              .abs()
              .compareTo((b.rect.center.dy - focusedChild.rect.center.dy).abs());
        });
        found = sorted.first;
        break;
    }
    if (found != null) {
      _pushPolicyData(direction, nearestScope, focusedChild);
      switch (direction) {
        case TraversalDirection.up:
        case TraversalDirection.left:
          requestFocusCallback(
            found,
            alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
          );
          break;
        case TraversalDirection.down:
        case TraversalDirection.right:
          requestFocusCallback(
            found,
            alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          );
          break;
      }
      return true;
    }
    return false;
  }
}

class _ReadingOrderSortData with Diagnosticable {
  _ReadingOrderSortData(this.node)
      : rect = node.rect,
        directionality = _findDirectionality(node.context!);

  final TextDirection? directionality;
  final Rect rect;
  final FocusNode node;

  static TextDirection? _findDirectionality(BuildContext context) {
    return (context.getElementForInheritedWidgetOfExactType<Directionality>()?.widget as Directionality?)
        ?.textDirection;
  }

  static TextDirection? commonDirectionalityOf(List<_ReadingOrderSortData> list) {
    final Iterable<Set<Directionality>> allAncestors =
        list.map<Set<Directionality>>((_ReadingOrderSortData member) => member.directionalAncestors.toSet());
    Set<Directionality>? common;
    for (final Set<Directionality> ancestorSet in allAncestors) {
      common ??= ancestorSet;
      common = common.intersection(ancestorSet);
    }
    if (common!.isEmpty) {
      return list.first.directionality;
    }
    return list.first.directionalAncestors.firstWhere(common.contains).textDirection;
  }

  static void sortWithDirectionality(List<_ReadingOrderSortData> list, TextDirection directionality) {
    mergeSort<_ReadingOrderSortData>(list, compare: (_ReadingOrderSortData a, _ReadingOrderSortData b) {
      switch (directionality) {
        case TextDirection.ltr:
          return a.rect.left.compareTo(b.rect.left);
        case TextDirection.rtl:
          return b.rect.right.compareTo(a.rect.right);
      }
    });
  }

  Iterable<Directionality> get directionalAncestors {
    List<Directionality> getDirectionalityAncestors(BuildContext context) {
      final List<Directionality> result = <Directionality>[];
      InheritedElement? directionalityElement = context.getElementForInheritedWidgetOfExactType<Directionality>();
      while (directionalityElement != null) {
        result.add(directionalityElement.widget as Directionality);
        directionalityElement =
            _getAncestor(directionalityElement)?.getElementForInheritedWidgetOfExactType<Directionality>();
      }
      return result;
    }

    _directionalAncestors ??= getDirectionalityAncestors(node.context!);
    return _directionalAncestors!;
  }

  List<Directionality>? _directionalAncestors;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<TextDirection>('directionality', directionality));
    properties.add(StringProperty('name', node.debugLabel, defaultValue: null));
    properties.add(DiagnosticsProperty<Rect>('rect', rect));
  }
}

class _ReadingOrderDirectionalGroupData with Diagnosticable {
  _ReadingOrderDirectionalGroupData(this.members);

  final List<_ReadingOrderSortData> members;

  TextDirection? get directionality => members.first.directionality;

  Rect? _rect;

  Rect get rect {
    if (_rect == null) {
      for (final Rect rect in members.map<Rect>((_ReadingOrderSortData data) => data.rect)) {
        _rect ??= rect;
        _rect = _rect!.expandToInclude(rect);
      }
    }
    return _rect!;
  }

  List<Directionality> get memberAncestors {
    if (_memberAncestors == null) {
      _memberAncestors = <Directionality>[];
      for (final _ReadingOrderSortData member in members) {
        _memberAncestors!.addAll(member.directionalAncestors);
      }
    }
    return _memberAncestors!;
  }

  List<Directionality>? _memberAncestors;

  static void sortWithDirectionality(List<_ReadingOrderDirectionalGroupData> list, TextDirection directionality) {
    mergeSort<_ReadingOrderDirectionalGroupData>(list,
        compare: (_ReadingOrderDirectionalGroupData a, _ReadingOrderDirectionalGroupData b) {
      switch (directionality) {
        case TextDirection.ltr:
          return a.rect.left.compareTo(b.rect.left);
        case TextDirection.rtl:
          return b.rect.right.compareTo(a.rect.right);
      }
    });
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<TextDirection>('directionality', directionality));
    properties.add(DiagnosticsProperty<Rect>('rect', rect));
    properties.add(IterableProperty<String>('members', members.map<String>((_ReadingOrderSortData member) {
      return '"${member.node.debugLabel}"(${member.rect})';
    })));
  }
}

class SmoothReadingOrderTraversalPolicy extends FocusTraversalPolicy with SmoothDirectionalFocusTraversalPolicyMixin {
  @override
  // ignore: overridden_fields
  final void Function(FocusNode node, {ScrollPositionAlignmentPolicy alignmentPolicy}) requestFocusCallback;

  SmoothReadingOrderTraversalPolicy({this.requestFocusCallback = _focusAndEnsureVisible});

  List<_ReadingOrderDirectionalGroupData> _collectDirectionalityGroups(Iterable<_ReadingOrderSortData> candidates) {
    TextDirection? currentDirection = candidates.first.directionality;
    List<_ReadingOrderSortData> currentGroup = <_ReadingOrderSortData>[];
    final List<_ReadingOrderDirectionalGroupData> result = <_ReadingOrderDirectionalGroupData>[];
    for (final _ReadingOrderSortData candidate in candidates) {
      if (candidate.directionality == currentDirection) {
        currentGroup.add(candidate);
        continue;
      }
      currentDirection = candidate.directionality;
      result.add(_ReadingOrderDirectionalGroupData(currentGroup));
      currentGroup = <_ReadingOrderSortData>[candidate];
    }
    if (currentGroup.isNotEmpty) {
      result.add(_ReadingOrderDirectionalGroupData(currentGroup));
    }
    for (final _ReadingOrderDirectionalGroupData bandGroup in result) {
      if (bandGroup.members.length == 1) {
        continue;
      }
      _ReadingOrderSortData.sortWithDirectionality(bandGroup.members, bandGroup.directionality!);
    }
    return result;
  }

  _ReadingOrderSortData _pickNext(List<_ReadingOrderSortData> candidates) {
    mergeSort<_ReadingOrderSortData>(candidates,
        compare: (_ReadingOrderSortData a, _ReadingOrderSortData b) => a.rect.top.compareTo(b.rect.top));
    final _ReadingOrderSortData topmost = candidates.first;

    List<_ReadingOrderSortData> inBand(_ReadingOrderSortData current, Iterable<_ReadingOrderSortData> candidates) {
      final Rect band = Rect.fromLTRB(double.negativeInfinity, current.rect.top, double.infinity, current.rect.bottom);
      return candidates.where((_ReadingOrderSortData item) {
        return !item.rect.intersect(band).isEmpty;
      }).toList();
    }

    final List<_ReadingOrderSortData> inBandOfTop = inBand(topmost, candidates);
    assert(topmost.rect.isEmpty || inBandOfTop.isNotEmpty);

    if (inBandOfTop.length <= 1) {
      return topmost;
    }

    final TextDirection? nearestCommonDirectionality = _ReadingOrderSortData.commonDirectionalityOf(inBandOfTop);

    _ReadingOrderSortData.sortWithDirectionality(inBandOfTop, nearestCommonDirectionality!);

    final List<_ReadingOrderDirectionalGroupData> bandGroups = _collectDirectionalityGroups(inBandOfTop);
    if (bandGroups.length == 1) {
      return bandGroups.first.members.first;
    }

    _ReadingOrderDirectionalGroupData.sortWithDirectionality(bandGroups, nearestCommonDirectionality);
    return bandGroups.first.members.first;
  }

  @override
  Iterable<FocusNode> sortDescendants(Iterable<FocusNode> descendants, FocusNode currentNode) {
    if (descendants.length <= 1) {
      return descendants;
    }

    final List<_ReadingOrderSortData> data = <_ReadingOrderSortData>[
      for (final FocusNode node in descendants) _ReadingOrderSortData(node),
    ];

    final List<FocusNode> sortedList = <FocusNode>[];
    final List<_ReadingOrderSortData> unplaced = data;

    _ReadingOrderSortData current = _pickNext(unplaced);
    sortedList.add(current.node);
    unplaced.remove(current);

    while (unplaced.isNotEmpty) {
      final _ReadingOrderSortData next = _pickNext(unplaced);
      current = next;
      sortedList.add(current.node);
      unplaced.remove(current);
    }
    return sortedList;
  }
}
