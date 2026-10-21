// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get addTitle => 'コレクションに追加';

  @override
  String get noPhoto => '写真なし';

  @override
  String get selectPhoto => '写真を選択';

  @override
  String get removePhoto => '写真を削除';

  @override
  String get actressNameRequired => '女優名（必須）';

  @override
  String get saveCard => 'カードを保存';

  @override
  String get changePhoto => '写真を変更';

  @override
  String get deletePhoto => '写真を削除';

  @override
  String get noAttributesSet => '属性未設定';

  @override
  String get bodyInfo => '詳細情報';

  @override
  String get heightCm => '身長（cm）';

  @override
  String get weightKg => '体重（kg）';

  @override
  String get cup => 'カップ';

  @override
  String get measurements => 'スリーサイズ';

  @override
  String get privateNotes => '非公開メモ';

  @override
  String get noNotes => 'メモなし';

  @override
  String get confirmDeleteTitle => '削除しますか？';

  @override
  String get deleteWarningWithPhoto => 'この操作は元に戻せません。写真ファイルも削除されます。';

  @override
  String get cancel => 'キャンセル';

  @override
  String get reload => '再読み込み';

  @override
  String get confirmDelete => '削除';

  @override
  String get edit => '編集';

  @override
  String get delete => '削除';

  @override
  String get appTitle => 'AVACA コレクションライブラリ';

  @override
  String get search => '検索';

  @override
  String get filterAndSort => '絞り込み・並べ替え';

  @override
  String get filterSection => '絞り込み';

  @override
  String get sortSection => '並べ替え';

  @override
  String get sortCreatedDesc => '追加日（新しい順）';

  @override
  String get sortCreatedAsc => '追加日（古い順）';

  @override
  String get sortModifiedDesc => '更新日（新しい順）';

  @override
  String get sortModifiedAsc => '更新日（古い順）';

  @override
  String get sortAgeAsc => '年齢（低い順）';

  @override
  String get sortAgeDesc => '年齢（高い順）';

  @override
  String get birthDate => '生年月日';

  @override
  String get setBirthDate => '生年月日を設定';

  @override
  String get clear => 'クリア';

  @override
  String get done => '完了';

  @override
  String ageWithBirthDate(int age, String date) {
    return '$age歳  $date';
  }

  @override
  String get add => '追加';

  @override
  String get settings => '設定';

  @override
  String get themeAndColors => 'テーマと色';

  @override
  String get interfaceSettings => 'インターフェース';

  @override
  String loadFailed(String error) {
    return '読み込みに失敗しました: $error';
  }

  @override
  String get noData => 'データなし';

  @override
  String get searchNameHint => '名前を入力してすばやく検索...';

  @override
  String get applySettings => '設定を適用';

  @override
  String get themeMode => 'テーマモード';

  @override
  String get followSystem => 'システム設定に従う';

  @override
  String get lightTheme => 'ライト';

  @override
  String get darkTheme => 'ダーク';

  @override
  String get customTheme => 'カスタムテーマ';

  @override
  String get pureBlackAmoled => 'ピュアブラック AMOLED';

  @override
  String get pureBlackOnlyDark => 'ダークテーマでのみ有効です';

  @override
  String get colorSurface => '背景';

  @override
  String get colorSurfaceContainer => 'カード背景';

  @override
  String get colorOnSurface => 'メインテキスト';

  @override
  String get colorOnSurfaceVariant => 'サブテキスト';

  @override
  String get colorPrimary => 'メインアクセント';

  @override
  String get colorOnPrimary => 'アクセント上のテキスト';

  @override
  String get colorOutline => '境界線 / 区切り線';

  @override
  String get colorSnackbarBackground => 'スナックバーの背景';

  @override
  String adjustColorTitle(String colorLabel) {
    return '$colorLabelを調整';
  }

  @override
  String get apply => '適用';

  @override
  String get imageReadFailedUnsupportedFormat =>
      '画像を読み込めませんでした。対応していない形式の可能性があります。';

  @override
  String get enterName => '名前を入力してください';

  @override
  String get collectionAdded => 'コレクションに追加しました';

  @override
  String get alreadyInCollection => 'すでにコレクションに登録されています';

  @override
  String get dataDeleted => 'データを完全に削除しました';

  @override
  String get deleteFailed => '削除に失敗しました';

  @override
  String get photoCroppedRememberSave => '写真を切り抜きました。忘れずに保存してください。';

  @override
  String get detailSaved => '詳細を保存しました';

  @override
  String get saveFailedDuplicateName => '保存に失敗しました。同じ名前がすでに存在する可能性があります。';

  @override
  String get dataNotFound => 'データが見つかりません';

  @override
  String get attrCensored => 'モザイクあり';

  @override
  String get attrUncensored => '無修正';

  @override
  String get attrWestern => '洋物';

  @override
  String get attrFc2 => 'FC2';

  @override
  String get attrDomestic => '国内';

  @override
  String get filterAll => 'すべて';

  @override
  String get imageCropLoadErrorTitle => '画像の読み込みエラー';

  @override
  String get close => '閉じる';

  @override
  String get imageDecodeFailed => '画像のデコードに失敗しました';

  @override
  String get cropZoom => '拡大・縮小';

  @override
  String get cropPanX => '水平方向に移動';

  @override
  String get cropPanY => '垂直方向に移動';

  @override
  String get confirmCrop => '切り抜く';

  @override
  String get language => '言語';

  @override
  String get worksPageSize => '作品ページのサイズ';

  @override
  String get worksPageSizeSmall => '小';

  @override
  String get worksPageSizeLarge => '大';

  @override
  String get traditionalChineseTaiwan => '繁体字中国語（台湾）';

  @override
  String get english => '英語';

  @override
  String get simplifiedChinese => '簡体字中国語';

  @override
  String get japanese => '日本語';

  @override
  String get works => '作品';

  @override
  String get relatedActresses => '関連出演者';

  @override
  String get workStorageTitle => '作品保存記録';

  @override
  String get workStorageSaved => '保存済み';

  @override
  String get workStorageNotSaved => '未保存';

  @override
  String get workStorageQuality => '画質';

  @override
  String get workStorageFrameRate => 'フレームレート';

  @override
  String get workStorageSave => '保存';

  @override
  String get workStorageUpdated => '作品保存記録を更新しました';

  @override
  String get workStorageUpdateFailed => '作品保存記録の更新に失敗しました';

  @override
  String get workStorageFilterStored => '保存済み';

  @override
  String get workStorageFilterNotStored => '未保存';

  @override
  String get workStorageFilterAll => 'すべて';

  @override
  String get aliases => '別名';

  @override
  String get manageAliases => '別名を管理';

  @override
  String get aliasInputHint => '別名を入力';

  @override
  String get addAlias => '別名を追加';

  @override
  String get saveAliases => '別名を保存';

  @override
  String get noAliases => '別名はありません';

  @override
  String get deleteWorks => '作品を削除';

  @override
  String get deleteWorksTitle => '選択した作品を削除しますか？';

  @override
  String get deleteWorksWarning => '選択した作品を全体から削除し、他の女優からの作品リンクも削除します。';

  @override
  String worksDeleted(int count) {
    return '$count 件の作品を削除しました';
  }

  @override
  String get loadFailedGeneric => '読み込みに失敗しました';

  @override
  String actressWorksTitle(String actressName) {
    return '$actressNameの出演作品';
  }

  @override
  String get searchWorks => '作品を検索';

  @override
  String get workCodeSearchHint => '品番を入力して検索...';

  @override
  String get noMatchingWorks => '一致する作品がありません';

  @override
  String get scrapeWorks => '作品情報を取得';

  @override
  String get scrapeSettings => '取得設定';

  @override
  String get scrapeExistingData => '既存データの処理';

  @override
  String get scrapeUpdateAll => '既存データも更新';

  @override
  String get scrapeAutomaticDerivedFilter => '再編集・合集作品を自動除外';

  @override
  String get scrapeAutomaticDerivedFilterDescription =>
      '出典の系譜と作品語義だけで判定し、不明な作品は保持します。';

  @override
  String get scrapeAdvancedRules => '詳細ルール';

  @override
  String get scrapeAdvancedRulesDescription =>
      '完全な作品番号またはPrefixを入力（例：KCKC、KCKC-212）。';

  @override
  String get scrapeExactAllows => '番号／Prefixで許可';

  @override
  String get scrapeExactDenies => '番号／Prefixで除外';

  @override
  String get scrapeRuleHint => '作品番号またはPrefixを入力';

  @override
  String get scrapeNoRules => 'ルールは未設定です';

  @override
  String get syncActressDetails => 'プロフィール詳細を同期';

  @override
  String get replaceActressImage => '女優画像を差し替える';

  @override
  String get scrapeAvatarUnavailable => '利用可能な女優画像が見つかりませんでした。';

  @override
  String get scrapeAvatarFailed => '女優画像の差し替えに失敗したため、元の画像を保持しました。';

  @override
  String get fillMissingOnly => '再取得時は未入力の情報のみ補完';

  @override
  String get startScrape => '取得を開始';

  @override
  String get noWorks => '作品はまだありません';

  @override
  String durationMinutes(int minutes) {
    return '$minutes分';
  }

  @override
  String get studio => 'メーカー';

  @override
  String get publisher => 'レーベル';

  @override
  String get series => 'シリーズ';

  @override
  String scrapeComplete(int saved, int excluded, int failed) {
    return '取得完了: 保存 $saved件、除外 $excluded件、失敗 $failed件';
  }

  @override
  String scrapeCancelled(int saved, int excluded, int failed) {
    return '取得をキャンセルしました: 保存 $saved件、除外 $excluded件、失敗 $failed件';
  }

  @override
  String get scrapeFailed => '取得に失敗しました。もう一度お試しください。';

  @override
  String get scrapePhaseCollecting => '作品一覧を取得中';

  @override
  String get scrapePhaseSyncingActress => '女優情報を同期中';

  @override
  String get scrapePhaseFetchingDetails => '作品詳細を取得中';

  @override
  String get scrapePhaseResolvingWorks => '重複除去した作品を整理中';

  @override
  String get scrapePhaseSavingWorks => '作品を保存して画像をダウンロード中';

  @override
  String get scrapePhaseCompleted => '取得完了';

  @override
  String get scrapeSyncingTitle => 'スクレイピング中';

  @override
  String get scrapeSyncCompleted => 'スクレイピング完了';

  @override
  String get scrapeSyncPartial => 'スクレイピング完了（一部失敗）';

  @override
  String get scrapeSyncFailed => 'スクレイピングに失敗しました';

  @override
  String get scrapeSyncStopped => 'スクレイピングを停止しました';

  @override
  String get scrapeDetailsSection => '詳細情報';

  @override
  String get scrapeWorksSection => '作品';

  @override
  String get scrapeDownloadSection => 'ダウンロード';

  @override
  String scrapeCurrentWork(String code) {
    return '処理中：$code';
  }

  @override
  String get scrapeImagesLabel => '作品画像';

  @override
  String get scrapeSavedCount => '保存';

  @override
  String get scrapeExcludedCount => '除外';

  @override
  String get scrapeFailedCount => '失敗';

  @override
  String get scrapeStatusWaiting => '待機中';

  @override
  String get scrapeStatusSyncing => 'スクレイピング中';

  @override
  String get scrapeStatusCompleted => '完了';

  @override
  String get scrapeStatusPartial => '一部完了';

  @override
  String get scrapeStatusFailed => '失敗';

  @override
  String get scrapeStatusCancelled => '停止済み';

  @override
  String get scrapeStatusNoNewWorks => '完了（新しい作品なし）';

  @override
  String get scrapeStatusUnavailable => '利用不可';

  @override
  String get scrapeStatusBlocked => 'ページがブロックされました';

  @override
  String get scrapeStatusRateLimited => 'レート制限';

  @override
  String get scrapeStatusTimedOut => 'タイムアウト';

  @override
  String get stopScrape => '停止';

  @override
  String scrapeProgressSummary(int saved, int excluded, int failed) {
    return '保存 $saved件、除外 $excluded件、失敗 $failed件';
  }

  @override
  String scrapeFailedWorksTitle(int count) {
    return '失敗した作品（$count件）';
  }

  @override
  String scrapeImageFailuresTitle(int count) {
    return '画像ダウンロード失敗（$count件）';
  }

  @override
  String get scrapeFailureDetailsUnavailable => '利用可能な作品詳細を取得できませんでした';

  @override
  String get scrapeFailureDetailCodeMismatch => '作品詳細の番号が作品と一致しません';

  @override
  String get scrapeFailureInvalidCode => '作品番号を正規化できませんでした';

  @override
  String get scrapeFailurePerformerCountUnavailable => '出演者数を取得できませんでした';

  @override
  String get scrapeFailureDatabaseSave => '作品データの保存に失敗しました';

  @override
  String get scrapeImageFailureCard => 'ジャケット画像';

  @override
  String get scrapeImageFailureDetail => '詳細画像';

  @override
  String get scrapeImageFailureBoth => 'ジャケットと詳細画像';

  @override
  String get javBusVerificationTitle => 'JavBus の確認';

  @override
  String get javBusVerificationInstructions =>
      'JavBus では地域別の年齢確認を手動で行う必要があります。同じ安全なセッションで取得を続けるには、すべての質問に回答してください。';

  @override
  String get javBusVerificationSubmit => '確認を送信';

  @override
  String get settingsDataTransferTitle => 'データの入出力';

  @override
  String get settingsDataTransferSubtitle =>
      '女優、作品、詳細情報、画像を ZIP でバックアップまたは復元します。';

  @override
  String get dataTransferExportTitle => 'データをエクスポート';

  @override
  String get dataTransferExportSubtitle => '完全な ZIP バックアップの保存先を選択します。';

  @override
  String get dataTransferImportTitle => 'データをインポート';

  @override
  String get dataTransferImportSubtitle => 'ZIP バックアップを選択してすぐに復元します。';

  @override
  String get dataTransferPreparing => 'データを準備中…';

  @override
  String get dataTransferDuplicateProgress => '重複する女優の選択を待っています…';

  @override
  String get dataTransferWriting => 'データと画像を書き込み中…';

  @override
  String get dataTransferExportSuccess => 'エクスポートが完了しました。';

  @override
  String dataTransferExportSuccessWithSkippedImages(int count) {
    return 'エクスポート完了。使用できない画像を $count 枚スキップしました。';
  }

  @override
  String get dataTransferImportSuccess => 'インポートが完了しました。データをすぐに使用できます。';

  @override
  String get dataTransferDuplicateTitle => '重複する女優が見つかりました';

  @override
  String get dataTransferDuplicateExplanation =>
      '画像と作品数を比較して、使用する女優の詳細情報を選択してください。既存の作品と関連付けは保持されます。';

  @override
  String get dataTransferKeepExisting => '現在の詳細を保持';

  @override
  String get dataTransferUseImported => 'インポートした詳細を使用';

  @override
  String get dataTransferContinue => '続行';

  @override
  String dataTransferWorkCount(int count) {
    return '作品数: $count';
  }

  @override
  String get dataTransferArchiveTooLarge => 'ZIP が対応サイズを超えています。';

  @override
  String get dataTransferUnsafeArchive => 'ZIP に安全でないファイルパスが含まれています。';

  @override
  String get dataTransferCorruptArchive => 'ZIP が壊れているか、画像のチェックサムに失敗しました。';

  @override
  String get dataTransferFileUnreadable => '選択したファイルを読み取れませんでした。';

  @override
  String get dataTransferActorNameConflict => 'インポートした女優名が別のデータと競合しています。';

  @override
  String get dataTransferBusy => '別のデータ転送が進行中です。';

  @override
  String get dataTransferFailed => 'データ転送に失敗しました。既存データは変更されていません。';

  @override
  String get otherSettings => 'その他';

  @override
  String get about => '概要';

  @override
  String get github => 'github';

  @override
  String get feedbackSuggestions => 'フィードバック';

  @override
  String get scrapeSources => '取得元';

  @override
  String get scrapeSourceDetailsTitle => '女優詳細情報の取得元';

  @override
  String get scrapeSourceWorksTitle => '作品の取得元';

  @override
  String get scrapeSourcePriorityHint => '取得元を選択し、ドラッグして優先順位を変更';

  @override
  String get scrapeSourceAliasTitle => '女優別名の取得元';

  @override
  String get scrapeSourceMinnanoAv => 'みんなのAV';

  @override
  String get scrapeSourceJavBus => 'JavBus';

  @override
  String get scrapeSourceAvBase => 'AvBase';

  @override
  String get scrapeSourceAvWiki => 'AV-Wiki';

  @override
  String get scrapeSourceAll => 'すべての取得元（品番で統合・重複排除）';

  @override
  String get scrapeSourceSaveFailed => '取得元の設定を保存できませんでした。';

  @override
  String get scrapeSourceConnectionTitle => '取得元の接続状態';

  @override
  String get scrapeSourceConnectionSubtitle => '追加済みの取得元を確認し、ここで接続テストと確認を行います。';

  @override
  String get scrapeSourceRetest => '接続を再テスト';

  @override
  String get scrapeSourceTesting => 'テスト中…';

  @override
  String get scrapeSourceNotTested => '未テスト';

  @override
  String get scrapeSourceConnected => '接続成功';

  @override
  String get scrapeSourceConnectionFailed => '接続失敗';

  @override
  String get scrapeSourceVerificationRequired => '確認が必要';

  @override
  String get scrapeAliases => '別名を取得';

  @override
  String get scrapeAliasesDescription =>
      '別名の取得元で見つかった名前を、現在の名前を除いて女優の別名に保存します。';

  @override
  String get scrapePartial => '一部の取得元または作品を処理できませんでした。';

  @override
  String get scrapeZeroResults => '新しい作品は見つかりませんでした。';

  @override
  String get softwareUpdate => 'ソフトウェア更新';

  @override
  String get softwareUpdateDescription => 'AVACA の最新バージョンを確認してインストールします。';

  @override
  String get currentVersion => '現在のバージョン';

  @override
  String get latestVersion => '最新バージョン';

  @override
  String get autoCheckUpdates => '更新を自動的に確認';

  @override
  String get checkForUpdates => '更新を確認';

  @override
  String get checkingForUpdates => '更新を確認中…';

  @override
  String get downloadingUpdate => '更新をダウンロード中…';

  @override
  String get verifyingUpdate => '更新を検証中…';

  @override
  String get installingUpdate => 'インストールを開始中…';

  @override
  String get updateAvailable => '新しいバージョンがあります';

  @override
  String get upToDate => 'AVACA は最新です。';

  @override
  String get updateNow => '今すぐ更新';

  @override
  String get updateLater => '後で';

  @override
  String get updateUnavailable => 'このデバイスに対応する更新ファイルがありません。';

  @override
  String get updateCheckFailed => '更新を確認できませんでした。後でもう一度お試しください。';

  @override
  String get updateDownloadFailed => '更新のダウンロードに失敗しました。既存データは変更されていません。';

  @override
  String get updateIntegrityFailed => '更新ファイルの検証に失敗したため、更新を停止しました。';

  @override
  String get updateNotSupported => 'このデバイスでは自動更新に対応していません。';

  @override
  String get updateInstallPermissionRequired =>
      '先に AVACA に提供元不明のアプリのインストールを許可してください。';

  @override
  String get updatePortableFolderNotWritable =>
      'portable アプリフォルダーに書き込めないため、更新を停止しました。';

  @override
  String get updateInstallerFailed => '更新プログラムを開始できませんでした。現在のバージョンを保持しています。';

  @override
  String get updateDataPreserved => 'データと設定は保持されます。';

  @override
  String get prefixRouteRulesTitle => '作品画像 Prefix ルート規則';

  @override
  String get prefixRouteRulesSubtitle => '検証済みダウンロードから学習した画像 family を管理します。';

  @override
  String prefixRouteRuleCount(int count) {
    return '学習済み Prefix 規則 $count 件';
  }

  @override
  String get prefixRouteSearchHint => 'Prefix を検索';

  @override
  String get prefixRouteNoRules => '学習済みの Prefix ルート規則はありません。';

  @override
  String get prefixRouteNoSearchResults => '一致する Prefix 規則はありません。';

  @override
  String get prefixRouteBestFamily => '優先 family';

  @override
  String get prefixRouteNotAvailable => 'なし';

  @override
  String get prefixRouteCandidates => '既知の候補ルート';

  @override
  String prefixRouteSuccessCount(int count) {
    return '成功: $count 回';
  }

  @override
  String prefixRouteFailureCount(int count) {
    return '失敗: $count 回';
  }

  @override
  String prefixRouteLastSuccess(String time) {
    return '最終成功: $time';
  }

  @override
  String prefixRouteLastFailure(String time) {
    return '最終失敗: $time';
  }

  @override
  String get prefixRouteStatusVerified => '検証済み';

  @override
  String get prefixRouteStatusExceptions => '例外あり';

  @override
  String get prefixRouteStatusPending => '再検証待ち';

  @override
  String get prefixRouteStatusProbeFailed => '探測失敗';

  @override
  String get prefixRouteManualOverride => '手動指定 route';

  @override
  String get prefixRouteAutomatic => '自動';

  @override
  String get prefixRouteAutomaticDescription =>
      '学習済み候補を優先し、必要な場合だけ対応 family を探測します。';

  @override
  String get prefixRouteManualDescription => 'この family を最初に試します。学習統計は保持されます。';

  @override
  String get prefixRouteFamilyDmmStandard => 'DMM Standard';

  @override
  String get prefixRouteFamilyDmmLeadingOne => 'DMM Leading One';

  @override
  String get prefixRouteFamilyDmmH1711 => 'DMM H1711';

  @override
  String get prefixRouteFamilyDmmRebeccaH346 => 'DMM Rebecca H346';

  @override
  String get prefixRouteFamilyMgstagePrestige => 'MGStage Prestige';

  @override
  String get prefixRouteFamilyMgstageSeikyouiku => 'MGStage Seikyouiku';

  @override
  String get prefixRouteExport => '規則をエクスポート';

  @override
  String get prefixRouteImport => '規則をインポート';

  @override
  String get prefixRouteExportDialogTitle => 'Prefix 規則をエクスポート';

  @override
  String get prefixRouteExportRulesOnly => '規則のみ';

  @override
  String get prefixRouteExportRulesOnlyDescription =>
      '検証統計を含めず family だけを出力します。';

  @override
  String get prefixRouteExportWithStatistics => '規則と統計';

  @override
  String get prefixRouteExportWithStatisticsDescription => '成功、失敗、時刻を含めます。';

  @override
  String get prefixRouteExportSuccess => 'Prefix 規則をエクスポートしました。';

  @override
  String get prefixRouteImportDialogTitle => 'Prefix 規則をインポート';

  @override
  String prefixRouteImportPreview(int rules, int conflicts) {
    return '$rules 件の規則が見つかりました。手動指定の競合: $conflicts 件。';
  }

  @override
  String get prefixRouteImportMerge => '統合';

  @override
  String get prefixRouteImportReplace => '置換';

  @override
  String prefixRouteImportSuccess(int count) {
    return 'Prefix 規則を $count 件インポートしました。';
  }

  @override
  String get prefixRouteOperationFailed =>
      'Prefix ルート操作に失敗しました。既存の規則は変更されていません。';

  @override
  String get prefixRouteLoadFailed => 'Prefix ルート規則を読み込めませんでした。';

  @override
  String get prefixRouteClearAutomatic => '自動学習をクリア';

  @override
  String get prefixRouteClearAutomaticTitle => '自動学習をクリアしますか？';

  @override
  String get prefixRouteClearAutomaticMessage =>
      '学習候補と統計をクリアします。手動指定とダウンロード済み画像は保持されます。';

  @override
  String get prefixRouteClearAutomaticSuccess => 'Prefix の自動学習をクリアしました。';

  @override
  String get prefixRouteReset => 'この Prefix の学習をリセット';

  @override
  String get prefixRouteResetTitle => 'この Prefix の学習をリセットしますか？';

  @override
  String get prefixRouteResetMessage => '候補と統計をクリアします。手動指定がある場合は保持されます。';

  @override
  String get prefixRouteForget => 'この Prefix 規則を削除';

  @override
  String get prefixRouteForgetTitle => 'この Prefix 規則を削除しますか？';

  @override
  String get prefixRouteForgetMessage =>
      'この Prefix の学習データと手動指定を削除します。ダウンロード済み画像と作品データは変更されません。';

  @override
  String get workFieldProvenanceTitle => '項目ソース';

  @override
  String get workFieldProvenanceSource => 'ソース';

  @override
  String get workFieldProvenanceObservedAt => '観測時刻';

  @override
  String get workFieldProvenanceUnknown => '不明なソース';

  @override
  String get dataHealthTitle => 'データ健全性';

  @override
  String get dataHealthSubtitle =>
      '件数、不足している作品項目や画像、項目ソース、保留中の削除、取得元エラーを確認します。';

  @override
  String dataHealthSectionUnavailable(String section) {
    return 'このセクションを読み込めませんでした: $section';
  }

  @override
  String get dataHealthRefresh => '更新';

  @override
  String get dataHealthActresses => '女優';

  @override
  String get dataHealthWorks => '作品';

  @override
  String get dataHealthStored => '保存済み動画';

  @override
  String get dataHealthNotStored => '未保存';

  @override
  String get dataHealthMetadataIssues => '不足している作品項目';

  @override
  String get dataHealthMissingImages => '不足している画像参照';

  @override
  String get dataHealthMissingProvenance => '不足している項目ソース';

  @override
  String get dataHealthPendingDeletions => '保留中のファイル削除';

  @override
  String get dataHealthJobStates => 'スクレイプジョブ状態';

  @override
  String get dataHealthSourceErrors => '過去 7 日間のソースエラー';

  @override
  String get scrapeJobsTitle => 'スクレイプジョブ';

  @override
  String get scrapeJobsEmpty => 'スクレイプジョブはありません。';

  @override
  String scrapeJobsSelectedCount(int count) {
    return '$count 件を選択中';
  }

  @override
  String get scrapeJobsDelete => '削除';

  @override
  String get scrapeJobsDeleteTitle => '選択したスクレイプジョブを削除しますか？';

  @override
  String scrapeJobsDeleteMessage(int count) {
    return '$count 件の完了したスクレイプジョブの記録を削除しますか？作品、女優、設定は変更されません。';
  }

  @override
  String get scrapeJobsDeleteActive =>
      '実行中または待機中のジョブは削除できません。完了したジョブだけを選択してください。';

  @override
  String scrapeJobsDeleted(int count) {
    return '$count 件のスクレイプジョブを削除しました。';
  }

  @override
  String get scrapeJobsDeleteFailed => 'スクレイプジョブの記録を削除できませんでした。';

  @override
  String get scrapeJobDetailTitle => 'スクレイプジョブ詳細';

  @override
  String get scrapeJobPause => '一時停止';

  @override
  String get scrapeJobResume => '再開';

  @override
  String get scrapeJobCancel => 'キャンセル';

  @override
  String get scrapeJobRetryFailed => '失敗した作品だけ再試行';

  @override
  String get scrapeJobEvents => 'イベント履歴';

  @override
  String get scrapeJobDiagnostics => '刮削診断';

  @override
  String get scrapeJobItems => '作品チェックポイント';

  @override
  String get scrapeJobNoEvents => 'イベントはまだありません。';

  @override
  String get scrapeJobNoItems => '作品チェックポイントはまだありません。';

  @override
  String get scrapeJobFilterAll => 'すべて';

  @override
  String get scrapeJobFilterReview => '要確認';

  @override
  String get scrapeJobFilterKeep => '保持';

  @override
  String get scrapeJobFilterExclude => '除外';

  @override
  String get scrapeJobFilterFailed => '失敗';

  @override
  String get scrapeJobNoFilteredItems => 'このフィルターに一致するチェックポイントはありません。';

  @override
  String get scrapeJobStateReview => '要確認';

  @override
  String get scrapeJobStateQueued => '待機中';

  @override
  String get scrapeJobStateRunning => '実行中';

  @override
  String get scrapeJobStatePaused => '一時停止';

  @override
  String get scrapeJobStateWaiting => '認証待ち';

  @override
  String get scrapeJobStateSucceeded => '成功';

  @override
  String get scrapeJobStatePartial => '一部完了';

  @override
  String get scrapeJobStateFailed => '失敗';

  @override
  String get scrapeJobStateCancelled => 'キャンセル済み';

  @override
  String get scrapeJobStateExcluded => '除外';

  @override
  String scrapeJobCollectionSummary(int raw, int unique, int duplicates) {
    return '取得 $raw、重複除外後 $unique、重複 $duplicates';
  }

  @override
  String scrapeJobDetailProgress(int current, int total) {
    return '詳細 $current/$total';
  }

  @override
  String scrapeJobTerminalProgress(
    int processed,
    int total,
    int saved,
    int excluded,
    int failed,
  ) {
    return '処理 $processed/$total、保存 $saved、除外 $excluded、失敗 $failed';
  }

  @override
  String scrapeJobCandidateSummary(int count, int duplicates) {
    return '候補作品 $count、コレクション重複 $duplicates';
  }

  @override
  String scrapeJobSupplementalEvidence(int current, int total) {
    return '補足証拠 $current/$total';
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
    return '処理 $processed/$total、保持 $keep、要確認 $review、除外 $excluded、失敗 $failed';
  }

  @override
  String scrapeJobRulesVersion(String version) {
    return 'ルールバージョン：$version';
  }

  @override
  String get settingsDataHealthTitle => 'データ健全性';

  @override
  String get settingsDataHealthSubtitle => 'データ完全性とスクレイプの可観測性を確認します。';

  @override
  String get settingsScrapeJobsTitle => 'スクレイプジョブ';

  @override
  String get settingsScrapeJobsSubtitle => 'キュー、復旧、一時停止、失敗再試行を確認します。';
}

