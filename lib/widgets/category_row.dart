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

import 'package:flauncher/database.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/widgets/app_card.dart';
import 'package:flauncher/widgets/categories_dialog.dart';
import 'package:flauncher/widgets/ensure_visible.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

class CategoryRow extends StatefulWidget {
  final Category category;
  final List<App> applications;

  CategoryRow({
    Key? key,
    required this.category,
    required this.applications,
  }) : super(key: key);

  @override
  State<CategoryRow> createState() => _CategoryRowState();
}

class _CategoryRowState extends State<CategoryRow> {
  late final FocusNode _focusNode;

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
            if (event is RawKeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowUp) {
              _focusNode.focusInDirection(TraversalDirection.up);
              return KeyEventResult.handled;
            }
            if (event is RawKeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowDown) {
              _focusNode.focusInDirection(TraversalDirection.down);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(left: 16, bottom: 8),
                child: Text(widget.category.name,
                    style: Theme.of(context)
                        .textTheme
                        .headline6!
                        .copyWith(shadows: [Shadow(color: Colors.black54, offset: Offset(1, 1), blurRadius: 8)])),
              ),
              SizedBox(
                height: 110,
                child: widget.applications.isNotEmpty
                    ? ListView.custom(
                        padding: EdgeInsets.all(8),
                        scrollDirection: Axis.horizontal,
                        childrenDelegate: SliverChildBuilderDelegate(
                          (context, index) => EnsureVisible(
                            key: Key("${widget.category.id}-${widget.applications[index].packageName}"),
                            alignment: 0.1,
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8),
                              child: AppCard(
                                category: widget.category,
                                application: widget.applications[index],
                                autofocus: index == 0,
                                onMove: (direction) => _onMove(context, direction, index),
                                onMoveEnd: () => _onMoveEnd(context),
                              ),
                            ),
                          ),
                          childCount: widget.applications.length,
                          findChildIndexCallback: _findChildIndex,
                        ),
                      )
                    : _emptyState(context),
              ),
            ],
          ),
        ),
      );

  int _findChildIndex(Key key) => widget.applications
      .indexWhere((app) => "${widget.category.id}-${app.packageName}" == (key as ValueKey<String>).value);

  Widget _emptyState(BuildContext context) => EnsureVisible(
        alignment: 0.1,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Card(
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                child: InkWell(
                  onTap: () => showDialog(context: context, builder: (_) => CategoriesDialog()),
                  child: Padding(
                    padding: EdgeInsets.all(8),
                    child: Center(
                      child: Text(
                        "This category is empty.\nLong-press an app to move it here.",
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  void _onMove(BuildContext context, AxisDirection direction, int index) {
    int? newIndex;
    switch (direction) {
      case AxisDirection.right:
        if (index < widget.applications.length - 1) {
          newIndex = index + 1;
        }
        break;
      case AxisDirection.left:
        if (index > 0) {
          newIndex = index - 1;
        }
        break;
      default:
        break;
    }
    if (newIndex != null) {
      final appsService = context.read<AppsService>();
      appsService.reorderApplication(widget.category, index, newIndex);
    }
  }

  void _onMoveEnd(BuildContext context) {
    final appsService = context.read<AppsService>();
    appsService.saveOrderInCategory(widget.category);
  }
}
