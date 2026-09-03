import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;

class PhotoUploadService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Upload multiple photos to Firebase Storage
  /// Returns list of download URLs
  Future<List<String>> uploadPhotos(
    List<File> photos,
    String reportId, {
    Function(int, int)? onProgress,
  }) async {
    List<String> downloadUrls = [];

    for (int i = 0; i < photos.length; i++) {
      try {
        // Compress image
        final compressedFile = await _compressImage(photos[i]);

        // Create storage reference
        final fileName = '${DateTime.now().millisecondsSinceEpoch}_$i${path.extension(photos[i].path)}';
        final ref = _storage.ref().child('community_reports/$reportId/photos/$fileName');

        // Upload with progress tracking
        final uploadTask = ref.putFile(compressedFile);

        uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
          if (onProgress != null) {
            final progress = (snapshot.bytesTransferred / snapshot.totalBytes * 100).toInt();
            onProgress(i, progress);
          }
        });

        // Wait for upload to complete
        await uploadTask;

        // Get download URL
        final downloadUrl = await ref.getDownloadURL();
        downloadUrls.add(downloadUrl);

        print('✅ Uploaded photo ${i + 1}/${photos.length}');
      } catch (e) {
        print('❌ Failed to upload photo ${i + 1}: $e');
        // Continue with other photos even if one fails
      }
    }

    return downloadUrls;
  }

  /// Compress image to reduce file size
  Future<File> _compressImage(File file) async {
    try {
      // Read image
      final bytes = await file.readAsBytes();
      final image = img.decodeImage(bytes);

      if (image == null) return file;

      // Resize if too large (max 1920px width)
      img.Image resized = image;
      if (image.width > 1920) {
        resized = img.copyResize(image, width: 1920);
      }

      // Compress as JPEG with 85% quality
      final compressed = img.encodeJpg(resized, quality: 85);

      // Save to temporary file
      final tempDir = Directory.systemTemp;
      final tempFile = File('${tempDir.path}/${path.basename(file.path)}');
      await tempFile.writeAsBytes(compressed);

      print('📦 Compressed ${file.lengthSync()} bytes → ${tempFile.lengthSync()} bytes');

      return tempFile;
    } catch (e) {
      print('⚠️ Compression failed, using original: $e');
      return file;
    }
  }

  /// Delete photos from storage (cleanup on failed report submission)
  Future<void> deletePhotos(List<String> photoUrls) async {
    for (final url in photoUrls) {
      try {
        final ref = _storage.refFromURL(url);
        await ref.delete();
        print('🗑️ Deleted photo: $url');
      } catch (e) {
        print('⚠️ Failed to delete photo: $e');
      }
    }
  }

  /// Validate photo file
  bool isValidPhoto(File file) {
    final extension = path.extension(file.path).toLowerCase();
    final validExtensions = ['.jpg', '.jpeg', '.png'];

    if (!validExtensions.contains(extension)) {
      return false;
    }

    // Check file size (max 10MB)
    final fileSizeInMB = file.lengthSync() / (1024 * 1024);
    if (fileSizeInMB > 10) {
      return false;
    }

    return true;
  }
}