/// The translations for Japanese, as used in Japan (`ja_JP`).
class AppLocalizationsJaJp extends AppLocalizationsJa {
  AppLocalizationsJaJp() : super('ja_JP');

  @override
  String get addTitle => 'コレクションに追加';

  @override
  String get noPhoto => '写真なし';

  @override
  String get selectPhoto => '写真を選択';

  @override
  String get removePhoto => '写真を削除';

  @override
  String get actressNameRequired => '女優名（必須）';

  @override
  String get saveCard => 'カードを保存';

  @override
  String get changePhoto => '写真を変更';

  @override
  String get deletePhoto => '写真を削除';

  @override
  String get noAttributesSet => '属性未設定';

  @override
  String get bodyInfo => '詳細情報';

  @override
  String get heightCm => '身長（cm）';

  @override
  String get weightKg => '体重（kg）';

  @override
  String get cup => 'カップ';

  @override
  String get measurements => 'スリーサイズ';

  @override
  String get privateNotes => '非公開メモ';

  @override
  String get noNotes => 'メモなし';

  @override
  String get confirmDeleteTitle => '削除しますか？';

  @override
  String get deleteWarningWithPhoto => 'この操作は元に戻せません。写真ファイルも削除されます。';

  @override
  String get cancel => 'キャンセル';

