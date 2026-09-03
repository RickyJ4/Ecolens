/// Request to generate a cartographic map via the Cartographic Intelligence Engine.
class CartographicMapRequest {
  final List<double> bbox; // [west, south, east, north]
  final String mapType;
  final String? theme;
  final String? title;
  final String? subtitle;
  final List<String>? layerIds;
  final Map<String, dynamic>? geojsonData;
  final String? valueField;
  final String? labelField;
  final List<String>? dateRange;
  final String classificationMethod;
  final int nClasses;
  final String? colorPalette;
  final bool darkMode;
  final bool showLabels;
  final bool showLegend;
  final bool showScaleBar;
  final bool showNorthArrow;
  final bool showGrid;
  final bool showSourceAttribution;
  final String outputFormat;
  final int outputDpi;
  final double widthInches;
  final double heightInches;
  final String? showcaseId;

  const CartographicMapRequest({
    required this.bbox,
    this.mapType = 'choropleth',
    this.theme,
    this.title,
    this.subtitle,
    this.layerIds,
    this.geojsonData,
    this.valueField,
    this.labelField,
    this.dateRange,
    this.classificationMethod = 'natural_breaks',
    this.nClasses = 5,
    this.colorPalette,
    this.darkMode = false,
    this.showLabels = true,
    this.showLegend = true,
    this.showScaleBar = true,
    this.showNorthArrow = false,
    this.showGrid = true,
    this.showSourceAttribution = true,
    this.outputFormat = 'png',
    this.outputDpi = 150,
    this.widthInches = 16,
    this.heightInches = 12,
    this.showcaseId,
  });

  Map<String, dynamic> toJson() {
    return {
      if (showcaseId != null) 'showcase_id': showcaseId,
      'bbox': bbox,
      'map_type': mapType,
      if (theme != null) 'theme': theme,
      if (title != null) 'title': title,
      if (subtitle != null) 'subtitle': subtitle,
      if (layerIds != null) 'layer_ids': layerIds,
      if (geojsonData != null) 'geojson_data': geojsonData,
      if (valueField != null) 'value_field': valueField,
      if (labelField != null) 'label_field': labelField,
      if (dateRange != null) 'date_range': dateRange,
      'classification_method': classificationMethod,
      'n_classes': nClasses,
      if (colorPalette != null) 'color_palette': colorPalette,
      'dark_mode': darkMode,
      'show_labels': showLabels,
      'show_legend': showLegend,
      'show_scale_bar': showScaleBar,
      'show_north_arrow': showNorthArrow,
      'show_grid': showGrid,
      'show_source_attribution': showSourceAttribution,
      'output_format': outputFormat,
      'output_dpi': outputDpi,
      'width_inches': widthInches,
      'height_inches': heightInches,
    };
  }
}

/// Result from the Cartographic Intelligence Engine.
class CartographicMapResult {
  final String? imageUrl;
  final String? imageBase64;
  final CartographicQualityReport qualityReport;
  final Map<String, dynamic> metadata;
  final List<CartographicViolation> violations;
  final List<String> suggestions;
  final bool passedValidation;
  final List<String> attributions;
  final CartographicProjection projection;
  final int widthPx;
  final int heightPx;
  final String format;

  const CartographicMapResult({
    this.imageUrl,
    this.imageBase64,
    required this.qualityReport,
    required this.metadata,
    required this.violations,
    required this.suggestions,
    required this.passedValidation,
    required this.attributions,
    required this.projection,
    required this.widthPx,
    required this.heightPx,
    required this.format,
  });

