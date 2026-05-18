import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:avaca/l10n/app_localizations.dart';
import '../controllers/add_controller.dart';
import '../core/database.dart';

class AddView extends StatefulWidget {
  const AddView({
    super.key,
    required this.db,
  });

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
    controller = AddController(
      db: widget.db,
    );
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
    await controller.saveActress(
      context,
      nameController.text,
    );
  }

  Future<void> goBack() async {
    await controller.goBack(context);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(
          AppLocalizations.of(context).addTitle,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: goBack,
        ),
        backgroundColor: colorScheme.surfaceContainerHighest,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              spacing: 20,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildImageArea(),
                _buildImageActionRow(),
                _buildNameInput(),
                _buildSaveButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 照片預覽區塊。
  Widget _buildImageArea() {
    final imageState = controller.imageState;
    final hasPreview = imageState['preview_visible'] == true;

    return SizedBox(
      width: 180,
      height: 180,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (!hasPreview) _buildImagePlaceholder(),
          if (hasPreview) _buildImagePreview(),
        ],
      ),
    );
  }

  // 已選擇照片時顯示預覽。
  Widget _buildImagePreview() {
    final imageState = controller.imageState;
    final previewSrc = imageState['preview_src']?.toString() ?? '';
    final imageBytes = _decodeDataImage(previewSrc);

    if (imageBytes == null) {
      return _buildImagePlaceholder();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
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
  Widget _buildImagePlaceholder() {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: 180,
      height: 180,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            Icons.image,
            size: 40,
            color: colorScheme.onSurfaceVariant,
          ),
          Text(
            AppLocalizations.of(context).noPhoto,
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  // 照片選擇與移除按鈕列。
  Widget _buildImageActionRow() {
    final imageState = controller.imageState;
    final showDeleteButton = imageState['delete_button_visible'] == true;

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
  Widget _buildNameInput() {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 300,
      child: TextField(
        controller: nameController,
        textAlign: TextAlign.center,
        decoration: InputDecoration(
          labelText: AppLocalizations.of(context).actressNameRequired,
          border: const OutlineInputBorder(),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(
              color: colorScheme.outline,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(
              color: colorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }

  // 儲存按鈕。
  Widget _buildSaveButton() {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 200,
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