  @override
  String get reload => '再読み込み';

  @override
  String get confirmDelete => '削除';

  @override
  String get edit => '編集';

  @override
  String get delete => '削除';

  @override
  String get appTitle => 'AVACA';

  @override
  String get search => '検索';

  @override
  String get filterAndSort => '絞り込み・並べ替え';

  @override
  String get filterSection => '絞り込み';

  @override
  String get sortSection => '並べ替え';

  @override
  String get sortCreatedDesc => '追加日（新しい順）';

  @override
  String get sortCreatedAsc => '追加日（古い順）';

  @override
  String get sortModifiedDesc => '更新日（新しい順）';

  @override
  String get sortModifiedAsc => '更新日（古い順）';

  @override
  String get sortAgeAsc => '年齢（低い順）';

  @override
  String get sortAgeDesc => '年齢（高い順）';

  @override
  String get birthDate => '生年月日';

  @override
  String get setBirthDate => '生年月日を設定';

  @override
  String get clear => 'クリア';

  @override
  String get done => '完了';

  @override
  String ageWithBirthDate(int age, String date) {
    return '$age歳  $date';
  }

  @override
  String get add => '追加';

  @override
  String get settings => '設定';

  @override
  String get themeAndColors => 'テーマと色';

  @override
  String get interfaceSettings => 'インターフェース';

