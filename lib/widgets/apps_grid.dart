/*
 * FLauncher
 * Copyright (C) 2021  Étienne Fesser
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import 'dart:math';

import 'package:flauncher/database.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/widgets/app_card.dart';
import 'package:flauncher/widgets/ensure_visible.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

class AppsGrid extends StatefulWidget {
  final Category category;
  final List<App> applications;

  static const _crossAxisCount = 6;

  AppsGrid({
    Key? key,
    required this.category,
    required this.applications,
  }) : super(key: key);

  @override
  State<AppsGrid> createState() => _AppsGridState();
}

class _AppsGridState extends State<AppsGrid> {
  late final FocusNode _focusNode;
  int? _currentRow;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
        canRequestFocus: false,
        focusNode: _focusNode,
        child: FocusScope(
          onKey: (node, event) {
            if (event is RawKeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowUp && _currentRow == 0) {
              _focusNode.focusInDirection(TraversalDirection.up);
              return KeyEventResult.handled;
            }
            final totalRows = ((widget.applications.length - 1) / AppsGrid._crossAxisCount).floor();
            if (event is RawKeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.arrowDown &&
                _currentRow == totalRows) {
              _focusNode.focusInDirection(TraversalDirection.down);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(left: 16),
                child: Text(
                  "Applications",
                  style: Theme.of(context)
                      .textTheme
                      .headline6!
                      .copyWith(shadows: [Shadow(color: Colors.black54, offset: Offset(1, 1), blurRadius: 8)]),
                ),
              ),
              GridView.custom(
                shrinkWrap: true,
                primary: false,
                gridDelegate: _buildSliverGridDelegate(),
                padding: EdgeInsets.all(16),
                childrenDelegate: SliverChildBuilderDelegate(
                  (context, index) => EnsureVisible(
                    key: Key("${widget.category.id}-${widget.applications[index].packageName}"),
                    alignment: 0.5,
                    child: Focus(
                      canRequestFocus: false,
                      onFocusChange: (focused) {
                        if (focused) {
                          _currentRow = (index / AppsGrid._crossAxisCount).floor();
                        }
                      },
                      child: AppCard(
                        category: widget.category,
                        application: widget.applications[index],
                        autofocus: index == 0,
                        onMove: (direction) => _onMove(context, direction, index),
                        onMoveEnd: () => _saveOrder(context),
                      ),
                    ),
                  ),
                  childCount: widget.applications.length,
                  findChildIndexCallback: _findChildIndex,
                ),
              ),
            ],
          ),
        ),
      );

  int _findChildIndex(Key key) => widget.applications
      .indexWhere((app) => "${widget.category.id}-${app.packageName}" == (key as ValueKey<String>).value);

  void _onMove(BuildContext context, AxisDirection direction, int index) {
    final currentRow = (index / AppsGrid._crossAxisCount).floor();
    final totalRows = ((widget.applications.length - 1) / AppsGrid._crossAxisCount).floor();

    int? newIndex;
    switch (direction) {
      case AxisDirection.up:
        if (currentRow > 0) {
          newIndex = index - AppsGrid._crossAxisCount;
        }
        break;
      case AxisDirection.right:
        if (index < widget.applications.length - 1) {
          newIndex = index + 1;
        }
        break;
      case AxisDirection.down:
        if (currentRow < totalRows) {
          newIndex = min(index + AppsGrid._crossAxisCount, widget.applications.length - 1);
        }
        break;
      case AxisDirection.left:
        if (index > 0) {
          newIndex = index - 1;
        }
        break;
    }
    if (newIndex != null) {
      final appsService = context.read<AppsService>();
      appsService.reorderApplication(widget.category, index, newIndex);
    }
  }

  void _saveOrder(BuildContext context) {
    final appsService = context.read<AppsService>();
    appsService.saveOrderInCategory(widget.category);
  }

  SliverGridDelegate _buildSliverGridDelegate() => SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: AppsGrid._crossAxisCount,
        childAspectRatio: 16 / 9,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
      );
}
