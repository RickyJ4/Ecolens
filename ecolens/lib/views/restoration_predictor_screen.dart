import 'package:ecolens/core/theme.dart';
import 'package:ecolens/services/photo_upload_service.dart';
import 'package:ecolens/viewmodels/restoration_viewmodel.dart';
import 'package:ecolens/views/premium_ar_screen.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'dart:io';

/// Restoration Success Predictor Screen
/// Analyzes degraded land photos to predict restoration potential
class RestorationPredictorScreen extends StatefulWidget {
  const RestorationPredictorScreen({super.key});

  @override
  State<RestorationPredictorScreen> createState() =>
      _RestorationPredictorScreenState();
}

class _RestorationPredictorScreenState
    extends State<RestorationPredictorScreen> {
  final ImagePicker _picker = ImagePicker();
  final PhotoUploadService _uploadService = PhotoUploadService();
  XFile? _selectedPhoto;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<RestorationViewModel>(
        context,
        listen: false,
      ).getCurrentLocation();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EcoTheme.background,
      appBar: AppBar(
        backgroundColor: EcoTheme.background,
        elevation: 0,
        title: Text(
          "Restoration Predictor",
          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.view_in_ar),
            tooltip: "AR Preview",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const PremiumARScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              Provider.of<RestorationViewModel>(context, listen: false).reset();
              setState(() {
                _selectedPhoto = null;
              });
            },
          ),
        ],
      ),
      body: Consumer<RestorationViewModel>(
        builder: (context, vm, child) {
          if (vm.hasResult) {
            return _buildResultsView(vm);
          }
          return _buildUploadView(vm);
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // Upload View
  // ═══════════════════════════════════════════════════════════════

  Widget _buildUploadView(RestorationViewModel vm) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          _buildHeader(),

          const SizedBox(height: 24),

          // Photo Capture Section
          _buildPhotoSection(vm),

          const SizedBox(height: 24),

          // Location Status
          _buildLocationStatus(vm),

          const SizedBox(height: 24),

          // Analyze Button
          _buildAnalyzeButton(vm),

          // Error Display
          if (vm.error != null) ...[
            const SizedBox(height: 16),
            _buildErrorCard(vm.error!),
          ],

          // Instructions
          const SizedBox(height: 32),
          _buildInstructions(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [EcoTheme.forestGreen, EcoTheme.cyan],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.eco, size: 40, color: Colors.white),
          const SizedBox(height: 12),
          Text(
            'Predict Restoration Success',
            style: GoogleFonts.inter(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Upload a photo of degraded land to get AI-powered restoration recommendations and success probability.',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoSection(RestorationViewModel vm) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: EcoTheme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          if (_selectedPhoto != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(_selectedPhoto!.path),
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 16),
          ] else ...[
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: EcoTheme.cyan.withOpacity(0.3),
                  width: 2,
                ),
              ),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.photo_camera, size: 64, color: Colors.white24),
                    SizedBox(height: 8),
                    Text(
                      'No Photo Selected',
                      style: TextStyle(color: Colors.white38),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isUploading || vm.isAnalyzing
                      ? null
                      : () => _capturePhoto(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Take Photo'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: EcoTheme.forestGreen,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isUploading || vm.isAnalyzing
                      ? null
                      : () => _capturePhoto(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Gallery'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: EcoTheme.cyan,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),

          if (_isUploading) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(color: EcoTheme.cyan),
            const SizedBox(height: 8),
            const Text(
              'Uploading photo...',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLocationStatus(RestorationViewModel vm) {
    final hasLocation = vm.currentLocation != null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: hasLocation
            ? EcoTheme.forestGreen.withOpacity(0.2)
            : Colors.orange.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasLocation ? EcoTheme.forestGreen : Colors.orange,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            hasLocation ? Icons.location_on : Icons.location_off,
            color: hasLocation ? EcoTheme.forestGreen : Colors.orange,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasLocation ? 'Location Acquired' : 'Getting Location...',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                if (hasLocation)
                  Text(
                    'Lat: ${vm.currentLocation!.latitude.toStringAsFixed(4)}, '
                    'Lng: ${vm.currentLocation!.longitude.toStringAsFixed(4)}',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyzeButton(RestorationViewModel vm) {
    final canAnalyze =
        _selectedPhoto != null &&
        vm.currentLocation != null &&
        vm.photoUrl != null;

    return ElevatedButton(
      onPressed: canAnalyze && !vm.isAnalyzing
          ? () => vm.analyzeRestoration()
          : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: EcoTheme.cyan,
        foregroundColor: Colors.black,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: vm.isAnalyzing
          ? const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.black),
                  ),
                ),
                SizedBox(width: 12),
                Text('Analyzing...'),
              ],
            )
          : const Text(
              'Analyze Restoration Potential',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
    );
  }

  Widget _buildInstructions() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: EcoTheme.cardColor.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.lightbulb_outline,
                color: EcoTheme.cyan,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Tips for Best Results',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildTipItem('Capture photos during daylight'),
          _buildTipItem('Include surrounding vegetation'),
          _buildTipItem('Show soil condition clearly'),
          _buildTipItem('Take photo at the actual site'),
        ],
      ),
    );
  }

  Widget _buildTipItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: EcoTheme.forestGreen, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // Results View
  // ═══════════════════════════════════════════════════════════════

  Widget _buildResultsView(RestorationViewModel vm) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Success Probability Card
          _buildSuccessProbabilityCard(vm),

          const SizedBox(height: 16),

          // Current Conditions
          _buildCurrentConditionsCard(vm),

          const SizedBox(height: 16),

          // Recommendations
          _buildRecommendationsCard(vm),

          const SizedBox(height: 16),

          // Carbon Potential
          _buildCarbonPotentialCard(vm),

          const SizedBox(height: 16),

          // Cost Estimate
          _buildCostEstimateCard(vm),

          const SizedBox(height: 16),

          // Similar Projects
          if (vm.similarProjects.isNotEmpty) _buildSimilarProjectsCard(vm),
        ],
      ),
    );
  }

  Widget _buildSuccessProbabilityCard(RestorationViewModel vm) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            vm.successColor.withOpacity(0.3),
            vm.successColor.withOpacity(0.1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: vm.successColor, width: 2),
      ),
      child: Column(
        children: [
          Text(
            'Success Probability',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '${vm.successProbability.toStringAsFixed(1)}%',
            style: GoogleFonts.inter(
              fontSize: 48,
              fontWeight: FontWeight.bold,
              color: vm.successColor,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: vm.successColor,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${vm.successLevel} Confidence',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentConditionsCard(RestorationViewModel vm) {
    final conditions = vm.currentConditions;
    return _buildInfoCard('Current Conditions', Icons.analytics, [
      _buildInfoRow('NDVI', conditions['ndvi']?.toString() ?? 'N/A'),
      _buildInfoRow('Soil Quality', conditions['soil_quality'] ?? 'Unknown'),
      _buildInfoRow(
        'Degradation',
        conditions['degradation_level'] ?? 'Unknown',
      ),
    ]);
  }

  Widget _buildRecommendationsCard(RestorationViewModel vm) {
    final recommendations = vm.recommendations;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: EcoTheme.cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.recommend, color: EcoTheme.cyan),
              const SizedBox(width: 8),
              Text(
                'Recommendations',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...recommendations.map((rec) => _buildRecommendationItem(rec)),
        ],
      ),
    );
  }

  Widget _buildRecommendationItem(Map<String, dynamic> rec) {
    final priority = rec['priority'] as String? ?? 'medium';
    final color = priority == 'high'
        ? Colors.red
        : priority == 'medium'
        ? Colors.orange
        : Colors.yellow;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        border: Border.all(color: color.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  priority.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  rec['action'] ?? '',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            rec['rationale'] ?? '',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          if (rec['estimated_cost_usd'] != null) ...[
            const SizedBox(height: 8),
            Text(
              'Cost: \$${rec['estimated_cost_usd']}',
              style: const TextStyle(color: EcoTheme.cyan, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCarbonPotentialCard(RestorationViewModel vm) {
    final carbon = vm.carbonPotential;
    return _buildInfoCard('Carbon Potential (20 years)', Icons.eco, [
      _buildInfoRow(
        'Annual Sequestration',
        '${carbon['annual_sequestration_tons_co2']} tons CO₂',
      ),
      _buildInfoRow(
        'Total (20 years)',
        '${carbon['carbon_20yr_tons']} tons CO₂',
      ),
      _buildInfoRow(
        'Market Value',
        '\$${carbon['market_value_20yr_usd']}',
        valueColor: EcoTheme.cyan,
      ),
    ]);
  }

  Widget _buildCostEstimateCard(RestorationViewModel vm) {
    final cost = vm.costEstimate;
    return _buildInfoCard('Cost Estimate', Icons.attach_money, [
      _buildInfoRow(
        'Total Investment',
        '\$${cost['total_usd']}',
        valueColor: Colors.orange,
      ),
      _buildInfoRow('Timeframe', cost['timeframe'] ?? 'N/A'),
    ]);
  }

  Widget _buildSimilarProjectsCard(RestorationViewModel vm) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: EcoTheme.cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.history_edu, color: EcoTheme.cyan),
              const SizedBox(width: 8),
              Text(
                'Similar Projects',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...vm.similarProjects.map((project) => _buildProjectItem(project)),
        ],
      ),
    );
  }

  Widget _buildProjectItem(Map<String, dynamic> project) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            project['location'] ?? 'Unknown Location',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _buildInfoRow('Success Rate', '${project['success_rate']}%'),
          _buildInfoRow('Cost (per ha)', '\$${project['cost_per_ha_usd']}'),
        ],
      ),
    );
  }

  Widget _buildInfoCard(String title, IconData icon, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: EcoTheme.cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: EcoTheme.cyan),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                color: valueColor ?? Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(String error) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        border: Border.all(color: Colors.red),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.error, color: Colors.red),
          const SizedBox(width: 12),
          Expanded(
            child: Text(error, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // Photo Capture
  // ═══════════════════════════════════════════════════════════════

  Future<void> _capturePhoto(ImageSource source) async {
    try {
      final photo = await _picker.pickImage(source: source);
      if (photo == null) return;

      setState(() {
        _selectedPhoto = photo;
        _isUploading = true;
      });

      // Upload to Firebase Storage
      final photoUrls = await _uploadService.uploadPhotos([
        File(photo.path),
      ], 'restoration');
      final photoUrl = photoUrls.isNotEmpty ? photoUrls.first : '';

      // Set URL in ViewModel
      if (mounted) {
        Provider.of<RestorationViewModel>(
          context,
          listen: false,
        ).setPhotoUrl(photoUrl);
      }

      setState(() {
        _isUploading = false;
      });

      debugPrint("✅ Photo uploaded: $photoUrl");
    } catch (e) {
      setState(() {
        _isUploading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to upload photo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