  @override
  String loadFailed(String error) {
    return '読み込みに失敗しました: $error';
  }

  @override
  String get noData => 'データなし';

  @override
  String get searchNameHint => '名前を入力してすばやく検索...';

  @override
  String get applySettings => '設定を適用';

  @override
  String get themeMode => 'テーマモード';

  @override
  String get followSystem => 'システム設定に従う';

  @override
  String get lightTheme => 'ライト';

  @override
  String get darkTheme => 'ダーク';

  @override
  String get customTheme => 'カスタムテーマ';

  @override
  String get pureBlackAmoled => 'ピュアブラック AMOLED';

  @override
  String get pureBlackOnlyDark => 'ダークテーマでのみ有効です';

  @override
  String get colorSurface => '背景';

  @override
  String get colorSurfaceContainer => 'カード背景';

  @override
  String get colorOnSurface => 'メインテキスト';

  @override
  String get colorOnSurfaceVariant => 'サブテキスト';

  @override
  String get colorPrimary => 'メインアクセント';

  @override
  String get colorOnPrimary => 'アクセント上のテキスト';

  @override
  String get colorOutline => '境界線 / 区切り線';

  @override
  String get colorSnackbarBackground => 'スナックバーの背景';

  @override
  String adjustColorTitle(String colorLabel) {
    return '$colorLabelを調整';
  }

