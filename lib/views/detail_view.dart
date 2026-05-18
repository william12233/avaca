import 'dart:io';
import 'package:flutter/material.dart';
import 'package:avaca/l10n/app_localizations.dart';
import '../controllers/detail_controller.dart';
import '../core/database.dart';

class DetailView extends StatefulWidget {
  const DetailView({
    super.key,
    required this.db,
    required this.actressId,
  });

  final AppDatabase db;
  final int actressId;

  @override
  State<DetailView> createState() => _DetailViewState();
}

class _DetailViewState extends State<DetailView> {
  late final DetailController controller;
  late final Future<void> initFuture;

  final TextEditingController nameController = TextEditingController();
  final TextEditingController heightController = TextEditingController();
  final TextEditingController weightController = TextEditingController();
  final TextEditingController cupController = TextEditingController();
  final TextEditingController bwhController = TextEditingController();
  final TextEditingController memoController = TextEditingController();

  final Set<String> selectedAttrs = <String>{};

  @override
  void initState() {
    super.initState();

    controller = DetailController(
      db: widget.db,
      actressId: widget.actressId,
    );
    controller.addListener(_handleControllerChanged);

    initFuture = _initialize();
  }

  @override
  void dispose() {
    controller.removeListener(_handleControllerChanged);

    nameController.dispose();
    heightController.dispose();
    weightController.dispose();
    cupController.dispose();
    bwhController.dispose();
    memoController.dispose();

    super.dispose();
  }

  Future<void> _initialize() async {
    await controller.init();
    _syncFieldsFromController();
  }

  void _handleControllerChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _syncFieldsFromController() {
    final data = controller.actressData;

    nameController.text = data['name']?.toString() ?? '';
    heightController.text = data['height']?.toString() ?? '';
    weightController.text = data['weight']?.toString() ?? '';
    cupController.text = data['cup']?.toString() ?? '';
    bwhController.text = data['bwh']?.toString() ?? '';
    memoController.text = data['memo']?.toString() ?? '';

    selectedAttrs
      ..clear()
      ..addAll(controller.currentAttrs);
  }

  Future<void> _toggleEditMode() async {
    final editState = await controller.toggleEditMode(
      context,
      _getFormData(),
    );

    selectedAttrs
      ..clear()
      ..addAll(
        (editState['current_attrs'] as List<dynamic>? ?? [])
            .map((e) => e.toString()),
      );

    if (!controller.isEditing) {
      _syncFieldsFromController();
    }
  }