  factory CartographicMapResult.fromJson(Map<String, dynamic> json) {
    return CartographicMapResult(
      imageUrl: json['image_url'] as String?,
      imageBase64: json['image_base64'] as String?,
      qualityReport: CartographicQualityReport.fromJson(
        Map<String, dynamic>.from(json['quality_report'] as Map? ?? {}),
      ),
      metadata: Map<String, dynamic>.from(json['metadata'] as Map? ?? {}),
      violations: (json['violations'] as List?)
              ?.map((v) => CartographicViolation.fromJson(
                  Map<String, dynamic>.from(v as Map)))
              .toList() ??
          [],
      suggestions: (json['suggestions'] as List?)
              ?.map((s) => s.toString())
              .toList() ??
          [],
      passedValidation: json['passed_validation'] as bool? ?? false,
      attributions: (json['attributions'] as List?)
              ?.map((a) => a.toString())
              .toList() ??
          [],
      projection: CartographicProjection.fromJson(
        Map<String, dynamic>.from(json['projection'] as Map? ?? {}),
      ),
      widthPx: (json['width_px'] as num?)?.toInt() ?? 0,
      heightPx: (json['height_px'] as num?)?.toInt() ?? 0,
      format: json['format'] as String? ?? 'png',
    );
  }
}

/// Quality report from the 6-dimension validation.
class CartographicQualityReport {
  final double overallScore;
  final bool passed;
  final Map<String, double> dimensions;
  final int violationCount;
  final int criticalCount;

  const CartographicQualityReport({
    required this.overallScore,
    required this.passed,
    required this.dimensions,
    this.violationCount = 0,
    this.criticalCount = 0,
  });

  factory CartographicQualityReport.fromJson(Map<String, dynamic> json) {
    final dims = <String, double>{};
    final rawDims = json['dimensions'] as Map?;
    if (rawDims != null) {
      for (final entry in rawDims.entries) {
        dims[entry.key.toString()] = (entry.value as num?)?.toDouble() ?? 0.0;
      }
    }

    return CartographicQualityReport(
      overallScore: (json['overall'] as num?)?.toDouble() ?? 0.0,
      passed: json['passed'] as bool? ?? false,
      dimensions: dims,
      violationCount: (json['violation_count'] as num?)?.toInt() ?? 0,
      criticalCount: (json['critical_count'] as num?)?.toInt() ?? 0,
    );
  }
}

/// A rule violation detected during map validation.
class CartographicViolation {
  final String ruleId;
  final String category;
  final String severity;
  final String message;
  final String details;
  final bool autoCorrectable;
  final String? correctionHint;
  final double scorePenalty;

  const CartographicViolation({
    required this.ruleId,
    required this.category,
    required this.severity,
    required this.message,
    required this.details,
    this.autoCorrectable = false,
    this.correctionHint,
    this.scorePenalty = 0.0,
  });

  factory CartographicViolation.fromJson(Map<String, dynamic> json) {
    return CartographicViolation(
      ruleId: json['rule_id'] as String? ?? '',
      category: json['category'] as String? ?? '',
      severity: json['severity'] as String? ?? 'info',
      message: json['message'] as String? ?? '',
      details: json['details'] as String? ?? '',
      autoCorrectable: json['auto_correctable'] as bool? ?? false,
      correctionHint: json['correction_hint'] as String?,
      scorePenalty: (json['score_penalty'] as num?)?.toDouble() ?? 0.0,
    );
  }

  bool get isCritical => severity == 'critical';
  bool get isError => severity == 'error';
  bool get isWarning => severity == 'warning';
}

/// Projection recommendation from the engine.
class CartographicProjection {
  final int? epsg;
  final String name;
  final String proj4;
  final String rationale;
  final List<String> properties;
  final String distortionNote;

  const CartographicProjection({
    this.epsg,
    required this.name,
    required this.proj4,
    required this.rationale,
    required this.properties,
    required this.distortionNote,
  });

  factory CartographicProjection.fromJson(Map<String, dynamic> json) {
    return CartographicProjection(
      epsg: (json['epsg'] as num?)?.toInt(),
      name: json['name'] as String? ?? 'Unknown',
      proj4: json['proj4'] as String? ?? '',
      rationale: json['rationale'] as String? ?? '',
      properties: (json['properties'] as List?)
              ?.map((p) => p.toString())
              .toList() ??
          [],
      distortionNote: json['distortion_note'] as String? ?? '',
    );
  }
}

/// A map template definition from the engine.
class CartographicTemplate {
  final String id;
  final String name;
  final String description;
  final String defaultPaletteType;
  final int defaultNClasses;
  final bool requiresNormalization;