  @override
  String get apply => '適用';

  @override
  String get imageReadFailedUnsupportedFormat =>
      '画像を読み込めませんでした。対応していない形式の可能性があります。';

  @override
  String get enterName => '名前を入力してください';

  @override
  String get collectionAdded => 'コレクションに追加しました';

  @override
  String get alreadyInCollection => 'すでにコレクションに登録されています';

  @override
  String get dataDeleted => 'データを完全に削除しました';

  @override
  String get deleteFailed => '削除に失敗しました';

  @override
  String get photoCroppedRememberSave => '写真を切り抜きました。忘れずに保存してください。';

  @override
  String get detailSaved => '詳細を保存しました';

  @override
  String get saveFailedDuplicateName => '保存に失敗しました。同じ名前がすでに存在する可能性があります。';

  @override
  String get dataNotFound => 'データが見つかりません';

  @override
  String get attrCensored => 'モザイクあり';

  @override
  String get attrUncensored => '無修正';

  @override
  String get attrWestern => '洋物';

  @override
  String get attrFc2 => 'FC2';

  @override
  String get attrDomestic => '国内';

  @override
  String get filterAll => 'すべて';

  @override
  String get imageCropLoadErrorTitle => '画像の読み込みエラー';

  @override
  String get close => '閉じる';

  @override
  String get imageDecodeFailed => '画像のデコードに失敗しました';

  @override
  String get cropZoom => '拡大・縮小';

  @override
  String get cropPanX => '水平方向に移動';

  @override
  String get cropPanY => '垂直方向に移動';

  @override
  String get confirmCrop => '切り抜く';

  @override
  String get language => '言語';

  @override
  String get worksPageSize => '作品ページのサイズ';

  @override
  String get worksPageSizeSmall => '小';

  @override
  String get worksPageSizeLarge => '大';

  @override
  String get traditionalChineseTaiwan => '繁体字中国語（台湾）';

  @override
  String get english => '英語';

  @override
  String get simplifiedChinese => '簡体字中国語';

  @override
  String get japanese => '日本語';

  @override
  String get works => '作品';

  @override
  String get relatedActresses => '関連出演者';

  @override
  String get workStorageTitle => '作品保存記録';

  @override
  String get workStorageSaved => '保存済み';

  @override
  String get workStorageNotSaved => '未保存';

  @override
  String get workStorageQuality => '画質';

  @override
  String get workStorageFrameRate => 'フレームレート';

  @override
  String get workStorageSave => '保存';

  @override
  String get workStorageUpdated => '作品保存記録を更新しました';

  @override
  String get workStorageUpdateFailed => '作品保存記録の更新に失敗しました';

  @override
  String get workStorageFilterStored => '保存済み';

  @override
  String get workStorageFilterNotStored => '未保存';

  @override
  String get workStorageFilterAll => 'すべて';

  @override
  String get aliases => '別名';

  @override
  String get manageAliases => '別名を管理';

  @override
  String get aliasInputHint => '別名を入力';

  @override
  String get addAlias => '別名を追加';

  @override
  String get saveAliases => '別名を保存';

  @override
  String get noAliases => '別名はありません';

  @override
  String get deleteWorks => '作品を削除';

  @override
  String get deleteWorksTitle => '選択した作品を削除しますか？';

  @override
  String get deleteWorksWarning => '選択した作品を全体から削除し、他の女優からの作品リンクも削除します。';

  @override
  String worksDeleted(int count) {
    return '$count 件の作品を削除しました';
  }

  @override
  String get loadFailedGeneric => '読み込みに失敗しました';

  @override
  String actressWorksTitle(String actressName) {
    return '$actressNameの出演作品';
  }

  @override
  String get searchWorks => '作品を検索';

  @override
  String get workCodeSearchHint => '品番を入力して検索...';

  @override
  String get noMatchingWorks => '一致する作品がありません';

