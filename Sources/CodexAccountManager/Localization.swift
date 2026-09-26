import AppKit
import Foundation
import Observation

enum AppLanguage: String, Sendable, Codable, CaseIterable, Identifiable {
    case vietnamese = "vi"
    case english = "en"
    case japanese = "ja"
    case chinese = "zh-Hans"

    var id: String { rawValue }

    static func preferred(from identifiers: [String] = Locale.preferredLanguages) -> AppLanguage {
        for identifier in identifiers {
            let value = identifier.lowercased()
            if value.hasPrefix("vi") { return .vietnamese }
            if value.hasPrefix("en") { return .english }
            if value.hasPrefix("ja") { return .japanese }
            if value.hasPrefix("zh") { return .chinese }
        }
        return .english
    }

    var locale: Locale { Locale(identifier: rawValue) }
}

enum L10n {
    private static let values: [AppLanguage: [String: String]] = [
        .vietnamese: [
            "waiting_login": "Đang chờ đăng nhập…",
            "cancel": "Huỷ",
            "loading": "Đang tải…",
            "no_accounts": "Chưa có tài khoản",
            "no_accounts_description": "Thêm mới hoặc import tài khoản Codex hiện tại.",
            "close": "Đóng",
            "settings": "Cài đặt",
            "accounts": "Tài khoản",
            "general": "Chung",
            "manage_accounts": "Quản lý tài khoản",
            "account_count": "%d tài khoản",
            "codex_cli": "Codex CLI",
            "binary_path": "Đường dẫn Binary",
            "not_configured": "Chưa thiết lập",
            "configure_cli_in_general": "Thiết lập Codex CLI trong mục Chung.",
            "app_preferences": "Tuỳ chọn ứng dụng",
            "language": "Ngôn ngữ",
            "language_system": "Theo ngôn ngữ hệ thống",
            "language_vietnamese": "Tiếng Việt",
            "language_english": "Tiếng Anh",
            "language_japanese": "Tiếng Nhật",
            "language_chinese": "Tiếng Trung",
            "add_account": "Thêm tài khoản",
            "import_current": "Import tài khoản Codex hiện tại",
            "choose_binary": "Chọn Codex Binary…",
            "launch_at_login": "Mở cùng macOS",
            "quota_reset_notifications": "Thông báo khi hạn mức được đặt lại",
            "quit": "Thoát",
            "active": "Đang sử dụng",
            "switch_account": "Chuyển sang tài khoản này",
            "unknown_email": "Không rõ email",
            "credits": "Credits",
            "credits_accessibility": "Credits: %@",
            "delete_confirmation": "Xoá tài khoản “%@”?",
            "delete_local_profile": "Xoá profile local",
            "delete_message": "Việc này chỉ xoá profile local trên máy Mac. Không xoá tài khoản ChatGPT thật.",
            "delete": "Xoá",
            "quota": "Hạn mức",
            "day": "Ngày",
            "week": "Tuần",
            "month": "Tháng",
            "days": "%d ngày",
            "unlimited": "Không giới hạn",
            "updated": "Cập nhật %@",
            "just_updated": "Vừa cập nhật",
            "refreshing": "Đang cập nhật…",
            "no_quota": "Không lấy được hạn mức",
            "remaining": "Còn lại %d%%",
            "quota_reset_title": "Hạn mức đã được đặt lại",
            "quota_reset_message": "Tài khoản “%@” đã được đặt lại hạn mức %@.",
            "quota_accessibility": "Hạn mức %@: %@",
            "no_reset_time": "Không có thời gian đặt lại",
            "reset_after_hours": "Đặt lại sau %d giờ %d phút",
            "reset_after_minutes": "Đặt lại sau %d phút",
            "reset_in_days": "Đặt lại sau %d ngày %d giờ",
            "reset_on_date": "Đặt lại lúc %@, %@",
            "select_binary_title": "Chọn Codex Binary",
            "invalid_binary": "File đã chọn không phải Codex CLI hợp lệ.",
            "codex_cli_not_found": "Không tìm thấy Codex CLI.",
            "codex_cli_setup_description": "Hãy cài Codex CLI hoặc chọn file thực thi Codex trên máy Mac.",
            "account_exists": "Tài khoản này đã có trong codex-account-manager.",
            "preparing_login": "Đang chuẩn bị đăng nhập ChatGPT…",
            "waiting_chatgpt_login": "Đang chờ đăng nhập ChatGPT…",
            "usage_unavailable": "Tạm thời không lấy được hạn mức",
            "workspace_discovery_timed_out": "Kết nối tới Codex đã quá thời gian chờ. Vui lòng thử lại.",
            "login_url_missing": "Codex CLI không trả về liên kết đăng nhập.",
            "login_response_mismatch": "Phản hồi đăng nhập không khớp.",
            "login_failed": "Đăng nhập không thành công.",
            "login_not_completed": "Không thể hoàn tất đăng nhập. Vui lòng thử lại.",
            "chatgpt_only": "codex-account-manager chỉ hỗ trợ tài khoản ChatGPT.",
            "app_server_stopped": "Codex app-server đã dừng.",
            "app_server_no_response": "Codex app-server không phản hồi.",
            "login_timeout": "Hết thời gian chờ đăng nhập.",
            "app_server_exited": "Codex app-server đã thoát.",
            "temp_file_failed": "Không thể tạo file tạm.",
            "target_auth_missing": "Tài khoản đích chưa có thông tin đăng nhập.",
            "external_active_error": "Phát hiện tài khoản Codex khác đang sử dụng. Hãy import hoặc kích hoạt lại tài khoản.",
            "switch_verify_mismatch": "Xác minh tài khoản sau khi chuyển không khớp.",
        ],
        .english: [
            "waiting_login": "Waiting for sign-in…",
            "cancel": "Cancel",
            "loading": "Loading…",
            "no_accounts": "No accounts",
            "no_accounts_description": "Add an account or import the current Codex account.",
            "close": "Close",
            "settings": "Settings",
            "accounts": "Accounts",
            "general": "General",
            "manage_accounts": "Manage Accounts",
            "account_count": "%d accounts",
            "codex_cli": "Codex CLI",
            "binary_path": "Binary Path",
            "not_configured": "Not configured",
            "configure_cli_in_general": "Configure Codex CLI in General.",
            "app_preferences": "App Preferences",
            "language": "Language",
            "language_system": "System Language",
            "language_vietnamese": "Vietnamese",
            "language_english": "English",
            "language_japanese": "Japanese",
            "language_chinese": "Chinese",
            "add_account": "Add Account",
            "import_current": "Import Current Codex Account",
            "choose_binary": "Choose Codex Binary…",
            "launch_at_login": "Open at Login",
            "quota_reset_notifications": "Notify when usage limits reset",
            "quit": "Quit",
            "active": "Active account",
            "switch_account": "Switch to this account",
            "unknown_email": "Unknown email",
            "credits": "Credits",
            "credits_accessibility": "Credits: %@",
            "delete_confirmation": "Delete account “%@”?",
            "delete_local_profile": "Delete Local Profile",
            "delete_message": "This only removes the local profile from this Mac. It does not delete the ChatGPT account.",
            "delete": "Delete",
            "quota": "Quota",
            "day": "Day",
            "week": "Week",
            "month": "Month",
            "days": "%d days",
            "unlimited": "Unlimited",
            "updated": "Updated %@",
            "just_updated": "Just updated",
            "refreshing": "Updating…",
            "no_quota": "Quota unavailable",
            "remaining": "%d%% left",
            "quota_reset_title": "Usage limit reset",
            "quota_reset_message": "Account “%@” has had its %@ limit reset.",
            "quota_accessibility": "%@ quota: %@",
            "no_reset_time": "Reset time unavailable",
            "reset_after_hours": "Resets in %d hours %d minutes",
            "reset_after_minutes": "Resets in %d minutes",
            "reset_in_days": "Resets in %d days %d hours",
            "reset_on_date": "Resets at %@, %@",
            "select_binary_title": "Choose Codex Binary",
            "invalid_binary": "The selected file is not a valid Codex CLI.",
            "codex_cli_not_found": "Codex CLI was not found.",
            "codex_cli_setup_description": "Install Codex CLI or choose the Codex executable on this Mac.",
            "account_exists": "This account is already in codex-account-manager.",
            "preparing_login": "Preparing ChatGPT sign-in…",
            "waiting_chatgpt_login": "Waiting for ChatGPT sign-in…",
            "usage_unavailable": "Usage is temporarily unavailable",
            "workspace_discovery_timed_out": "Connection to Codex timed out. Please try again.",
            "login_url_missing": "Codex CLI did not return a sign-in link.",
            "login_response_mismatch": "The sign-in response did not match.",
            "login_failed": "Sign-in failed.",
            "login_not_completed": "Sign-in could not be completed. Please try again.",
            "chatgpt_only": "codex-account-manager only supports ChatGPT accounts.",
            "app_server_stopped": "Codex app-server stopped.",
            "app_server_no_response": "Codex app-server did not respond.",
            "login_timeout": "The sign-in request timed out.",
            "app_server_exited": "Codex app-server exited.",
            "temp_file_failed": "Could not create a temporary file.",
            "target_auth_missing": "The target account has no sign-in credentials.",
            "external_active_error": "Another Codex account is active. Import it or reactivate the saved account.",
            "switch_verify_mismatch": "Account verification failed after switching.",
        ],
        .japanese: [
            "waiting_login": "サインインを待っています…",
            "cancel": "キャンセル",
            "loading": "読み込み中…",
            "no_accounts": "アカウントがありません",
            "no_accounts_description": "アカウントを追加するか、現在のCodexアカウントを読み込んでください。",
            "close": "閉じる",
            "settings": "設定",
            "accounts": "アカウント",
            "general": "一般",
            "manage_accounts": "アカウントを管理",
            "account_count": "%d個のアカウント",
            "codex_cli": "Codex CLI",
            "binary_path": "Binaryのパス",
            "not_configured": "未設定",
            "configure_cli_in_general": "「一般」でCodex CLIを設定してください。",
            "app_preferences": "アプリの設定",
            "language": "言語",
            "language_system": "システムの言語",
            "language_vietnamese": "ベトナム語",
            "language_english": "英語",
            "language_japanese": "日本語",
            "language_chinese": "中国語",
            "add_account": "アカウントを追加",
            "import_current": "現在のCodexアカウントを読み込む",
            "choose_binary": "Codex Binaryを選択…",
            "launch_at_login": "ログイン時に開く",
            "quota_reset_notifications": "使用枠のリセットを通知",
            "quit": "終了",
            "active": "使用中のアカウント",
            "switch_account": "このアカウントに切り替える",
            "unknown_email": "メールアドレス不明",
            "credits": "クレジット",
            "credits_accessibility": "クレジット：%@",
            "delete_confirmation": "アカウント「%@」を削除しますか？",
            "delete_local_profile": "ローカルプロファイルを削除",
            "delete_message": "このMac上のローカルプロファイルのみ削除されます。ChatGPTアカウントは削除されません。",
            "delete": "削除",
            "quota": "使用枠",
            "day": "日",
            "week": "週",
            "month": "月",
            "days": "%d日",
            "unlimited": "無制限",
            "updated": "%@に更新",
            "just_updated": "更新したばかり",
            "refreshing": "更新中…",
            "no_quota": "使用枠を取得できません",
            "remaining": "残り%d%%",
            "quota_reset_title": "使用枠がリセットされました",
            "quota_reset_message": "アカウント「%@」の%@制限がリセットされました。",
            "quota_accessibility": "%@の使用枠：%@",
            "no_reset_time": "リセット時刻がありません",
            "reset_after_hours": "%d時間%d分後にリセット",
            "reset_after_minutes": "%d分後にリセット",
            "reset_in_days": "%d日%d時間後にリセット",
            "reset_on_date": "%2$@の%1$@にリセット",
            "select_binary_title": "Codex Binaryを選択",
            "invalid_binary": "選択したファイルは有効なCodex CLIではありません。",
            "codex_cli_not_found": "Codex CLIが見つかりません。",
            "codex_cli_setup_description": "Codex CLIをインストールするか、このMac上の実行ファイルを選択してください。",
            "account_exists": "このアカウントはすでにcodex-account-managerにあります。",
            "preparing_login": "ChatGPTへのサインインを準備中…",
            "waiting_chatgpt_login": "ChatGPTへのサインインを待っています…",
            "usage_unavailable": "使用状況を一時的に取得できません",
            "workspace_discovery_timed_out": "Codex への接続がタイムアウトしました。もう一度お試しください。",
            "login_url_missing": "Codex CLIからサインインリンクが返されませんでした。",
            "login_response_mismatch": "サインイン応答が一致しません。",
            "login_failed": "サインインに失敗しました。",
            "login_not_completed": "サインインを完了できませんでした。もう一度お試しください。",
            "chatgpt_only": "codex-account-managerはChatGPTアカウントのみ対応しています。",
            "app_server_stopped": "Codex app-serverが停止しました。",
            "app_server_no_response": "Codex app-serverが応答しません。",
            "login_timeout": "サインインの待機時間を超えました。",
            "app_server_exited": "Codex app-serverが終了しました。",
            "temp_file_failed": "一時ファイルを作成できません。",
            "target_auth_missing": "切り替え先アカウントにサインイン情報がありません。",
            "external_active_error": "別のCodexアカウントが使用されています。読み込むか、保存済みアカウントを再度有効にしてください。",
            "switch_verify_mismatch": "切り替え後のアカウント確認に失敗しました。",
        ],
        .chinese: [
            "waiting_login": "正在等待登录…",
            "cancel": "取消",
            "loading": "正在加载…",
            "no_accounts": "暂无账号",
            "no_accounts_description": "添加账号或导入当前 Codex 账号。",
            "close": "关闭",
            "settings": "设置",
            "accounts": "账号",
            "general": "通用",
            "manage_accounts": "管理账号",
            "account_count": "%d 个账号",
            "codex_cli": "Codex CLI",
            "binary_path": "Binary 路径",
            "not_configured": "未配置",
            "configure_cli_in_general": "请在“通用”中配置 Codex CLI。",
            "app_preferences": "应用偏好设置",
            "language": "语言",
            "language_system": "跟随系统语言",
            "language_vietnamese": "越南语",
            "language_english": "英语",
            "language_japanese": "日语",
            "language_chinese": "中文",
            "add_account": "添加账号",
            "import_current": "导入当前 Codex 账号",
            "choose_binary": "选择 Codex Binary…",
            "launch_at_login": "登录时打开",
            "quota_reset_notifications": "额度重置时通知",
            "quit": "退出",
            "active": "当前账号",
            "switch_account": "切换到此账号",
            "unknown_email": "未知邮箱",
            "credits": "积分",
            "credits_accessibility": "积分：%@",
            "delete_confirmation": "删除账号“%@”？",
            "delete_local_profile": "删除本地配置",
            "delete_message": "这只会删除此 Mac 上的本地配置，不会删除 ChatGPT 账号。",
            "delete": "删除",
            "quota": "额度",
            "day": "天",
            "week": "周",
            "month": "月",
            "days": "%d天",
            "unlimited": "无限",
            "updated": "%@更新",
            "just_updated": "刚刚更新",
            "refreshing": "正在更新…",
            "no_quota": "无法获取额度",
            "remaining": "剩余%d%%",
            "quota_reset_title": "额度已重置",
            "quota_reset_message": "账号“%@”的%@额度已重置。",
            "quota_accessibility": "%@额度：%@",
            "no_reset_time": "无重置时间",
            "reset_after_hours": "%d小时%d分钟后重置",
            "reset_after_minutes": "%d分钟后重置",
            "reset_in_days": "%d天%d小时后重置",
            "reset_on_date": "%2$@ %1$@重置",
            "select_binary_title": "选择 Codex Binary",
            "invalid_binary": "所选文件不是有效的 Codex CLI。",
            "codex_cli_not_found": "未找到 Codex CLI。",
            "codex_cli_setup_description": "请安装 Codex CLI，或选择这台 Mac 上的 Codex 可执行文件。",
            "account_exists": "此账号已存在于 codex-account-manager 中。",
            "preparing_login": "正在准备登录 ChatGPT…",
            "waiting_chatgpt_login": "正在等待登录 ChatGPT…",
            "usage_unavailable": "暂时无法获取使用额度",
            "workspace_discovery_timed_out": "连接 Codex 超时，请重试。",
            "login_url_missing": "Codex CLI 未返回登录链接。",
            "login_response_mismatch": "登录响应不匹配。",
            "login_failed": "登录失败。",
            "login_not_completed": "无法完成登录。请重试。",
            "chatgpt_only": "codex-account-manager 仅支持 ChatGPT 账号。",
            "app_server_stopped": "Codex app-server 已停止。",
            "app_server_no_response": "Codex app-server 无响应。",
            "login_timeout": "等待登录超时。",
            "app_server_exited": "Codex app-server 已退出。",
            "temp_file_failed": "无法创建临时文件。",
            "target_auth_missing": "目标账号没有登录凭据。",
            "external_active_error": "检测到另一个正在使用的 Codex 账号。请导入该账号或重新激活已保存的账号。",
            "switch_verify_mismatch": "切换后账号验证不匹配。",
        ],
    ]

