import 'package:flutter/material.dart';
import 'package:avaca/l10n/app_localizations.dart';
import '../components/actress_card.dart';
import '../controllers/home_controller.dart';
import '../core/database.dart';

/// 首頁畫面。
///
/// 負責顯示收藏資料、搜尋列、篩選排序選單，以及導向新增、設定與詳細頁。
class HomeView extends StatefulWidget {
  const HomeView({
    super.key,
    required this.db,
  });

  final AppDatabase db;

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  late final HomeController controller;
  late Future<List<Map<String, Object?>>> galleryFuture;

  final TextEditingController searchTextController = TextEditingController();
  final FocusNode searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    controller = HomeController(db: widget.db);
    galleryFuture = controller.getGalleryData();
  }

  @override
  void dispose() {
    searchTextController.dispose();
    searchFocusNode.dispose();
    super.dispose();
  }

  void refreshGallery() {
    setState(() {
      galleryFuture = controller.getGalleryData();
    });
  }

  Future<void> toggleSearch() async {
    final state = controller.toggleSearch();

    searchTextController.text = state['search_value']?.toString() ?? '';

    setState(() {});

    if (state['is_open'] == true) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (mounted) {
        searchFocusNode.requestFocus();
      }
    }

    if (state['refresh_gallery'] == true) {
      refreshGallery();
    }
  }

  void onSearchChange(String value) {
    controller.changeSearch(value);
    refreshGallery();
  }

  Future<void> openFilterSheet() async {
    final state = controller.openFilterSheet();
    if (state['open'] != true) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => _buildFilterSheet(),
    );
  }

  Future<void> goAdd() async {
    await controller.goAdd(context);
    if (mounted) {
      refreshGallery();
    }
  }

  Future<void> goSettings() async {
    await controller.goSettings(context);
    if (mounted) {
      refreshGallery();
    }
  }

  Future<void> goDetail(int actressId) async {
    await controller.goDetail(context, actressId);
    if (mounted) {
      refreshGallery();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: _buildGalleryFuture(),
          ),
        ],
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      title: Text(AppLocalizations.of(context).appTitle),
      actions: [
        IconButton(
          tooltip: AppLocalizations.of(context).search,
          icon: const Icon(Icons.search),
          onPressed: toggleSearch,
        ),
        IconButton(
          tooltip: AppLocalizations.of(context).filterAndSort,
          icon: const Icon(Icons.tune),
          onPressed: openFilterSheet,
        ),
        IconButton(
          tooltip: AppLocalizations.of(context).add,
          icon: const Icon(Icons.add),
          onPressed: goAdd,
        ),
        IconButton(
          tooltip: AppLocalizations.of(context).settings,
          icon: const Icon(Icons.settings),
          onPressed: goSettings,
        ),
      ],
    );
  }

  Widget _buildGalleryFuture() {
    return FutureBuilder<List<Map<String, Object?>>>(
      future: galleryFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              AppLocalizations.of(context).loadFailed(
                snapshot.error.toString(),
              ),
            ),
          );
        }

        final data = snapshot.data ?? [];

        if (data.isEmpty) {
          return Center(
            child: Text(AppLocalizations.of(context).noData),
          );
        }

        return _buildGallery(data);
      },
    );
  }

  Widget _buildSearchBar() {
    final isOpen = controller.isSearchOpen;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.decelerate,
      height: isOpen ? 55 : 0,
      margin: EdgeInsets.only(
        left: 15,
        right: 15,
        top: isOpen ? 10 : 0,
        bottom: isOpen ? 10 : 0,
      ),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(30),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: () {
            searchFocusNode.requestFocus();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Icon(Icons.search),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: searchTextController,
                    focusNode: searchFocusNode,
                    decoration: InputDecoration(
                      hintText: AppLocalizations.of(context).searchNameHint,
                      isDense: true,
                      filled: false,
                      fillColor: Colors.transparent,
                      hoverColor: Colors.transparent,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                    ),
                    onChanged: onSearchChange,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGallery(List<Map<String, Object?>> actressData) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const double targetCardWidth = 180;
        const double spacing = 10;
        const double padding = 10;

        final usableWidth = constraints.maxWidth - padding * 2;
        final crossAxisCount = (usableWidth / (targetCardWidth + spacing))
            .floor()
            .clamp(2, 6);

        final itemWidth =
            (usableWidth - spacing * (crossAxisCount - 1)) / crossAxisCount;

        final childAspectRatio = _calculateCardAspectRatio(itemWidth);

        return GridView.builder(
          padding: const EdgeInsets.all(padding),
          itemCount: actressData.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            childAspectRatio: childAspectRatio,
          ),
          itemBuilder: (context, index) {
            final item = actressData[index];
            final actressId = _readActressId(item);

            return ActressCard(
              name: item['name']?.toString() ?? '',
              imgPath: item['img_path']?.toString(),
              onTap: () => goDetail(actressId),
            );
          },
        );
      },
    );
  }

  int _readActressId(Map<String, Object?> item) {
    final id = item['id'];
    return id is int ? id : int.tryParse(id.toString()) ?? 0;
  }

  double _calculateCardAspectRatio(double width) {
    const double verticalPadding = 20;
    const double gap = 5;
    const double nameHeight = 22;

    final height = width + verticalPadding + gap + nameHeight;
    return width / height;
  }

  Widget _buildFilterSheet() {
    final options = controller.getFilterOptions();

    return StatefulBuilder(
      builder: (context, sheetSetState) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(25),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context).filterAndSort,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                _buildFilterOptions(
                  options: options,
                  sheetSetState: sheetSetState,
                ),
                const SizedBox(height: 20),
                _buildApplyFilterButton(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFilterOptions({
    required List<String> options,
    required StateSetter sheetSetState,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((text) {
        final selected = text == controller.currentFilter;

        return ChoiceChip(
          label: Text(_filterLabel(text)),
          selected: selected,
          onSelected: (_) {
            controller.selectFilter(text);
            // 更新篩選選單內部畫面，讓目前選取的項目立即反映在畫面上。
            sheetSetState(() {});
          },
        );
      }).toList(),
    );
  }

  String _filterLabel(String key) {
    final l10n = AppLocalizations.of(context);

    return switch (key) {
      'all' => l10n.filterAll,
      'censored' => l10n.attrCensored,
      'uncensored' => l10n.attrUncensored,
      'western' => l10n.attrWestern,
      'fc2' => l10n.attrFc2,
      'domestic' => l10n.attrDomestic,
      _ => key,
    };
  }

  Widget _buildApplyFilterButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () {
          controller.applyFilterSheet();
          Navigator.of(context).pop();
          refreshGallery();
        },
        child: Text(AppLocalizations.of(context).applySettings),
      ),
    );
  }
}