  @override
  String get scrapeWorks => '作品情報を取得';

  @override
  String get scrapeSettings => '取得設定';

  @override
  String get scrapeExistingData => '既存データの処理';

  @override
  String get scrapeUpdateAll => '既存データも更新';

  @override
  String get scrapeAutomaticDerivedFilter => '再編集・合集作品を自動除外';

  @override
  String get scrapeAutomaticDerivedFilterDescription =>
      '出典の系譜と作品語義だけで判定し、不明な作品は保持します。';

  @override
  String get scrapeAdvancedRules => '詳細ルール';

  @override
  String get scrapeAdvancedRulesDescription =>
      '完全な作品番号またはPrefixを入力（例：KCKC、KCKC-212）。';

  @override
  String get scrapeExactAllows => '番号／Prefixで許可';

  @override
  String get scrapeExactDenies => '番号／Prefixで除外';

  @override
  String get scrapeRuleHint => '作品番号またはPrefixを入力';

  @override
  String get scrapeNoRules => 'ルールは未設定です';

  @override
  String get syncActressDetails => 'プロフィール詳細を同期';

  @override
  String get replaceActressImage => '女優画像を差し替える';

  @override
  String get scrapeAvatarUnavailable => '利用可能な女優画像が見つかりませんでした。';

  @override
  String get scrapeAvatarFailed => '女優画像の差し替えに失敗したため、元の画像を保持しました。';

  @override
  String get fillMissingOnly => '再取得時は未入力の情報のみ補完';

  @override
  String get startScrape => '取得を開始';

  @override
  String get noWorks => '作品はまだありません';

  @override
  String durationMinutes(int minutes) {
    return '$minutes分';
  }

  @override
  String get studio => 'メーカー';

  @override
  String get publisher => 'レーベル';

  @override
  String get series => 'シリーズ';

  @override
  String scrapeComplete(int saved, int excluded, int failed) {
    return '取得完了: 保存 $saved件、除外 $excluded件、失敗 $failed件';
  }

  @override
  String scrapeCancelled(int saved, int excluded, int failed) {
    return '取得をキャンセルしました: 保存 $saved件、除外 $excluded件、失敗 $failed件';
  }

  @override
  String get scrapeFailed => '取得に失敗しました。もう一度お試しください。';

  @override
  String get scrapePhaseCollecting => '作品一覧を取得中';

  @override
  String get scrapePhaseSyncingActress => '女優情報を同期中';

  @override
  String get scrapePhaseFetchingDetails => '作品詳細を取得中';

  @override
  String get scrapePhaseResolvingWorks => '重複除去した作品を整理中';

  @override
  String get scrapePhaseSavingWorks => '作品を保存して画像をダウンロード中';

  @override
  String get scrapePhaseCompleted => '取得完了';

  @override
  String get scrapeSyncingTitle => 'スクレイピング中';

  @override
  String get scrapeSyncCompleted => 'スクレイピング完了';

  @override
  String get scrapeSyncPartial => 'スクレイピング完了（一部失敗）';

  @override
  String get scrapeSyncFailed => 'スクレイピングに失敗しました';

  @override
  String get scrapeSyncStopped => 'スクレイピングを停止しました';

  @override
  String get scrapeDetailsSection => '詳細情報';

  @override
  String get scrapeWorksSection => '作品';

  @override
  String get scrapeDownloadSection => 'ダウンロード';

  @override
  String scrapeCurrentWork(String code) {
    return '処理中：$code';
  }

  @override
  String get scrapeImagesLabel => '作品画像';

  @override
  String get scrapeSavedCount => '保存';

  @override
  String get scrapeExcludedCount => '除外';

  @override
  String get scrapeFailedCount => '失敗';

  @override
  String get scrapeStatusWaiting => '待機中';

  @override
  String get scrapeStatusSyncing => 'スクレイピング中';

  @override
  String get scrapeStatusCompleted => '完了';

  @override
  String get scrapeStatusPartial => '一部完了';

  @override
  String get scrapeStatusFailed => '失敗';

  @override
  String get scrapeStatusCancelled => '停止済み';

  @override
  String get scrapeStatusNoNewWorks => '完了（新しい作品なし）';

  @override
  String get scrapeStatusUnavailable => '利用不可';

  @override
  String get scrapeStatusBlocked => 'ページがブロックされました';

  @override
  String get scrapeStatusRateLimited => 'レート制限';

  @override
  String get scrapeStatusTimedOut => 'タイムアウト';

  @override
  String get stopScrape => '停止';

  @override
  String scrapeProgressSummary(int saved, int excluded, int failed) {
    return '保存 $saved件、除外 $excluded件、失敗 $failed件';
  }

  @override
  String scrapeFailedWorksTitle(int count) {
    return '失敗した作品（$count件）';
  }

  @override
  String scrapeImageFailuresTitle(int count) {
    return '画像ダウンロード失敗（$count件）';
  }

  @override
  String get scrapeFailureDetailsUnavailable => '利用可能な作品詳細を取得できませんでした';

  @override
  String get scrapeFailureDetailCodeMismatch => '作品詳細の番号が作品と一致しません';

  @override
  String get scrapeFailureInvalidCode => '作品番号を正規化できませんでした';

  @override
  String get scrapeFailurePerformerCountUnavailable => '出演者数を取得できませんでした';

  @override
  String get scrapeFailureDatabaseSave => '作品データの保存に失敗しました';

  @override
  String get scrapeImageFailureCard => 'ジャケット画像';

  @override
  String get scrapeImageFailureDetail => '詳細画像';

  @override
  String get scrapeImageFailureBoth => 'ジャケットと詳細画像';

  @override
  String get javBusVerificationTitle => 'JavBus の確認';

  @override
  String get javBusVerificationInstructions =>
      'JavBus では地域別の年齢確認を手動で行う必要があります。同じ安全なセッションで取得を続けるには、すべての質問に回答してください。';

  @override
  String get javBusVerificationSubmit => '確認を送信';

  @override
  String get settingsDataTransferTitle => 'データの入出力';

  @override
  String get settingsDataTransferSubtitle =>
      '女優、作品、詳細情報、画像を ZIP でバックアップまたは復元します。';

  @override
  String get dataTransferExportTitle => 'データをエクスポート';

  @override
  String get dataTransferExportSubtitle => '完全な ZIP バックアップの保存先を選択します。';

  @override
  String get dataTransferImportTitle => 'データをインポート';

  @override
  String get dataTransferImportSubtitle => 'ZIP バックアップを選択してすぐに復元します。';

  @override
  String get dataTransferPreparing => 'データを準備中…';

  @override
  String get dataTransferDuplicateProgress => '重複する女優の選択を待っています…';

  @override
  String get dataTransferWriting => 'データと画像を書き込み中…';

  @override
  String get dataTransferExportSuccess => 'エクスポートが完了しました。';

  @override
  String dataTransferExportSuccessWithSkippedImages(int count) {
    return 'エクスポート完了。使用できない画像を $count 枚スキップしました。';
  }

  @override
  String get dataTransferImportSuccess => 'インポートが完了しました。データをすぐに使用できます。';

  @override
  String get dataTransferDuplicateTitle => '重複する女優が見つかりました';

  @override
  String get dataTransferDuplicateExplanation =>
      '画像と作品数を比較して、使用する女優の詳細情報を選択してください。既存の作品と関連付けは保持されます。';

  @override
  String get dataTransferKeepExisting => '現在の詳細を保持';

  @override
  String get dataTransferUseImported => 'インポートした詳細を使用';

  @override
  String get dataTransferContinue => '続行';

