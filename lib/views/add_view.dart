import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:avaca/l10n/app_localizations.dart';
import '../components/aligned_app_bar_back_button.dart';
import '../components/adaptive_page_layout.dart';
import '../components/app_scaffold.dart';
import '../controllers/add_controller.dart';
import '../core/app_appearance.dart';
import '../core/database.dart';
import '../core/layout.dart';

class AddView extends StatefulWidget {
  const AddView({super.key, required this.db});

  final AppDatabase db;

  @override
  State<AddView> createState() => _AddViewState();
}

class _AddViewState extends State<AddView> {
  late final AddController controller;
  final TextEditingController nameController = TextEditingController();

  // 初始化控制器並監聽狀態變化。
  @override
  void initState() {
    super.initState();
    controller = AddController(db: widget.db);
    controller.addListener(_handleControllerChanged);
  }

  // 移除監聽並釋放輸入框資源。
  @override
  void dispose() {
    controller.removeListener(_handleControllerChanged);
    nameController.dispose();
    super.dispose();
  }

  // 控制器狀態更新時重新建構畫面。
  void _handleControllerChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> pickImage() async {
    await controller.pickImage(context);
  }

  void removeImage() {
    controller.removeImage();
  }

  Future<void> saveActress() async {
    await controller.saveActress(context, nameController.text);
  }

  Future<void> goBack() async {
    await controller.goBack(context);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AppScaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(
          AppLocalizations.of(context).addTitle,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        leading: AlignedAppBarBackButton(onPressed: goBack),
        backgroundColor: AppSurfaces.of(
          context,
        ).clearForGlass(colorScheme.surfaceContainerHighest),
      ),
      body: SafeArea(
        child: AdaptivePageLayout(
          padding: EdgeInsets.zero,
          compactBuilder: (context, tokens) => _buildForm(tokens),
          expandedBuilder: (context, tokens) => _buildForm(tokens),
        ),
      ),
    );
  }

  Widget _buildForm(AppLayoutTokens tokens) {
    return Center(
      child: SingleChildScrollView(
        padding: tokens.pagePadding,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: tokens.formMaxWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: tokens.sectionGap,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildImageArea(tokens),
              _buildImageActionRow(tokens),
              _buildNameInput(tokens),
              _buildSaveButton(tokens),
            ],
          ),
        ),
      ),
    );
  }

  // 照片預覽區塊。
  Widget _buildImageArea(AppLayoutTokens tokens) {
    final imageState = controller.imageState;
    final hasPreview = imageState.hasImage;

    return SizedBox(
      width: 180,
      height: 180,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (!hasPreview) _buildImagePlaceholder(tokens),
          if (hasPreview) _buildImagePreview(tokens),
        ],
      ),
    );
  }

  // 已選擇照片時顯示預覽。
  Widget _buildImagePreview(AppLayoutTokens tokens) {
    final imageState = controller.imageState;
    final previewSrc = imageState.previewSrc;
    final imageBytes = _decodeDataImage(previewSrc);

    if (imageBytes == null) {
      return _buildImagePlaceholder(tokens);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(tokens.cardRadius),
      child: Image.memory(
        imageBytes,
        width: 180,
        height: 180,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      ),
    );
  }

  // 尚未選擇照片時顯示預設佔位畫面。
  Widget _buildImagePlaceholder(AppLayoutTokens tokens) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: 180,
      height: 180,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(tokens.cardRadius),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.image, size: 40, color: colorScheme.onSurfaceVariant),
          Text(
            AppLocalizations.of(context).noPhoto,
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  // 照片選擇與移除按鈕列。
  Widget _buildImageActionRow(AppLayoutTokens tokens) {
    final imageState = controller.imageState;
    final showDeleteButton = imageState.hasImage;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ElevatedButton.icon(
          onPressed: pickImage,
          icon: const Icon(Icons.image_search),
          label: Text(AppLocalizations.of(context).selectPhoto),
        ),
        if (showDeleteButton) ...[
          const SizedBox(width: 8),
          IconButton(
            tooltip: AppLocalizations.of(context).removePhoto,
            onPressed: removeImage,
            color: Theme.of(context).colorScheme.error,
            icon: const Icon(Icons.delete),
          ),
        ],
      ],
    );
  }

  // 姓名輸入欄位。
  Widget _buildNameInput(AppLayoutTokens tokens) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: tokens.isExpanded ? 480 : 300,
      child: TextField(
        controller: nameController,
        textAlign: TextAlign.center,
        decoration: InputDecoration(
          labelText: AppLocalizations.of(context).actressNameRequired,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(tokens.cardRadius),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(tokens.cardRadius),
            borderSide: BorderSide(color: colorScheme.outline),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(tokens.cardRadius),
            borderSide: BorderSide(color: colorScheme.primary),
          ),
        ),
      ),
    );
  }

  // 儲存按鈕。
  Widget _buildSaveButton(AppLayoutTokens tokens) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: tokens.isExpanded ? 260 : 200,
      child: ElevatedButton.icon(
        onPressed: saveActress,
        icon: const Icon(Icons.save),
        label: Text(AppLocalizations.of(context).saveCard),
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.secondary,
          foregroundColor: colorScheme.onSecondary,
        ),
      ),
    );
  }

  // 將 data image 字串轉成圖片 bytes。
  Uint8List? _decodeDataImage(String src) {
    if (src.isEmpty) {
      return null;
    }

    final commaIndex = src.indexOf(',');

    if (commaIndex == -1) {
      return null;
    }

    try {
      return base64Decode(src.substring(commaIndex + 1));
    } catch (_) {
      return null;
    }
  }
}
