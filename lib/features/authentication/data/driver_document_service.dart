import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../../core/constants/firestore_paths.dart';

/// Handles the "Driver Verification Workflow": uploads compliance documents
/// to Firebase Storage under `driver_docs/{uid}/{type}{ext}` and records
/// per-document metadata in `drivers/{driverId}.documentsMeta`.
///
/// Once every required document has an entry in `documentsMeta`, the Cloud
/// Function trigger automatically flips `verificationStatus` from `pending`
/// to `under_review`. From there an admin reviews each document and flips
/// `verificationStatus` to `approved` / `rejected`, unlocking the driver
/// home screen (enforced client-side by the router redirect).
class DriverDocumentService {
  DriverDocumentService({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  })  : _fs = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _fs;
  final FirebaseStorage _storage;

  /// Uploads [file] for document [type] (e.g. `"id_front"`, `"license"`)
  /// and records its metadata inside the driver's Firestore document.
  Future<void> uploadDocument({
    required String uid,
    required String type,
    required File file,
  }) async {
    // 1. Find the driver's Firestore document by userId field.
    final snap = await _fs
        .collection(FsCollections.drivers)
        .where('userId', isEqualTo: uid)
        .limit(1)
        .get();

    if (snap.docs.isEmpty) {
      throw StateError('No driver profile found for user $uid');
    }

    final driverDoc = snap.docs.first;

    // 2. Upload to Firebase Storage: driver_docs/{uid}/{type}{ext}
    final ext = file.path.contains('.')
        ? file.path.substring(file.path.lastIndexOf('.'))
        : '.jpg';
    final storageRef = _storage.ref('driver_docs/$uid/$type$ext');
    final uploadTask = await storageRef.putFile(file);
    final downloadUrl = await uploadTask.ref.getDownloadURL();

    // 3. Update documentsMeta map in the driver's Firestore doc.
    final existingMeta = Map<String, dynamic>.from(
      (driverDoc.data()['documentsMeta'] as Map?) ?? const {},
    );
    existingMeta[type] = {
      'url': downloadUrl,
      'storagePath': storageRef.fullPath,
      'status': 'pending',
      'uploadedAt': FieldValue.serverTimestamp(),
    };

    await _fs
        .collection(FsCollections.drivers)
        .doc(driverDoc.id)
        .update({'documentsMeta': existingMeta});
  }

  /// Deletes a previously uploaded document from Storage and clears its
  /// metadata entry from Firestore.
  Future<void> deleteDocument({
    required String uid,
    required String type,
  }) async {
    final snap = await _fs
        .collection(FsCollections.drivers)
        .where('userId', isEqualTo: uid)
        .limit(1)
        .get();

    if (snap.docs.isEmpty) return;

    final driverDoc = snap.docs.first;
    final meta = Map<String, dynamic>.from(
      (driverDoc.data()['documentsMeta'] as Map?) ?? const {},
    );

    final docMeta = meta[type] as Map?;
    if (docMeta != null) {
      final storagePath = docMeta['storagePath'] as String?;
      if (storagePath != null && storagePath.isNotEmpty) {
        try {
          await _storage.ref(storagePath).delete();
        } catch (_) {
          // File may already be gone — non-fatal.
        }
      }
    }

    meta.remove(type);
    await _fs
        .collection(FsCollections.drivers)
        .doc(driverDoc.id)
        .update({'documentsMeta': meta});
  }
}