  @override
  String dataTransferWorkCount(int count) {
    return '作品数: $count';
  }

  @override
  String get dataTransferArchiveTooLarge => 'ZIP が対応サイズを超えています。';

  @override
  String get dataTransferUnsafeArchive => 'ZIP に安全でないファイルパスが含まれています。';

  @override
  String get dataTransferCorruptArchive => 'ZIP が壊れているか、画像のチェックサムに失敗しました。';

  @override
  String get dataTransferFileUnreadable => '選択したファイルを読み取れませんでした。';

  @override
  String get dataTransferActorNameConflict => 'インポートした女優名が別のデータと競合しています。';

  @override
  String get dataTransferBusy => '別のデータ転送が進行中です。';

  @override
  String get dataTransferFailed => 'データ転送に失敗しました。既存データは変更されていません。';

  @override
  String get otherSettings => 'その他';

  @override
  String get about => '概要';

  @override
  String get github => 'github';

  @override
  String get feedbackSuggestions => 'フィードバック';

  @override
  String get scrapeSources => '取得元';

  @override
  String get scrapeSourceDetailsTitle => '女優詳細情報の取得元';

  @override
  String get scrapeSourceWorksTitle => '作品の取得元';

  @override
  String get scrapeSourcePriorityHint => '取得元を選択し、ドラッグして優先順位を変更';

  @override
  String get scrapeSourceAliasTitle => '女優別名の取得元';

  @override
  String get scrapeSourceMinnanoAv => 'みんなのAV';

  @override
  String get scrapeSourceJavBus => 'JavBus';

  @override
  String get scrapeSourceAvBase => 'AvBase';

  @override
  String get scrapeSourceAvWiki => 'AV-Wiki';

  @override
  String get scrapeSourceAll => 'すべての取得元（品番で統合・重複排除）';

  @override
  String get scrapeSourceSaveFailed => '取得元の設定を保存できませんでした。';

  @override
  String get scrapeSourceConnectionTitle => '取得元の接続状態';

  @override
  String get scrapeSourceConnectionSubtitle => '追加済みの取得元を確認し、ここで接続テストと確認を行います。';

  @override
  String get scrapeSourceRetest => '接続を再テスト';

  @override
  String get scrapeSourceTesting => 'テスト中…';

  @override
  String get scrapeSourceNotTested => '未テスト';

  @override
  String get scrapeSourceConnected => '接続成功';

  @override
  String get scrapeSourceConnectionFailed => '接続失敗';

  @override
  String get scrapeSourceVerificationRequired => '確認が必要';

  @override
  String get scrapeAliases => '別名を取得';

  @override
  String get scrapeAliasesDescription =>
      '別名の取得元で見つかった名前を、現在の名前を除いて女優の別名に保存します。';

  @override
  String get scrapePartial => '一部の取得元または作品を処理できませんでした。';

  @override
  String get scrapeZeroResults => '新しい作品は見つかりませんでした。';

  @override
  String get softwareUpdate => 'ソフトウェア更新';

  @override
  String get softwareUpdateDescription => 'AVACA の最新バージョンを確認してインストールします。';

  @override
  String get currentVersion => '現在のバージョン';

  @override
  String get latestVersion => '最新バージョン';

  @override
  String get autoCheckUpdates => '更新を自動的に確認';

  @override
  String get checkForUpdates => '更新を確認';

  @override
  String get checkingForUpdates => '更新を確認中…';

  @override
  String get downloadingUpdate => '更新をダウンロード中…';

  @override
  String get verifyingUpdate => '更新を検証中…';

  @override
  String get installingUpdate => 'インストールを開始中…';

  @override
  String get updateAvailable => '新しいバージョンがあります';

  @override
  String get upToDate => 'AVACA は最新です。';

  @override
  String get updateNow => '今すぐ更新';

  @override
  String get updateLater => '後で';

  @override
  String get updateUnavailable => 'このデバイスに対応する更新ファイルがありません。';

  @override
  String get updateCheckFailed => '更新を確認できませんでした。後でもう一度お試しください。';

  @override
  String get updateDownloadFailed => '更新のダウンロードに失敗しました。既存データは変更されていません。';

  @override
  String get updateIntegrityFailed => '更新ファイルの検証に失敗したため、更新を停止しました。';

  @override
  String get updateNotSupported => 'このデバイスでは自動更新に対応していません。';

  @override
  String get updateInstallPermissionRequired =>
      '先に AVACA に提供元不明のアプリのインストールを許可してください。';

  @override
  String get updatePortableFolderNotWritable =>
      'portable アプリフォルダーに書き込めないため、更新を停止しました。';

  @override
  String get updateInstallerFailed => '更新プログラムを開始できませんでした。現在のバージョンを保持しています。';

  @override
  String get updateDataPreserved => 'データと設定は保持されます。';

  @override
  String get prefixRouteRulesTitle => '作品画像 Prefix ルート規則';

  @override
  String get prefixRouteRulesSubtitle => '検証済みダウンロードから学習した画像 family を管理します。';

  @override
  String prefixRouteRuleCount(int count) {
    return '学習済み Prefix 規則 $count 件';
  }

  @override
  String get prefixRouteSearchHint => 'Prefix を検索';

  @override
  String get prefixRouteNoRules => '学習済みの Prefix ルート規則はありません。';

  @override
  String get prefixRouteNoSearchResults => '一致する Prefix 規則はありません。';

  @override
  String get prefixRouteBestFamily => '優先 family';

  @override
  String get prefixRouteNotAvailable => 'なし';

  @override
  String get prefixRouteCandidates => '既知の候補ルート';

  @override
  String prefixRouteSuccessCount(int count) {
    return '成功: $count 回';
  }

  @override
  String prefixRouteFailureCount(int count) {
    return '失敗: $count 回';
  }

  @override
  String prefixRouteLastSuccess(String time) {
    return '最終成功: $time';
  }

  @override
  String prefixRouteLastFailure(String time) {
    return '最終失敗: $time';
  }

  @override
  String get prefixRouteStatusVerified => '検証済み';

  @override
  String get prefixRouteStatusExceptions => '例外あり';

  @override
  String get prefixRouteStatusPending => '再検証待ち';

  @override
  String get prefixRouteStatusProbeFailed => '探測失敗';

  @override
  String get prefixRouteManualOverride => '手動指定 route';

  @override
  String get prefixRouteAutomatic => '自動';

  @override
  String get prefixRouteAutomaticDescription =>
      '学習済み候補を優先し、必要な場合だけ対応 family を探測します。';

  @override
  String get prefixRouteManualDescription => 'この family を最初に試します。学習統計は保持されます。';

  @override
  String get prefixRouteFamilyDmmStandard => 'DMM Standard';

  @override
  String get prefixRouteFamilyDmmLeadingOne => 'DMM Leading One';

  @override
  String get prefixRouteFamilyDmmH1711 => 'DMM H1711';

  @override
  String get prefixRouteFamilyDmmRebeccaH346 => 'DMM Rebecca H346';

  @override
  String get prefixRouteFamilyMgstagePrestige => 'MGStage Prestige';

  @override
  String get prefixRouteFamilyMgstageSeikyouiku => 'MGStage Seikyouiku';

  @override
  String get prefixRouteExport => '規則をエクスポート';

  @override
  String get prefixRouteImport => '規則をインポート';

  @override
  String get prefixRouteExportDialogTitle => 'Prefix 規則をエクスポート';

  @override
  String get prefixRouteExportRulesOnly => '規則のみ';

  @override
  String get prefixRouteExportRulesOnlyDescription =>
      '検証統計を含めず family だけを出力します。';

  @override
  String get prefixRouteExportWithStatistics => '規則と統計';