    static func text(_ key: String, language: AppLanguage = .preferred()) -> String {
        values[language]?[key] ?? values[.english]?[key] ?? key
    }

    static func format(_ key: String, language: AppLanguage = .preferred(), arguments: [CVarArg]) -> String {
        String(format: text(key, language: language), locale: language.locale, arguments: arguments)
    }

    static func missingKeys(for language: AppLanguage) -> Set<String> {
        let baseKeys = Set(values[.english, default: [:]].keys)
        let translatedKeys = Set(values[language, default: [:]].keys)
        return baseKeys.subtracting(translatedKeys)
    }
}

@MainActor @Observable
final class LocalizationManager {
    static let shared = LocalizationManager()

    private(set) var language: AppLanguage
    @ObservationIgnored private var languageOverride: AppLanguage?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    private init() {
        language = .preferred()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSLocale.currentLocaleDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        })
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        })
        observers.append(center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        })
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleLanguagePreferencesChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        })
    }

    func text(_ key: String) -> String {
        L10n.text(key, language: language)
    }

    func format(_ key: String, _ arguments: CVarArg...) -> String {
        L10n.format(key, language: language, arguments: arguments)
    }

    func setLanguageOverride(_ language: AppLanguage?) {
        languageOverride = language
        refresh()
    }

    private func refresh() {
        let preferred = languageOverride ?? AppLanguage.preferred()
        if language != preferred { language = preferred }
    }
}
