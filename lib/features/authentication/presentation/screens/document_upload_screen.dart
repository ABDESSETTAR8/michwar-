import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/models/driver_model.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/driver_document_service.dart';

final _driverDocumentServiceProvider = Provider<DriverDocumentService>(
  (ref) => DriverDocumentService(
    firestore: ref.watch(firestoreProvider),
  ),
);

/// "Document Upload (Driver Only)" portal (Section 4 — Algeria-Specific
/// Compliance). Drivers must submit all 5 required documents before their
/// account is activated by an admin.
class DocumentUploadScreen extends ConsumerStatefulWidget {
  const DocumentUploadScreen({super.key});

  @override
  ConsumerState<DocumentUploadScreen> createState() =>
      _DocumentUploadScreenState();
}

class _DocumentUploadScreenState extends ConsumerState<DocumentUploadScreen> {
  final Set<String> _uploading = {};

  Future<void> _pickAndUpload(String type) async {
    final uid = ref.read(authStateProvider).value;
    if (uid == null) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (picked == null) return;

    setState(() => _uploading.add(type));
    try {
      await ref.read(_driverDocumentServiceProvider).uploadDocument(
            uid: uid,
            type: type,
            file: File(picked.path),
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading.remove(type));
    }
  }

  @override
  Widget build(BuildContext context) {
    final driver = ref.watch(driverProfileProvider).value;
    final documentsMeta = driver?.documentsMeta ?? const {};
    final status = driver?.verificationStatus;

    final allUploaded = AppConstants.requiredDriverDocuments
        .every((type) => documentsMeta.containsKey(type));

    return Scaffold(
      appBar: AppBar(title: const Text('Driver verification')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            color: AppColors.primary.withOpacity(0.06),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.verified_user_rounded, color: AppColors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _statusMessage(status, allUploaded),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Upload clear photos of the following documents. Our team '
            'reviews submissions within 24-48 hours.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          ...AppConstants.requiredDriverDocuments.map((type) {
            final docMeta = documentsMeta[type] as Map?;
            final docStatus = docMeta?['status'] as String?;
            final label = AppConstants.driverDocumentLabels[type]!;
            final uploading = _uploading.contains(type);
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: _statusIcon(docStatus, uploading),
                title: Text(label),
                subtitle: Text(_docSubtitle(docStatus)),
                trailing: TextButton(
                  onPressed: uploading ? null : () => _pickAndUpload(type),
                  child: Text(docMeta == null ? 'Upload' : 'Replace'),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  String _statusMessage(DriverVerificationStatus? status, bool allUploaded) {
    switch (status) {
      case DriverVerificationStatus.underReview:
        return 'Your documents are under review by our compliance team.';
      case DriverVerificationStatus.approved:
        return 'You are verified and ready to accept rides!';
      case DriverVerificationStatus.rejected:
        return 'Some documents were rejected. Please re-upload them.';
      default:
        return allUploaded
            ? 'All documents submitted — finalizing review…'
            : 'Submit all 5 documents to activate your driver account.';
    }
  }

  String _docSubtitle(String? status) {
    switch (status) {
      case 'approved':
        return 'Approved';
      case 'rejected':
        return 'Rejected — please re-upload';
      case 'pending':
        return 'Pending review';
      default:
        return 'Not uploaded';
    }
  }

  Widget _statusIcon(String? status, bool uploading) {
    if (uploading) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    switch (status) {
      case 'approved':
        return const Icon(Icons.check_circle, color: AppColors.success);
      case 'rejected':
        return const Icon(Icons.error, color: AppColors.danger);
      case 'pending':
        return const Icon(Icons.hourglass_top, color: AppColors.warning);
      default:
        return const Icon(Icons.upload_file, color: AppColors.textSecondary);
    }
  }
}