  @override
  String get prefixRouteExportWithStatisticsDescription => '成功、失敗、時刻を含めます。';

  @override
  String get prefixRouteExportSuccess => 'Prefix 規則をエクスポートしました。';

  @override
  String get prefixRouteImportDialogTitle => 'Prefix 規則をインポート';

  @override
  String prefixRouteImportPreview(int rules, int conflicts) {
    return '$rules 件の規則が見つかりました。手動指定の競合: $conflicts 件。';
  }

  @override
  String get prefixRouteImportMerge => '統合';

  @override
  String get prefixRouteImportReplace => '置換';

  @override
  String prefixRouteImportSuccess(int count) {
    return 'Prefix 規則を $count 件インポートしました。';
  }

  @override
  String get prefixRouteOperationFailed =>
      'Prefix ルート操作に失敗しました。既存の規則は変更されていません。';

  @override
  String get prefixRouteLoadFailed => 'Prefix ルート規則を読み込めませんでした。';

  @override
  String get prefixRouteClearAutomatic => '自動学習をクリア';

  @override
  String get prefixRouteClearAutomaticTitle => '自動学習をクリアしますか？';

  @override
  String get prefixRouteClearAutomaticMessage =>
      '学習候補と統計をクリアします。手動指定とダウンロード済み画像は保持されます。';

  @override
  String get prefixRouteClearAutomaticSuccess => 'Prefix の自動学習をクリアしました。';

  @override
  String get prefixRouteReset => 'この Prefix の学習をリセット';

  @override
  String get prefixRouteResetTitle => 'この Prefix の学習をリセットしますか？';

  @override
  String get prefixRouteResetMessage => '候補と統計をクリアします。手動指定がある場合は保持されます。';

  @override
  String get prefixRouteForget => 'この Prefix 規則を削除';

  @override
  String get prefixRouteForgetTitle => 'この Prefix 規則を削除しますか？';

  @override
  String get prefixRouteForgetMessage =>
      'この Prefix の学習データと手動指定を削除します。ダウンロード済み画像と作品データは変更されません。';

  @override
  String get workFieldProvenanceTitle => '項目ソース';

  @override
  String get workFieldProvenanceSource => 'ソース';

  @override
  String get workFieldProvenanceObservedAt => '観測時刻';

  @override
  String get workFieldProvenanceUnknown => '不明なソース';

  @override
  String get dataHealthTitle => 'データ健全性';

  @override
  String get dataHealthSubtitle =>
      '件数、不足している作品項目や画像、項目ソース、保留中の削除、取得元エラーを確認します。';

  @override
  String dataHealthSectionUnavailable(String section) {
    return 'このセクションを読み込めませんでした: $section';
  }

  @override
  String get dataHealthRefresh => '更新';

  @override
  String get dataHealthActresses => '女優';

  @override
  String get dataHealthWorks => '作品';

  @override
  String get dataHealthStored => '保存済み動画';

  @override
  String get dataHealthNotStored => '未保存';

  @override
  String get dataHealthMetadataIssues => '不足している作品項目';

  @override
  String get dataHealthMissingImages => '不足している画像参照';

  @override
  String get dataHealthMissingProvenance => '不足している項目ソース';

  @override
  String get dataHealthPendingDeletions => '保留中のファイル削除';

  @override
  String get dataHealthJobStates => 'スクレイプジョブ状態';

  @override
  String get dataHealthSourceErrors => '過去 7 日間のソースエラー';

  @override
  String get scrapeJobsTitle => 'スクレイプジョブ';

  @override
  String get scrapeJobsEmpty => 'スクレイプジョブはありません。';

  @override
  String scrapeJobsSelectedCount(int count) {
    return '$count 件を選択中';
  }

  @override
  String get scrapeJobsDelete => '削除';

  @override
  String get scrapeJobsDeleteTitle => '選択したスクレイプジョブを削除しますか？';

  @override
  String scrapeJobsDeleteMessage(int count) {
    return '$count 件の完了したスクレイプジョブの記録を削除しますか？作品、女優、設定は変更されません。';
  }

  @override
  String get scrapeJobsDeleteActive =>
      '実行中または待機中のジョブは削除できません。完了したジョブだけを選択してください。';

  @override
  String scrapeJobsDeleted(int count) {
    return '$count 件のスクレイプジョブを削除しました。';
  }

  @override
  String get scrapeJobsDeleteFailed => 'スクレイプジョブの記録を削除できませんでした。';

  @override
  String get scrapeJobDetailTitle => 'スクレイプジョブ詳細';

  @override
  String get scrapeJobPause => '一時停止';

  @override
  String get scrapeJobResume => '再開';

  @override
  String get scrapeJobCancel => 'キャンセル';

  @override
  String get scrapeJobRetryFailed => '失敗した作品だけ再試行';

  @override
  String get scrapeJobEvents => 'イベント履歴';

  @override
  String get scrapeJobDiagnostics => '刮削診断';

  @override
  String get scrapeJobItems => '作品チェックポイント';

  @override
  String get scrapeJobNoEvents => 'イベントはまだありません。';

  @override
  String get scrapeJobNoItems => '作品チェックポイントはまだありません。';

  @override
  String get scrapeJobFilterAll => 'すべて';

  @override
  String get scrapeJobFilterReview => '要確認';

  @override
  String get scrapeJobFilterKeep => '保持';

  @override
  String get scrapeJobFilterExclude => '除外';

  @override
  String get scrapeJobFilterFailed => '失敗';

  @override
  String get scrapeJobNoFilteredItems => 'このフィルターに一致するチェックポイントはありません。';

  @override
  String get scrapeJobStateReview => '要確認';

  @override
  String get scrapeJobStateQueued => '待機中';

  @override
  String get scrapeJobStateRunning => '実行中';

  @override
  String get scrapeJobStatePaused => '一時停止';

  @override
  String get scrapeJobStateWaiting => '認証待ち';

  @override
  String get scrapeJobStateSucceeded => '成功';

  @override
  String get scrapeJobStatePartial => '一部完了';

  @override
  String get scrapeJobStateFailed => '失敗';

  @override
  String get scrapeJobStateCancelled => 'キャンセル済み';

  @override
  String get scrapeJobStateExcluded => '除外';

  @override
  String scrapeJobCollectionSummary(int raw, int unique, int duplicates) {
    return '取得 $raw、重複除外後 $unique、重複 $duplicates';
  }

  @override
  String scrapeJobDetailProgress(int current, int total) {
    return '詳細 $current/$total';
  }

  @override
  String scrapeJobTerminalProgress(
    int processed,
    int total,
    int saved,
    int excluded,
    int failed,
  ) {
    return '処理 $processed/$total、保存 $saved、除外 $excluded、失敗 $failed';
  }

  @override
  String scrapeJobCandidateSummary(int count, int duplicates) {
    return '候補作品 $count、コレクション重複 $duplicates';
  }

  @override
  String scrapeJobSupplementalEvidence(int current, int total) {
    return '補足証拠 $current/$total';
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
    return '処理 $processed/$total、保持 $keep、要確認 $review、除外 $excluded、失敗 $failed';
  }

  @override
  String scrapeJobRulesVersion(String version) {
    return 'ルールバージョン：$version';
  }

  @override
  String get settingsDataHealthTitle => 'データ健全性';

  @override
  String get settingsDataHealthSubtitle => 'データ完全性とスクレイプの可観測性を確認します。';

  @override
  String get settingsScrapeJobsTitle => 'スクレイプジョブ';

  @override
  String get settingsScrapeJobsSubtitle => 'キュー、復旧、一時停止、失敗再試行を確認します。';
}
