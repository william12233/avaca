// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get addTitle => 'Add Collection';

  @override
  String get noPhoto => 'No Photo';

  @override
  String get selectPhoto => 'Select Photo';

  @override
  String get removePhoto => 'Remove Photo';

  @override
  String get actressNameRequired => 'Actress Name (Required)';

  @override
  String get saveCard => 'Save Card';

  @override
  String get changePhoto => 'Change Photo';

  @override
  String get deletePhoto => 'Delete Photo';

  @override
  String get noAttributesSet => 'No Attributes Set';

  @override
  String get bodyInfo => 'Details';

  @override
  String get heightCm => 'Height (cm)';

  @override
  String get weightKg => 'Weight (kg)';

  @override
  String get cup => 'Cup';

  @override
  String get measurements => 'Measurements';

  @override
  String get privateNotes => 'Private Notes';

  @override
  String get noNotes => 'No Notes';

  @override
  String get confirmDeleteTitle => 'Confirm Delete?';

  @override
  String get deleteWarningWithPhoto =>
      'This cannot be undone. The photo file will also be deleted.';

  @override
  String get cancel => 'Cancel';

  @override
  String get reload => 'Reload';

  @override
  String get confirmDelete => 'Delete';

  @override
  String get edit => 'Edit';

  @override
  String get delete => 'Delete';

  @override
  String get appTitle => 'AVACA';

  @override
  String get search => 'Search';

  @override
  String get filterAndSort => 'Filter & Sort';

  @override
  String get filterSection => 'Filter';

  @override
  String get sortSection => 'Sort';

  @override
  String get sortCreatedDesc => 'Added (Newest)';

  @override
  String get sortCreatedAsc => 'Added (Oldest)';

  @override
  String get sortModifiedDesc => 'Modified (Newest)';

  @override
  String get sortModifiedAsc => 'Modified (Oldest)';

  @override
  String get sortAgeAsc => 'Age (Low to High)';

  @override
  String get sortAgeDesc => 'Age (High to Low)';

  @override
  String get birthDate => 'Birthday';

  @override
  String get setBirthDate => 'Set birthday';

  @override
  String get clear => 'Clear';

  @override
  String get done => 'Done';

  @override
  String ageWithBirthDate(int age, String date) {
    return 'Age $age  $date';
  }

  @override
  String get add => 'Add';

  @override
  String get settings => 'Settings';

  @override
  String get themeAndColors => 'Theme & Colors';

  @override
  String get interfaceSettings => 'Interface';

  @override
  String loadFailed(String error) {
    return 'Failed to load: $error';
  }

  @override
  String get noData => 'No Data';

  @override
  String get searchNameHint => 'Enter a name to search quickly...';

  @override
  String get applySettings => 'Apply Settings';

  @override
  String get themeMode => 'Theme Mode';

  @override
  String get followSystem => 'Follow System';

  @override
  String get lightTheme => 'Light';

  @override
  String get darkTheme => 'Dark';

  @override
  String get customTheme => 'Custom Theme';

  @override
  String get pureBlackAmoled => 'Pure Black AMOLED';

  @override
  String get pureBlackOnlyDark => 'Only works with dark theme';

  @override
  String get colorSurface => 'Background';

  @override
  String get colorSurfaceContainer => 'Card Background';

  @override
  String get colorOnSurface => 'Primary Text';

  @override
  String get colorOnSurfaceVariant => 'Secondary Text';

  @override
  String get colorPrimary => 'Primary Accent';

  @override
  String get colorOnPrimary => 'Text on Primary';

  @override
  String get colorOutline => 'Border / Divider';

  @override
  String get colorSnackbarBackground => 'Snackbar Background';

  @override
  String adjustColorTitle(String colorLabel) {
    return 'Adjust $colorLabel';
  }

  @override
  String get apply => 'Apply';

  @override
  String get imageReadFailedUnsupportedFormat =>
      'Failed to read image. The format may not be supported.';

  @override
  String get enterName => 'Please enter a name';

  @override
  String get collectionAdded => 'Added to collection';

  @override
  String get alreadyInCollection => 'Already in collection';

  @override
  String get dataDeleted => 'Data deleted permanently';

  @override
  String get deleteFailed => 'Delete failed';

  @override
  String get photoCroppedRememberSave => 'Photo cropped. Remember to save!';

  @override
  String get detailSaved => 'Details saved';

  @override
  String get saveFailedDuplicateName =>
      'Save failed. The name may already exist.';

  @override
  String get dataNotFound => 'Data not found';

  @override
  String get attrCensored => 'Censored';

  @override
  String get attrUncensored => 'Uncensored';

  @override
  String get attrWestern => 'Western';

  @override
  String get attrFc2 => 'FC2';

  @override
  String get attrDomestic => 'Domestic';

  @override
  String get filterAll => 'All';

  @override
  String get imageCropLoadErrorTitle => 'Image load error';

  @override
  String get close => 'Close';

  @override
  String get imageDecodeFailed => 'Failed to decode image';

  @override
  String get cropZoom => 'Zoom';

  @override
  String get cropPanX => 'Horizontal pan';

  @override
  String get cropPanY => 'Vertical pan';

  @override
  String get confirmCrop => 'Crop';

  @override
  String get language => 'Language';

  @override
  String get worksPageSize => 'Works page size';

  @override
  String get worksPageSizeSmall => 'Small';

  @override
  String get worksPageSizeLarge => 'Large';

  @override
  String get traditionalChineseTaiwan => 'Traditional Chinese (Taiwan)';

  @override
  String get english => 'English';

  @override
  String get simplifiedChinese => 'Simplified Chinese';

  @override
  String get japanese => 'Japanese';

  @override
  String get works => 'Works';

  @override
  String get relatedActresses => 'Related actresses';

  @override
  String get workStorageTitle => 'Work storage record';

  @override
  String get workStorageSaved => 'Saved';

  @override
  String get workStorageNotSaved => 'Not saved';

  @override
  String get workStorageQuality => 'Quality';

  @override
  String get workStorageFrameRate => 'Frame rate';

  @override
  String get workStorageSave => 'Save';

  @override
  String get workStorageUpdated => 'Work storage record updated';

  @override
  String get workStorageUpdateFailed => 'Failed to update work storage record';

  @override
  String get workStorageFilterStored => 'Saved';

  @override
  String get workStorageFilterNotStored => 'Not saved';

  @override
  String get workStorageFilterAll => 'All';

  @override
  String get aliases => 'Aliases';

  @override
  String get manageAliases => 'Manage aliases';

  @override
  String get aliasInputHint => 'Enter an alternate name';

  @override
  String get addAlias => 'Add alias';

  @override
  String get saveAliases => 'Save aliases';

  @override
  String get noAliases => 'No aliases';

  @override
  String get deleteWorks => 'Delete works';

  @override
  String get deleteWorksTitle => 'Delete selected works?';

  @override
  String get deleteWorksWarning =>
      'The selected works will be removed globally, including links from other actresses.';

  @override
  String worksDeleted(int count) {
    return 'Deleted $count works';
  }

  @override
  String get loadFailedGeneric => 'Failed to load';

  @override
  String actressWorksTitle(String actressName) {
    return 'Works featuring $actressName';
  }

  @override
  String get searchWorks => 'Search works';

  @override
  String get workCodeSearchHint => 'Enter a work code to search...';

  @override
  String get noMatchingWorks => 'No matching works';

  @override
  String get scrapeWorks => 'Scrape works';

  @override
  String get scrapeSettings => 'Scrape settings';

  @override
  String get scrapeExistingData => 'Existing data policy';

  @override
  String get scrapeUpdateAll => 'Update existing data';

  @override
  String get scrapeAutomaticDerivedFilter =>
      'Automatically exclude derived or bundled works';

  @override
  String get scrapeAutomaticDerivedFilterDescription =>
      'Use lineage and work semantics; keep unknown works and never exclude by prefix alone.';

  @override
  String get scrapeAdvancedRules => 'Advanced rules';

  @override
  String get scrapeAdvancedRulesDescription =>
      'Enter a full work code or prefix, e.g. KCKC or KCKC-212.';

  @override
  String get scrapeExactAllows => 'Code/prefix allows';

  @override
  String get scrapeExactDenies => 'Code/prefix denies';

  @override
  String get scrapeRuleHint => 'Enter a code or prefix';

  @override
  String get scrapeNoRules => 'No rules configured';

  @override
  String get syncActressDetails => 'Sync profile details';

  @override
  String get replaceActressImage => 'Replace actress image';

  @override
  String get scrapeAvatarUnavailable => 'No usable actress image was found.';

  @override
  String get scrapeAvatarFailed =>
      'Actress image replacement failed; the previous image was kept.';

  @override
  String get fillMissingOnly => 'Only fill missing information on rescrape';

  @override
  String get startScrape => 'Start scraping';

  @override
  String get noWorks => 'No works yet';

  @override
  String durationMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String get studio => 'Studio';

  @override
  String get publisher => 'Publisher';

  @override
  String get series => 'Series';

  @override
  String scrapeComplete(int saved, int excluded, int failed) {
    return 'Scrape complete: saved $saved, excluded $excluded, failed $failed';
  }

  @override
  String scrapeCancelled(int saved, int excluded, int failed) {
    return 'Scrape cancelled: saved $saved, excluded $excluded, failed $failed';
  }

  @override
  String get scrapeFailed => 'Scrape failed. Please try again.';

  @override
  String get scrapePhaseCollecting => 'Getting the work list';

  @override
  String get scrapePhaseSyncingActress => 'Syncing actress details';

  @override
  String get scrapePhaseFetchingDetails => 'Getting work details';

  @override
  String get scrapePhaseResolvingWorks => 'Merging deduplicated works';

  @override
  String get scrapePhaseSavingWorks => 'Saving works and downloading images';

  @override
  String get scrapePhaseCompleted => 'Scrape complete';

  @override
  String get scrapeSyncingTitle => 'Scraping';

  @override
  String get scrapeSyncCompleted => 'Scrape complete';

  @override
  String get scrapeSyncPartial => 'Scrape complete with some failures';

  @override
  String get scrapeSyncFailed => 'Scrape failed';

  @override
  String get scrapeSyncStopped => 'Scrape stopped';

  @override
  String get scrapeDetailsSection => 'Details';

  @override
  String get scrapeWorksSection => 'Works';

  @override
  String get scrapeDownloadSection => 'Downloads';

  @override
  String scrapeCurrentWork(String code) {
    return 'Currently processing: $code';
  }

  @override
  String get scrapeImagesLabel => 'Work images';

  @override
  String get scrapeSavedCount => 'Saved';

  @override
  String get scrapeExcludedCount => 'Excluded';

  @override
  String get scrapeFailedCount => 'Failed';

  @override
  String get scrapeStatusWaiting => 'Waiting';

  @override
  String get scrapeStatusSyncing => 'Scraping';

  @override
  String get scrapeStatusCompleted => 'Complete';

  @override
  String get scrapeStatusPartial => 'Partial';

  @override
  String get scrapeStatusFailed => 'Failed';

  @override
  String get scrapeStatusCancelled => 'Stopped';

  @override
  String get scrapeStatusNoNewWorks => 'Complete, no new works';

  @override
  String get scrapeStatusUnavailable => 'Unavailable';

  @override
  String get scrapeStatusBlocked => 'Page blocked';

  @override
  String get scrapeStatusRateLimited => 'Rate limited';

  @override
  String get scrapeStatusTimedOut => 'Timed out';

  @override
  String get stopScrape => 'Stop';

  @override
  String scrapeProgressSummary(int saved, int excluded, int failed) {
    return 'Saved $saved, excluded $excluded, failed $failed';
  }

  @override
  String scrapeFailedWorksTitle(int count) {
    return 'Failed works ($count)';
  }

  @override
  String scrapeImageFailuresTitle(int count) {
    return 'Image download failures ($count)';
  }

  @override
  String get scrapeFailureDetailsUnavailable =>
      'No source returned usable work details';

  @override
  String get scrapeFailureDetailCodeMismatch =>
      'Work detail code did not match the work';

  @override
  String get scrapeFailureInvalidCode =>
      'The work code could not be normalized';

  @override
  String get scrapeFailurePerformerCountUnavailable =>
      'Performer count was unavailable';

  @override
  String get scrapeFailureDatabaseSave => 'Work data could not be saved';

  @override
  String get scrapeImageFailureCard => 'cover image';

  @override
  String get scrapeImageFailureDetail => 'detail image';

  @override
  String get scrapeImageFailureBoth => 'cover and detail images';

  @override
  String get javBusVerificationTitle => 'JavBus verification';

  @override
  String get javBusVerificationInstructions =>
      'JavBus requires a manual regional age check. Answer every question to continue scraping in the same secure session.';

  @override
  String get javBusVerificationSubmit => 'Submit verification';

  @override
  String get settingsDataTransferTitle => 'Data transfer';

  @override
  String get settingsDataTransferSubtitle =>
      'Back up or restore actors, works, details, and images as a ZIP.';

  @override
  String get dataTransferExportTitle => 'Export data';

  @override
  String get dataTransferExportSubtitle =>
      'Choose a destination for a complete ZIP backup.';

  @override
  String get dataTransferImportTitle => 'Import data';

  @override
  String get dataTransferImportSubtitle =>
      'Choose a ZIP backup to restore it for immediate use.';

  @override
  String get dataTransferPreparing => 'Preparing data…';

  @override
  String get dataTransferDuplicateProgress =>
      'Waiting for duplicate-actor choices…';

  @override
  String get dataTransferWriting => 'Writing data and images…';

  @override
  String get dataTransferExportSuccess => 'Export complete.';

  @override
  String dataTransferExportSuccessWithSkippedImages(int count) {
    return 'Export complete; skipped $count unusable images.';
  }

  @override
  String get dataTransferImportSuccess =>
      'Import complete. The data is ready to use.';

  @override
  String get dataTransferDuplicateTitle => 'Duplicate actor found';

  @override
  String get dataTransferDuplicateExplanation =>
      'Compare the avatars and work counts, then choose which actor details to use. Existing works and relations are kept.';

  @override
  String get dataTransferKeepExisting => 'Keep current details';

  @override
  String get dataTransferUseImported => 'Use imported details';

  @override
  String get dataTransferContinue => 'Continue';

  @override
  String dataTransferWorkCount(int count) {
    return 'Works: $count';
  }

  @override
  String get dataTransferArchiveTooLarge =>
      'The ZIP exceeds the supported size.';

  @override
  String get dataTransferUnsafeArchive =>
      'The ZIP contains an unsafe file path.';

  @override
  String get dataTransferCorruptArchive =>
      'The ZIP is corrupt or an image checksum failed.';

  @override
  String get dataTransferFileUnreadable =>
      'The selected file could not be read.';

  @override
  String get dataTransferActorNameConflict =>
      'The imported actor name conflicts with another record.';

  @override
  String get dataTransferBusy =>
      'Another data transfer is already in progress.';

  @override
  String get dataTransferFailed =>
      'Data transfer failed. Existing data was not changed.';

  @override
  String get otherSettings => 'Other';

  @override
  String get about => 'About';

  @override
  String get github => 'github';

  @override
  String get feedbackSuggestions => 'Feedback';

  @override
  String get scrapeSources => 'Scrape sources';

  @override
  String get scrapeSourceDetailsTitle => 'Actress details source';

  @override
  String get scrapeSourceWorksTitle => 'Works source';

  @override
  String get scrapeSourcePriorityHint =>
      'Select sources and drag to set priority';

  @override
  String get scrapeSourceAliasTitle => 'Actress aliases source';

  @override
  String get scrapeSourceMinnanoAv => 'Minnano AV';

  @override
  String get scrapeSourceJavBus => 'JavBus';

  @override
  String get scrapeSourceAvBase => 'AvBase';

  @override
  String get scrapeSourceAvWiki => 'AV-Wiki';

  @override
  String get scrapeSourceAll => 'All sources (merge and deduplicate by code)';

  @override
  String get scrapeSourceSaveFailed => 'Could not save scrape source settings.';

  @override
  String get scrapeSourceConnectionTitle => 'Scrape source connections';

  @override
  String get scrapeSourceConnectionSubtitle =>
      'View the added scrape websites, test their connections, and complete verification here.';

  @override
  String get scrapeSourceRetest => 'Retest connections';

  @override
  String get scrapeSourceTesting => 'Testing…';

  @override
  String get scrapeSourceNotTested => 'Not tested';

  @override
  String get scrapeSourceConnected => 'Connected';

  @override
  String get scrapeSourceConnectionFailed => 'Connection failed';

  @override
  String get scrapeSourceVerificationRequired => 'Verification required';

  @override
  String get scrapeAliases => 'Scrape aliases';

  @override
  String get scrapeAliasesDescription =>
      'Save names found by the alias source as actress aliases, excluding the current name.';

  @override
  String get scrapePartial => 'Some sources or records could not be processed.';

  @override
  String get scrapeZeroResults => 'No new works were found.';

  @override
  String get softwareUpdate => 'Software update';

  @override
  String get softwareUpdateDescription =>
      'Check for and install the latest AVACA version.';

  @override
  String get currentVersion => 'Current version';

  @override
  String get latestVersion => 'Latest version';

  @override
  String get autoCheckUpdates => 'Check for updates automatically';

  @override
  String get checkForUpdates => 'Check for updates';

  @override
  String get checkingForUpdates => 'Checking for updates…';

  @override
  String get downloadingUpdate => 'Downloading update…';

  @override
  String get verifyingUpdate => 'Verifying update…';

  @override
  String get installingUpdate => 'Starting installation…';

  @override
  String get updateAvailable => 'Update available';

  @override
  String get upToDate => 'AVACA is up to date.';

  @override
  String get updateNow => 'Update now';

  @override
  String get updateLater => 'Later';

  @override
  String get updateUnavailable =>
      'No update file is available for this device.';

  @override
  String get updateCheckFailed =>
      'Could not check for updates. Try again later.';

  @override
  String get updateDownloadFailed =>
      'The update download failed. Existing data was not changed.';

  @override
  String get updateIntegrityFailed =>
      'The update file failed verification. The update was stopped.';

  @override
  String get updateNotSupported =>
      'Automatic updates are not supported on this device.';

  @override
  String get updateInstallPermissionRequired =>
      'Allow AVACA to install apps from this source first.';

  @override
  String get updatePortableFolderNotWritable =>
      'The portable app folder is not writable. The update was stopped.';

  @override
  String get updateInstallerFailed =>
      'The updater could not start. The current version was kept.';

  @override
  String get updateDataPreserved => 'Your data and settings will be preserved.';

  @override
  String get prefixRouteRulesTitle => 'Prefix route rules';

  @override
  String get prefixRouteRulesSubtitle =>
      'View and manage image families learned from validated downloads.';

  @override
  String prefixRouteRuleCount(int count) {
    return '$count learned Prefix rules';
  }

  @override
  String get prefixRouteSearchHint => 'Search Prefix';

  @override
  String get prefixRouteNoRules =>
      'No Prefix route rules have been learned yet.';

  @override
  String get prefixRouteNoSearchResults => 'No Prefix rules match this search.';

  @override
  String get prefixRouteBestFamily => 'Priority family';

  @override
  String get prefixRouteNotAvailable => 'Not available';

  @override
  String get prefixRouteCandidates => 'Known candidates';

  @override
  String prefixRouteSuccessCount(int count) {
    return 'Successes: $count';
  }

  @override
  String prefixRouteFailureCount(int count) {
    return 'Failures: $count';
  }

  @override
  String prefixRouteLastSuccess(String time) {
    return 'Last success: $time';
  }

  @override
  String prefixRouteLastFailure(String time) {
    return 'Last failure: $time';
  }

  @override
  String get prefixRouteStatusVerified => 'Verified';

  @override
  String get prefixRouteStatusExceptions => 'Has exceptions';

  @override
  String get prefixRouteStatusPending => 'Pending validation';

  @override
  String get prefixRouteStatusProbeFailed => 'Probe failed';

  @override
  String get prefixRouteManualOverride => 'Manual override';

  @override
  String get prefixRouteAutomatic => 'Automatic';

  @override
  String get prefixRouteAutomaticDescription =>
      'Use learned candidates first, then probe the supported families when needed.';

  @override
  String get prefixRouteManualDescription =>
      'This family is tried first. Learned statistics remain available.';

  @override
  String get prefixRouteFamilyDmmStandard => 'DMM standard';

  @override
  String get prefixRouteFamilyDmmLeadingOne => 'DMM leading one';

  @override
  String get prefixRouteFamilyDmmH1711 => 'DMM H1711';

  @override
  String get prefixRouteFamilyDmmRebeccaH346 => 'DMM Rebecca H346';

  @override
  String get prefixRouteFamilyMgstagePrestige => 'MGStage Prestige';

  @override
  String get prefixRouteFamilyMgstageSeikyouiku => 'MGStage Seikyouiku';

  @override
  String get prefixRouteExport => 'Export rules';

  @override
  String get prefixRouteImport => 'Import rules';

  @override
  String get prefixRouteExportDialogTitle => 'Export Prefix rules';

  @override
  String get prefixRouteExportRulesOnly => 'Rules only';

  @override
  String get prefixRouteExportRulesOnlyDescription =>
      'Export families without validation statistics.';

  @override
  String get prefixRouteExportWithStatistics => 'Rules and statistics';

  @override
  String get prefixRouteExportWithStatisticsDescription =>
      'Include success, failure, and timestamp data.';

  @override
  String get prefixRouteExportSuccess => 'Prefix rules exported.';

  @override
  String get prefixRouteImportDialogTitle => 'Import Prefix rules';

  @override
  String prefixRouteImportPreview(int rules, int conflicts) {
    return 'Found $rules rules. Manual override conflicts: $conflicts.';
  }

  @override
  String get prefixRouteImportMerge => 'Merge';

  @override
  String get prefixRouteImportReplace => 'Replace';

  @override
  String prefixRouteImportSuccess(int count) {
    return 'Imported $count Prefix rules.';
  }

  @override
  String get prefixRouteOperationFailed =>
      'The Prefix route operation failed. Existing rules were not changed.';

  @override
  String get prefixRouteLoadFailed => 'Prefix route rules could not be loaded.';

  @override
  String get prefixRouteClearAutomatic => 'Clear automatic learning';

  @override
  String get prefixRouteClearAutomaticTitle => 'Clear automatic learning?';

  @override
  String get prefixRouteClearAutomaticMessage =>
      'Learned candidates and statistics will be cleared. Manual overrides and downloaded images will be kept.';

  @override
  String get prefixRouteClearAutomaticSuccess =>
      'Automatic Prefix learning was cleared.';

  @override
  String get prefixRouteReset => 'Reset learning';

  @override
  String get prefixRouteResetTitle => 'Reset this Prefix learning?';

  @override
  String get prefixRouteResetMessage =>
      'Learned candidates and statistics will be cleared. A manual override, if present, will be kept.';

  @override
  String get prefixRouteForget => 'Remove this Prefix rule';

  @override
  String get prefixRouteForgetTitle => 'Remove this Prefix rule?';

  @override
  String get prefixRouteForgetMessage =>
      'The learned data and manual override for this Prefix will be removed. Downloaded images and work data will not be changed.';

  @override
  String get workFieldProvenanceTitle => 'Field provenance';

  @override
  String get workFieldProvenanceSource => 'Source';

  @override
  String get workFieldProvenanceObservedAt => 'Observed';

  @override
  String get workFieldProvenanceUnknown => 'Unknown source';

  @override
  String get dataHealthTitle => 'Data health';

  @override
  String get dataHealthSubtitle =>
      'Check counts, missing metadata/images, provenance, pending cleanup, and scrape-source errors.';

  @override
  String dataHealthSectionUnavailable(String section) {
    return 'This section could not be loaded: $section';
  }

  @override
  String get dataHealthRefresh => 'Refresh';

  @override
  String get dataHealthActresses => 'Actresses';

  @override
  String get dataHealthWorks => 'Works';

  @override
  String get dataHealthStored => 'Stored videos';

  @override
  String get dataHealthNotStored => 'Not stored';

  @override
  String get dataHealthMetadataIssues => 'Missing work fields';

  @override
  String get dataHealthMissingImages => 'Missing image references';

  @override
  String get dataHealthMissingProvenance => 'Missing field provenance';

  @override
  String get dataHealthPendingDeletions => 'Pending file cleanup';

  @override
  String get dataHealthJobStates => 'Scrape job states';

  @override
  String get dataHealthSourceErrors => 'Source errors in the last 7 days';

  @override
  String get scrapeJobsTitle => 'Scrape jobs';

  @override
  String get scrapeJobsEmpty => 'There are no scrape jobs yet.';

  @override
  String scrapeJobsSelectedCount(int count) {
    return '$count selected';
  }

  @override
  String get scrapeJobsDelete => 'Delete';

  @override
  String get scrapeJobsDeleteTitle => 'Delete selected scrape jobs?';

  @override
  String scrapeJobsDeleteMessage(int count) {
    return 'Delete $count completed scrape-job records? Works, actresses, and settings will not be changed.';
  }

  @override
  String get scrapeJobsDeleteActive =>
      'Running or queued jobs cannot be deleted. Select completed jobs only.';

  @override
  String scrapeJobsDeleted(int count) {
    return 'Deleted $count scrape-job records.';
  }

  @override
  String get scrapeJobsDeleteFailed => 'Could not delete scrape-job records.';

  @override
  String get scrapeJobDetailTitle => 'Scrape job details';

  @override
  String get scrapeJobPause => 'Pause';

  @override
  String get scrapeJobResume => 'Resume';

  @override
  String get scrapeJobCancel => 'Cancel';

  @override
  String get scrapeJobRetryFailed => 'Retry failed works only';

  @override
  String get scrapeJobEvents => 'Event journal';

  @override
  String get scrapeJobDiagnostics => 'Scrape diagnostics';

  @override
  String get scrapeJobItems => 'Work checkpoints';

  @override
  String get scrapeJobNoEvents => 'No events have been recorded.';

  @override
  String get scrapeJobNoItems => 'No work checkpoints have been recorded.';

  @override
  String get scrapeJobFilterAll => 'All';

  @override
  String get scrapeJobFilterReview => 'Review';

  @override
  String get scrapeJobFilterKeep => 'Keep';

  @override
  String get scrapeJobFilterExclude => 'Exclude';

  @override
  String get scrapeJobFilterFailed => 'Failed';

  @override
  String get scrapeJobNoFilteredItems => 'No checkpoints match this filter.';

  @override
  String get scrapeJobStateReview => 'Review';

  @override
  String get scrapeJobStateQueued => 'Queued';

  @override
  String get scrapeJobStateRunning => 'Running';

  @override
  String get scrapeJobStatePaused => 'Paused';

  @override
  String get scrapeJobStateWaiting => 'Waiting for verification';

  @override
  String get scrapeJobStateSucceeded => 'Succeeded';

  @override
  String get scrapeJobStatePartial => 'Partially complete';

  @override
  String get scrapeJobStateFailed => 'Failed';

  @override
  String get scrapeJobStateCancelled => 'Cancelled';

  @override
  String get scrapeJobStateExcluded => 'Excluded';

  @override
  String scrapeJobCollectionSummary(int raw, int unique, int duplicates) {
    return 'Found $raw; unique $unique; duplicates $duplicates';
  }

  @override
  String scrapeJobDetailProgress(int current, int total) {
    return 'Details $current/$total';
  }

  @override
  String scrapeJobTerminalProgress(
    int processed,
    int total,
    int saved,
    int excluded,
    int failed,
  ) {
    return 'Processed $processed/$total; saved $saved; excluded $excluded; failed $failed';
  }

  @override
  String scrapeJobCandidateSummary(int count, int duplicates) {
    return 'Candidates $count; collection duplicates $duplicates';
  }

  @override
  String scrapeJobSupplementalEvidence(int current, int total) {
    return 'Supplemental evidence $current/$total';
  }

  @override
  String scrapeJobOutcomeSummary(
    int processed,
    int total,
    int keep,
    int review,
    int excluded,
    int failed,
  ) {
    return 'Processed $processed/$total; kept $keep; review $review; excluded $excluded; failed $failed';
  }

  @override
  String scrapeJobRulesVersion(String version) {
    return 'Rules version: $version';
  }

  @override
  String get settingsDataHealthTitle => 'Data health';

  @override
  String get settingsDataHealthSubtitle =>
      'Inspect data completeness and scrape observability.';

  @override
  String get settingsScrapeJobsTitle => 'Scrape jobs';

  @override
  String get settingsScrapeJobsSubtitle =>
      'Inspect queue, recovery, pause, and failed-work retry.';
}