  const CartographicTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.defaultPaletteType,
    required this.defaultNClasses,
    required this.requiresNormalization,
  });

  factory CartographicTemplate.fromJson(Map<String, dynamic> json) {
    return CartographicTemplate(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      defaultPaletteType: json['default_palette_type'] as String? ?? 'sequential',
      defaultNClasses: (json['default_n_classes'] as num?)?.toInt() ?? 5,
      requiresNormalization: json['requires_normalization'] as bool? ?? false,
    );
  }
}

/// A showcase example with real disaster data.
class CartographicShowcase {
  final String id;
  final String templateId;
  final String title;
  final String subtitle;
  final String disasterType;
  final String description;
  final List<double> bbox;
  final String palette;
  final int nClasses;
  final String whyThisTemplate;
  final List<String> keyFindings;
  final String dateRange;

  const CartographicShowcase({
    required this.id,
    required this.templateId,
    required this.title,
    required this.subtitle,
    required this.disasterType,
    required this.description,
    required this.bbox,
    required this.palette,
    required this.nClasses,
    required this.whyThisTemplate,
    required this.keyFindings,
    required this.dateRange,
  });

  factory CartographicShowcase.fromJson(Map<String, dynamic> json) {
    return CartographicShowcase(
      id: json['id'] as String? ?? '',
      templateId: json['template_id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      subtitle: json['subtitle'] as String? ?? '',
      disasterType: json['disaster_type'] as String? ?? '',
      description: json['description'] as String? ?? '',
      bbox: (json['bbox'] as List?)?.map((b) => (b as num).toDouble()).toList() ?? [],
      palette: json['palette'] as String? ?? 'YlOrRd',
      nClasses: (json['n_classes'] as num?)?.toInt() ?? 5,
      whyThisTemplate: json['why_this_template'] as String? ?? '',
      keyFindings: (json['key_findings'] as List?)
              ?.map((f) => f.toString())
              .toList() ??
          [],
      dateRange: json['date_range'] as String? ?? '',
    );
  }
}

/// Full catalog returned by get_map_templates endpoint.
class CartographicCatalog {
  final List<CartographicTemplate> templates;
  final List<CartographicShowcase> showcaseExamples;
  final Map<String, List<String>> palettes;
  final Map<String, List<String>> palettePreview;
  final List<Map<String, dynamic>> dataSources;
  final List<Map<String, dynamic>> classificationMethods;

  const CartographicCatalog({
    required this.templates,
    required this.showcaseExamples,
    required this.palettes,
    required this.palettePreview,
    required this.dataSources,
    required this.classificationMethods,
  });

  factory CartographicCatalog.fromJson(Map<String, dynamic> json) {
    // Parse palettes
    final palettesRaw = json['palettes'] as Map? ?? {};
    final palettes = <String, List<String>>{};
    for (final entry in palettesRaw.entries) {
      palettes[entry.key.toString()] =
          (entry.value as List?)?.map((p) => p.toString()).toList() ?? [];
    }

    // Parse palette previews
    final previewsRaw = json['palette_previews'] as Map? ?? {};
    final previews = <String, List<String>>{};
    for (final entry in previewsRaw.entries) {
      previews[entry.key.toString()] =
          (entry.value as List?)?.map((c) => c.toString()).toList() ?? [];
    }

    return CartographicCatalog(
      templates: (json['templates'] as List?)
              ?.map((t) => CartographicTemplate.fromJson(
                  Map<String, dynamic>.from(t as Map)))
              .toList() ??
          [],
      showcaseExamples: (json['showcase_examples'] as List?)
              ?.map((e) => CartographicShowcase.fromJson(
                  Map<String, dynamic>.from(e as Map)))
              .toList() ??
          [],
      palettes: palettes,
      palettePreview: previews,
      dataSources: (json['data_sources'] as List?)
              ?.map((s) => Map<String, dynamic>.from(s as Map))
              .toList() ??
          [],
      classificationMethods: (json['classification_methods'] as List?)
              ?.map((m) => Map<String, dynamic>.from(m as Map))
              .toList() ??
          [],
    );
  }
}