  Map<String, Object?> _getFormData() {
    return {
      'name': nameController.text,
      'img_path': controller.actressData['img_path']?.toString() ?? '',
      'main_type': selectedAttrs.join(','),
      'selected_attrs': selectedAttrs.toList(),
      'memo': memoController.text,
      'height': heightController.text,
      'weight': weightController.text,
      'bwh': bwhController.text,
      'cup': cupController.text,
    };
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return FutureBuilder<void>(
      future: initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return Scaffold(
          backgroundColor: colorScheme.surface,
          appBar: AppBar(
            centerTitle: true,
            backgroundColor: colorScheme.surfaceContainerHighest,
            title: _buildAppBarTitle(),
            actions: [
              IconButton(
                icon: Icon(
                  controller.isEditing ? Icons.save : Icons.edit,
                ),
                onPressed: _toggleEditMode,
              ),
              if (!controller.isEditing)
                IconButton(
                  icon: const Icon(Icons.delete_forever),
                  color: colorScheme.error,
                  onPressed: _openDeleteDialog,
                ),
            ],
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 800;

                  if (isWide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 4, child: _buildProfilePanel()),
                        const SizedBox(width: 16),
                        Expanded(flex: 8, child: _buildInfoPanel()),
                      ],
                    );
                  }

                  return Column(
                    children: [
                      _buildProfilePanel(),
                      const SizedBox(height: 16),
                      _buildInfoPanel(),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAppBarTitle() {
    if (controller.isEditing) {
      return TextField(
        controller: nameController,
        textAlign: TextAlign.center,
        decoration: const InputDecoration(border: InputBorder.none),
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      );
    }

    return Text(
      controller.actressData['name']?.toString() ??
          AppLocalizations.of(context).dataNotFound,
      style: const TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  // 顯示個人照片、照片操作與屬性內容。
  Widget _buildProfilePanel() {
    final colorScheme = Theme.of(context).colorScheme;
    final isEditing = controller.isEditing;

    return Container(
      padding: isEditing ? const EdgeInsets.all(20) : EdgeInsets.zero,
      decoration: isEditing
          ? BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildProfileImage(),
          if (isEditing) ...[
            const SizedBox(height: 12),
            _buildPhotoEditRow(),
          ],
          const SizedBox(height: 16),
          isEditing ? _buildAttrEditRow() : _buildAttrViewRow(),
        ],
      ),
    );
  }

  Widget _buildProfileImage() {
    final imgPath = controller.actressData['img_path']?.toString() ?? '';
    final colorScheme = Theme.of(context).colorScheme;

    if (imgPath.isEmpty) {
      return Container(
        width: 220,
        height: 220,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Icon(
          Icons.person,
          size: 80,
          color: colorScheme.onSurfaceVariant,
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Image.file(
        File(imgPath),
        width: 220,
        height: 220,
        fit: BoxFit.cover,
      ),
    );
  }

  Widget _buildPhotoEditRow() {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ElevatedButton.icon(
          onPressed: () => controller.changePhoto(context),
          icon: const Icon(Icons.add_a_photo),
          label: Text(AppLocalizations.of(context).changePhoto),
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          onPressed: controller.deletePhoto,
          icon: Icon(
            Icons.delete,
            color: colorScheme.error,
          ),
          label: Text(AppLocalizations.of(context).deletePhoto),
        ),
      ],
    );
  }

  Widget _buildAttrViewRow() {
    final colorScheme = Theme.of(context).colorScheme;

    if (controller.currentAttrs.isEmpty) {
      return Text(
        AppLocalizations.of(context).noAttributesSet,
        style: TextStyle(
          fontSize: 13,
          color: colorScheme.outline,
        ),
      );
    }

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 14,
      runSpacing: 6,
      children: controller.currentAttrs.map((attr) {
        return Text(
          attr,
          style: TextStyle(
            fontSize: 13,
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildAttrEditRow() {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 4,
      children: controller.getAttrOptions(context).map((option) {
        return FilterChip(
          label: Text(option),
          selected: selectedAttrs.contains(option),
          onSelected: (selected) {
            setState(() {
              selected
                  ? selectedAttrs.add(option)
                  : selectedAttrs.remove(option);
            });
          },
        );
      }).toList(),
    );
  }

  // 顯示身體資料與私人筆記。
  Widget _buildInfoPanel() {
    return Column(
      children: [
        _buildCard(
          title: AppLocalizations.of(context).bodyInfo,
          child: Column(
            children: [
              _buildStatField(
                label: AppLocalizations.of(context).heightCm,
                controller: heightController,
              ),
              const SizedBox(height: 6),
              _buildStatField(
                label: AppLocalizations.of(context).weightKg,
                controller: weightController,
              ),
              const SizedBox(height: 6),
              _buildStatField(
                label: AppLocalizations.of(context).cup,
                controller: cupController,
              ),
              const SizedBox(height: 6),
              _buildStatField(
                label: AppLocalizations.of(context).measurements,
                controller: bwhController,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildCard(
          title: AppLocalizations.of(context).privateNotes,
          child: controller.isEditing
              ? TextField(
                  controller: memoController,
                  minLines: 5,
                  maxLines: 10,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                )
              : Text(
                  memoController.text.isEmpty
                      ? AppLocalizations.of(context).noNotes
                      : memoController.text,
                  style: const TextStyle(fontSize: 14),
                ),
        ),
      ],
    );
  }

  Widget _buildStatField({
    required String label,
    required TextEditingController controller,
  }) {
    final isEditing = this.controller.isEditing;
    final colorScheme = Theme.of(context).colorScheme;

    if (!isEditing) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 90,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Text(
              controller.text.isEmpty ? '—' : controller.text,
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
      );
    }

    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        border: const UnderlineInputBorder(),
      ),
    );
  }

  Widget _buildCard({
    required String title,
    required Widget child,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  // 開啟刪除確認視窗，實際刪除流程交給 controller 處理。
  Future<void> _openDeleteDialog() async {
    final dialogState = controller.openDeleteDialog();

    if (dialogState['open'] != true) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(AppLocalizations.of(context).confirmDeleteTitle),
          content: Text(AppLocalizations.of(context).deleteWarningWithPhoto),
          actions: [
            TextButton(
              onPressed: () {
                controller.closeDeleteDialog();
                Navigator.of(dialogContext).pop();
              },
              child: Text(AppLocalizations.of(context).cancel),
            ),
            TextButton(
              onPressed: () async {
                controller.closeDeleteDialog();
                Navigator.of(dialogContext).pop();
                await controller.executeDelete(context);
              },
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: Text(AppLocalizations.of(context).confirmDelete),
            ),
          ],
        );
      },
    );
  }
}