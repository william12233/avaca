import 'package:flutter/material.dart';
import 'package:avaca/l10n/app_localizations.dart';
import '../components/adaptive_page_layout.dart';
import '../components/actress_card.dart';
import '../controllers/home_controller.dart';
import '../core/database.dart';
import '../core/layout.dart';

/// 首頁畫面。
///
/// 負責顯示收藏資料、搜尋列、篩選排序選單，以及導向新增、設定與詳細頁。
class HomeView extends StatefulWidget {
  const HomeView({super.key, required this.db});

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

    searchTextController.text = state.searchValue;

    setState(() {});

    if (state.isOpen) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (mounted) {
        searchFocusNode.requestFocus();
      }
    }

    if (state.refreshGallery) {
      refreshGallery();
    }
  }

  void onSearchChange(String value) {
    controller.changeSearch(value);
    refreshGallery();
  }

  Future<void> openFilterSheet() async {
    _dismissKeyboard();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => _buildFilterSheet(),
    );
  }

  Future<void> goAdd() async {
    _dismissKeyboard();
    await controller.goAdd(context);
    if (mounted) {
      refreshGallery();
    }
  }

  Future<void> goSettings() async {
    _dismissKeyboard();
    await controller.goSettings(context);
    if (mounted) {
      refreshGallery();
    }
  }

  Future<void> goDetail(int actressId) async {
    _dismissKeyboard();
    await controller.goDetail(context, actressId);
    if (mounted) {
      refreshGallery();
    }
  }

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: AdaptivePageLayout(
        padding: EdgeInsets.zero,
        compactBuilder: (context, tokens) => _buildHomeContent(tokens),
        expandedBuilder: (context, tokens) => _buildHomeContent(tokens),
      ),
    );
  }

  Widget _buildHomeContent(AppLayoutTokens tokens) {
    return Column(
      children: [
        _buildSearchBar(tokens),
        Expanded(child: _buildGalleryFuture(tokens)),
      ],
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

  Widget _buildGalleryFuture(AppLayoutTokens tokens) {
    return FutureBuilder<List<Map<String, Object?>>>(
      future: galleryFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              AppLocalizations.of(
                context,
              ).loadFailed(snapshot.error.toString()),
            ),
          );
        }

        final data = snapshot.data ?? [];

        if (data.isEmpty) {
          return Center(child: Text(AppLocalizations.of(context).noData));
        }

        return _buildGallery(data);
      },
    );
  }

  Widget _buildSearchBar(AppLayoutTokens tokens) {
    final isOpen = controller.isSearchOpen;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.decelerate,
      height: isOpen ? 55 : 0,
      margin: EdgeInsets.only(
        left: tokens.gridPadding.left + 5,
        right: tokens.gridPadding.right + 5,
        top: isOpen ? tokens.gridGap : 0,
        bottom: isOpen ? tokens.gridGap : 0,
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
        const double targetCardWidth = 120;
        const double spacing = 10;
        const double padding = 10;

        final usableWidth = constraints.maxWidth - padding * 2;
        final crossAxisCount = (usableWidth / (targetCardWidth + spacing))
            .floor()
            .clamp(3, 9);

        final itemWidth =
            (usableWidth - spacing * (crossAxisCount - 1)) / crossAxisCount;

        final childAspectRatio = _calculateCardAspectRatio(context, itemWidth);

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

  double _calculateCardAspectRatio(BuildContext context, double width) {
    const double gap = 5;
    final nameHeight = MediaQuery.textScalerOf(context).scale(16);

    final height = width + gap + nameHeight;
    return width / height;
  }

  Widget _buildFilterSheet() {
    final filterOptions = controller.getFilterOptions();
    final sortOptions = controller.getSortOptions();

    return StatefulBuilder(
      builder: (context, sheetSetState) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context).filterAndSort,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    AppLocalizations.of(context).filterSection,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  _buildOptions(
                    options: filterOptions,
                    selectedValue: controller.currentFilter,
                    labelBuilder: _filterLabel,
                    onSelected: controller.selectFilter,
                    sheetSetState: sheetSetState,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    AppLocalizations.of(context).sortSection,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  _buildOptions(
                    options: sortOptions,
                    selectedValue: controller.currentSort,
                    labelBuilder: _sortLabel,
                    onSelected: controller.changeSort,
                    sheetSetState: sheetSetState,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildOptions({
    required List<String> options,
    required String selectedValue,
    required String Function(String value) labelBuilder,
    required void Function(String value) onSelected,
    required StateSetter sheetSetState,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: options.map((text) {
        final selected = text == selectedValue;

        return ChoiceChip(
          label: Text(labelBuilder(text)),
          labelPadding: const EdgeInsets.symmetric(horizontal: 1),
          padding: const EdgeInsets.symmetric(horizontal: 2),
          visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          showCheckmark: false,
          selectedColor: colorScheme.primary,
          backgroundColor: colorScheme.surfaceContainerHighest,
          side: BorderSide(
            color: selected ? colorScheme.primary : colorScheme.outline,
          ),
          labelStyle: TextStyle(
            fontSize: 12,
            color: selected ? colorScheme.onPrimary : colorScheme.onSurface,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
          selected: selected,
          onSelected: (_) {
            onSelected(text);
            sheetSetState(() {});
            refreshGallery();
          },
        );
      }).toList(),
    );
  }

  String _sortLabel(String key) {
    final l10n = AppLocalizations.of(context);
    return switch (key) {
      'created_desc' => l10n.sortCreatedDesc,
      'created_asc' => l10n.sortCreatedAsc,
      'modified_desc' => l10n.sortModifiedDesc,
      'modified_asc' => l10n.sortModifiedAsc,
      'age_asc' => l10n.sortAgeAsc,
      'age_desc' => l10n.sortAgeDesc,
      _ => key,
    };
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
}
