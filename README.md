# codex-account-manager

Manage multiple ChatGPT Codex accounts directly from the macOS menu bar.

<img src="Resources/preview.gif" alt="Codex Account Manager preview" />

[Tiếng Việt](#tiếng-việt) · [English](#english)

> [!IMPORTANT]
> codex-account-manager is an unofficial community project and is not affiliated with or endorsed by OpenAI.

## Tiếng Việt

Ứng dụng menu bar macOS để quản lý nhiều tài khoản ChatGPT Codex. App chạy local và không hiện trong Dock.

### Tính năng

- Thêm tài khoản bằng luồng đăng nhập ChatGPT chính thức hoặc import tài khoản Codex đang dùng.
- Đổi tài khoản, kéo thả để sắp xếp, và xoá profile local.
- Xem gói, hạn mức, credit và thời gian reset.
- Tự cập nhật khi Codex có hoạt động; hạn mức được đưa về 100% đúng mốc reset.
- Thông báo macOS khi hạn mức 5h hoặc tuần được reset.
- Cài đặt Codex CLI, ngôn ngữ, thông báo và mở cùng macOS.

### Yêu cầu

- macOS 14 trở lên.
- Swift 6.2 trở lên và Xcode tương ứng.
- Codex CLI đang hoạt động, hoặc Codex CLI đi kèm app ChatGPT.
- Tài khoản Codex dùng ChatGPT; không hỗ trợ tài khoản chỉ dùng API key.

### Chạy từ source

```bash
git clone https://github.com/vuduchiieu/codex-account-manager.git
cd codex-account-manager
./build.sh
open .build/codex-account-manager.app
```

### Cách dùng

1. Chuột phải icon để thêm/import tài khoản hoặc mở Cài đặt.
2. Chuột trái icon để xem hạn mức; nhấn vòng tròn cạnh email để đổi tài khoản.
3. Quản lý, sắp xếp hoặc xoá profile trong **Cài đặt → Quản lý tài khoản**.

> [!WARNING]
> Chuyển tài khoản có thể khởi động lại ChatGPT/Codex đang chạy. Hãy lưu công việc trước khi chuyển.

### Dữ liệu và quyền riêng tư

App không có server riêng, analytics hoặc telemetry. Dữ liệu nằm tại:

```text
~/Library/Application Support/codex-account-manager/
```

- `accounts.json`: email, gói và hạn mức đã lưu; không chứa token.
- `profiles/<UUID>/auth.json`: credential local cho từng profile.
- `backups/`: bản sao credential trước khi chuyển tài khoản.

App cập nhật `~/.codex/auth.json` an toàn, kiểm tra email sau khi chuyển và rollback nếu thất bại.

### Giới hạn

- Hạn mức phụ thuộc vào Codex CLI và phản hồi từ server.
- Chưa tự đổi tài khoản khi hết hạn mức hoặc đồng bộ qua cloud.

---

## English

A macOS menu bar app for managing multiple ChatGPT Codex accounts. It runs locally and stays out of the Dock.

### Features

- Add accounts through the official ChatGPT sign-in flow or import the current Codex account.
- Switch accounts, drag to reorder, and remove local profiles.
- View plans, usage limits, credits, and reset times.
- Refresh after Codex activity; reset cached usage to 100% at the scheduled reset time.
- Send macOS notifications when a 5-hour or weekly limit resets.
- Configure the Codex CLI, language, notifications, and Open at Login.

### Requirements

- macOS 14 or later.
- Swift 6.2 or later with a compatible Xcode version.
- A working Codex CLI, or the CLI bundled with the ChatGPT app.
- A ChatGPT-backed Codex account; API-key-only accounts are not supported.

### Run from source

```bash
git clone https://github.com/vuduchiieu/codex-account-manager.git
cd codex-account-manager
./build.sh
open .build/codex-account-manager.app
```

### Usage

1. Right-click the icon to add/import an account or open Settings.
2. Left-click it to view usage; click the circle beside an email address to switch accounts.
3. Manage, reorder, or remove local profiles in **Settings → Manage Accounts**.

> [!WARNING]
> Switching accounts may relaunch a running ChatGPT/Codex app. Save active work first.

### Data and privacy

The app has no project-owned server, analytics, or telemetry. Local data is stored in:

```text
~/Library/Application Support/codex-account-manager/
```

- `accounts.json`: saved email, plan, and usage data; no tokens.
- `profiles/<UUID>/auth.json`: local credentials for each profile.
- `backups/`: credential backups made before switching accounts.

The app updates `~/.codex/auth.json` safely, verifies the email after a switch, and rolls back on failure.

### Limitations

- Usage data depends on the installed Codex CLI and server response.
- Automatic account rotation and cloud sync are not available.
