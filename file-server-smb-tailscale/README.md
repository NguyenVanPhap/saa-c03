# File Server: SMB + Tailscale trên Windows 11

Hai máy (hoặc nhiều client) cùng một **tailnet Tailscale**. SMB **không** được mở ra Internet. Client chỉ **đọc / mở / copy**. Server vẫn ghi file trực tiếp vào `D:\SharedFiles` bằng tài khoản Administrator của laptop chủ.

```text
SERVER (Windows 11)
    │
    ├── D:\SharedFiles
    │
    └── SMB Share  SharedFiles
          │
          │ Tailscale VPN (100.x.x.x)
          │
          ├──────── CLIENT A
          ├──────── CLIENT B
          └──────── CLIENT C
```

File trong thư mục này:

| File | Máy nào chạy |
|---|---|
| `setup-server.ps1` | Laptop **SERVER** |
| `setup-client.ps1` | Mỗi laptop **CLIENT** |

Yêu cầu: Windows 11, Windows PowerShell **5.1** (không cần PowerShell 7), quyền Administrator, `winget`.

---

## 1. Server setup

1. Mở **Windows PowerShell 5.1 64-bit** bằng **Run as administrator**  
   (`C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe`).
2. Chuyển tới thư mục chứa script:

   ```powershell
   cd <thư-mục-chứa-script>
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
   .\setup-server.ps1
   ```

3. Script sẽ:

   - Từ chối chạy nếu không phải Administrator.
   - Kiểm tra Windows 11.
   - Cài Tailscale bằng `winget` nếu chưa có (**không** tự login).
   - Kiểm tra ổ `D:\` **đã tồn tại**. Nếu không có `D:\`: báo lỗi và **dừng**. Không format, không partition, không xóa disk.
   - Tạo `D:\SharedFiles` nếu chưa có. Nếu đã có: **giữ nguyên dữ liệu**.
   - Tạo local user `shareuser` (không phải Administrator). Password nhập bằng `Read-Host -AsSecureString`.
   - Gán NTFS **Read / Read & Execute / List folder contents** cho `shareuser` **chỉ trên** `D:\SharedFiles`.
   - Tạo SMB share `SharedFiles` với share permission **Read**.
   - Tắt SMB1 nếu đang bật; giữ SMB2/SMB3.
   - Tạo firewall rule TCP 445 **chỉ** từ dải Tailscale `100.64.0.0/10` (không mở 445 ra Internet).

Biến cấu hình (đầu `setup-server.ps1`):

```powershell
$SharePath = "D:\SharedFiles"
$ShareName = "SharedFiles"
$ShareUser = "shareuser"
```

**Không** điền password vào file.

Khi xong, màn hình in:

```text
========================================
 FILE SERVER READY
========================================

Tailscale IP:
100.x.x.x

SMB Share:
\\100.x.x.x\SharedFiles

Username:
shareuser
```

Password **không** được in ra. Ghi IP này để điền vào client.

Thêm file vào share bằng Explorer trên **chính server**: mở `D:\SharedFiles` bằng tài khoản admin của bạn, copy file vào. Không dùng `shareuser` để upload.

---

## 2. Tailscale login

Script **không** gọi `tailscale login` và **không** lưu credential Tailscale.

Trên **mỗi** máy (server và client), cùng một tailnet:

1. Cài Tailscale (script dùng `winget install Tailscale.Tailscale` nếu thiếu).
2. Mở app Tailscale ở khay hệ thống.
3. Log in bằng browser.
4. Đợi trạng thái **Connected**.
5. Quay lại cửa sổ PowerShell, nhấn Enter để script kiểm tra lại.

Cùng tài khoản Tailscale / cùng tailnet. Máy khác tailnet sẽ không thấy `100.x.x.x` của server.

Không port-forward trên router. Không bật UPnP cho SMB.

---

## 3. Client setup

Trên mỗi client Windows 11:

1. PowerShell **Run as administrator**.
2. Mở `setup-client.ps1`, có thể điền sẵn IP server:

   ```powershell
   $ServerTailscaleIP = "100.101.102.103"
   $ShareName         = "SharedFiles"
   $DriveLetter       = "Z:"
   $ShareUser         = "shareuser"
   ```

   Để trống `$ServerTailscaleIP` thì script hỏi:

   ```text
   Enter Tailscale IP of server:
   ```

3. Chạy:

   ```powershell
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
   .\setup-client.ps1
   ```

4. Log in Tailscale nếu chưa Connected (cùng tailnet với server).
5. Nhập password `shareuser` khi `Get-Credential` hiện ra. Có thể chọn lưu vào **Windows Credential Manager**.
6. Script map `\\<IP>\SharedFiles` → `Z:` và kiểm tra read-only.

Nếu `Z:` đã map đúng share này → dùng lại. Nếu `Z:` đang dùng cho share/ổ khác → **không** ghi đè, không disconnect drive khác.

---

## 4. Cách lấy Tailscale IP

Trên **server** (sau khi Connected):

```powershell
tailscale ip -4
```

Hoặc:

```powershell
tailscale ip
```

Lấy dòng IPv4 dạng `100.x.x.x` (dải CGNAT `100.64.0.0/10`).

```powershell
tailscale status
```

Cột đầu tiên của máy server cũng là Tailscale IP. MagicDNS (nếu bật) cho tên `ten-may.tail-xxxx.ts.net`, nhưng script client dùng **IPv4** để map drive.

---

## 5. Cách truy cập SMB

Sau khi server sẵn sàng và cả hai máy Connected:

- Explorer → thanh địa chỉ:

  ```text
  \\100.x.x.x\SharedFiles
  ```

- Username: `shareuser`  
  Nếu Windows hỏi dạng domain, thử:

  ```text
  TEN-MAY-SERVER\shareuser
  ```

  (`TEN-MAY-SERVER` = tên Computer của laptop chủ, Settings → System → About.)

- Password: password đã đặt khi chạy `setup-server.ps1`.

Client **không** dùng tài khoản Microsoft / PIN của server.

---

## 6. Cách map Z:

Cách 1 — chạy `setup-client.ps1` (khuyến nghị).

Cách 2 — thủ công, PowerShell:

```powershell
net use Z: \\100.x.x.x\SharedFiles /user:shareuser /persistent:yes
```

Cách 3 — Explorer: This PC → Map network drive → Drive `Z:` → Folder `\\100.x.x.x\SharedFiles` → Connect using different credentials.

Nếu script chạy **elevated** mà Explorer không thấy `Z:`, đó là tách token UAC. `setup-client.ps1` bật `EnableLinkedConnections` (không tắt UAC). Nếu vẫn không thấy: sign out/in, hoặc map lại từ cửa sổ PowerShell **không** Run as administrator.

---

## 7. Troubleshooting

Client kiểm tra theo thứ tự: **Tailscale Connected → server reachable → TCP 445 → SMB share**. Không dựa vào ping.

| Triệu chứng | Việc nên kiểm |
|---|---|
| `ERROR: Please run this script as Administrator.` | Chuột phải PowerShell → Run as administrator. |
| `Drive D:\ does not exist` | Gắn ổ / gán letter `D:`. Script **không** format disk. |
| `Please login to Tailscale first.` | Mở app Tailscale, login, Connected, chạy lại script. |
| `Test-NetConnection` TCP 445 fail | Server tắt/sleep; sai IP; Tailscale khác tailnet; firewall; `LanmanServer` chưa chạy. |
| `net use` sai mật khẩu | Gõ lại password `shareuser`. Thử `COMPUTERNAME\shareuser`. |
| Access Denied khi **đọc** | User không phải `shareuser`; ACL bị sửa tay; share tên khác. |
| Access Denied khi **ghi** | Đúng thiết kế. |
| `Z:` đã dùng | Đổi `$DriveLetter` hoặc tự `net use Z: /delete` nếu bạn chủ động muốn. |
| Explorer không thấy `Z:` | UAC / `EnableLinkedConnections`. Sign out/in. |
| Windows 11 24H2, map bằng IP bị Access Denied | Kết nối workgroup + user local dùng NTLM. Kiểm tra policy chặn NTLM outbound. |
| Office báo không lưu được / file lock | Đúng: client không được tạo file `~$...`. Mở **Read-only**. |
| `winget` không có | Cài **App Installer** từ Microsoft Store. Script không tải exe từ URL lạ. |

Lệnh hữu ích trên **server**:

```powershell
Get-Service LanmanServer
Get-SmbShare -Name SharedFiles
Get-SmbShareAccess -Name SharedFiles
Get-SmbServerConfiguration | Select-Object EnableSMB1Protocol, EnableSMB2Protocol
tailscale ip -4
Get-NetFirewallRule -DisplayName 'SMB-Tailscale-SharedFiles-In'
```

Trên **client**:

```powershell
tailscale status
Test-NetConnection 100.x.x.x -Port 445
net use
Get-PSDrive Z
```

---

## 8. Uninstall / rollback

Rollback **không** xóa file trong `D:\SharedFiles` trừ khi bạn tự xóa.

### Client

```powershell
net use Z: /delete
cmdkey /delete:100.x.x.x
```

Gỡ Tailscale (tùy chọn):

```powershell
winget uninstall Tailscale.Tailscale
```

### Server

```powershell
Remove-SmbShare -Name SharedFiles -Force
Remove-NetFirewallRule -DisplayName 'SMB-Tailscale-SharedFiles-In'
```

Bật lại rule SMB mặc định nếu bạn cần chia sẻ LAN (chỉ khi hiểu rõ hệ quả):

```powershell
Get-NetFirewallRule | Where-Object { $_.Name -like 'FPS-SMB*' } | Enable-NetFirewallRule
```

Xóa user SMB (tùy chọn, không bắt buộc):

```powershell
Remove-LocalUser -Name shareuser
```

Gỡ Tailscale: `winget uninstall Tailscale.Tailscale`.

**Không** chạy `icacls D:\ /reset`. Chỉ folder share đã bị cắt inheritance:

```powershell
# Khôi phục inheritance từ D:\ (chỉ khi bạn muốn SharedFiles trở lại ACL cũ của ổ D:)
icacls D:\SharedFiles /inheritance:e
```

Dữ liệu file vẫn còn; chỉ ACL thay đổi.

---

## 9. Cách kiểm tra server đang read-only

### Tự động

`setup-client.ps1` sau khi map:

- Test 1: liệt kê thư mục → **PASS**.
- Test 2: thử tạo `__write_test__.tmp`. Kỳ vọng **Access Denied**. Nếu tạo được: `SECURITY ERROR: SMB share is writable.` rồi xóa file test. Không đụng file thật.

### Thủ công trên client (sau khi map Z:)

```powershell
Get-ChildItem Z:\                          # phải được
Copy-Item Z:\somefile.txt $env:TEMP        # phải được (copy về máy local)
New-Item Z:\__should_fail__.txt -ItemType File   # phải Access Denied
```

Trong Explorer: mở file được; Save As lên `Z:` phải thất bại; Delete/Rename phải thất bại.

### Trên server (ACL, không cần password)

```powershell
Get-SmbShareAccess -Name SharedFiles
# shareuser = Read, không phải Change / Full Control

Get-Acl D:\SharedFiles | Select-Object -ExpandProperty Access
# shareuser: ReadAndExecute / Read — không có Write, Modify, Delete, FullControl
# BUILTIN\Users / Everyone không được có Write trên folder này
```

Validation cuối `setup-server.ps1` in:

```text
[OK] Administrator
[OK] Windows 11
[OK] Tailscale installed
[OK] Tailscale connected
[OK] Shared folder exists
[OK] SMB service running
[OK] SMB share exists
[OK] Share permission = Read
[OK] NTFS permission = Read-only
[OK] Firewall configured
```

---

## 10. Security considerations

### Vì sao phải **cả** Share + NTFS

Windows lấy **quyền chặt hơn** của hai lớp khi truy cập qua SMB.

| Lớp | shareuser |
|---|---|
| SMB Share | Read (không Change, không Full Control) |
| NTFS trên `D:\SharedFiles` | Read, Read & Execute, List folder contents |

Chỉ Share = Read **chưa đủ**. User local mặc định thuộc `BUILTIN\Users`. Nếu `D:\SharedFiles` **kế thừa** Modify từ `D:\`, `shareuser` vẫn ghi được qua NTFS dù share là Read.

Script vì vậy:

- Cắt inheritance **chỉ** trên `D:\SharedFiles`.
- **Không** copy ACE inherited từ `D:\`.
- **Không** sửa ACL của `D:\` hay folder khác.
- Giữ `SYSTEM` + `Administrators` Full Control để chủ máy vẫn bỏ file vào share.
- Không thêm `shareuser` vào Administrators.

Copy file vẫn được: client **đọc** trên SMB rồi **ghi ra ổ local**. Đó không phải quyền Write trên share.

### Firewall

- Không tắt Windows Firewall, Defender, UAC.
- Không mở TCP 445 tới `Any` / Internet.
- Không port-forward, không UPnP.
- Rule `SMB-Tailscale-SharedFiles-In`: inbound TCP 445 từ `100.64.0.0/10` (và IPv6 Tailscale nếu gán được), ưu tiên bind vào adapter tên Tailscale.
- Rule SMB-In mặc định (`FPS-SMB*`) dạng allow-from-Any bị **tắt** để LAN/Internet không dùng 445.

**Giới hạn Windows Firewall:** Windows không có cách 100% ổn định để nói “chỉ interface Tailscale” (tên adapter có thể đổi). Dải `100.64.0.0/10` là cách được hỗ trợ. Nếu bind adapter thất bại, script **không** fallback sang mở 445 global — chỉ dùng remote IP CGNAT và in cảnh báo. Chạy lại `setup-server.ps1` sau khi Tailscale Connected để bind adapter.

Laptop sleep/hibernate = share offline.

### SMB

- SMB1 không được bật.
- SMB2/SMB3 giữ bật (cùng stack).
- Guest auth không được bật bởi script.

### Mật khẩu / tài khoản

- Không hard-code password.
- `shareuser` chỉ để SMB; ai có password + nằm trong tailnet đều đọc được share.
- Nên đặt password mạnh và **Tailscale ACL** hạn chế ai tới TCP 445 của server (khuyến nghị, làm trên admin console Tailscale, không nằm trong script).

### Những gì script cố ý không làm

- Không format / xóa disk.
- Không disconnect network drive khác trên client.
- Không tự login Tailscale.
- Không tắt firewall để “cho dễ chạy”.
- Không đảm bảo firewall bên thứ ba (ESET, Norton, …). Cần cho phép SMB từ dải Tailscale trên sản phẩm đó nếu chúng thay Windows Firewall.

### BitLocker / vật lý

SMB read-only **không** thay mã hóa ổ. Nên BitLocker `D:\`. Ai ngồi trước server với quyền admin vẫn sửa được file — đó là cách bạn nạp nội dung.

---

## Checklist (sau khi viết / khi review)

| Hạng mục | Trạng thái |
|---|---|
| Windows 11 | Có (build ≥ 22000) |
| PowerShell 5.1 | Có (không dùng cú pháp PS7) |
| Tailscale | Cài bằng winget; không tự login |
| SMB2/SMB3 | Bật |
| SMB1 not enabled | Tắt nếu đang bật |
| Read-only | Share Read **và** NTFS RX |
| Copy works | Đọc SMB + ghi local |
| Write / Delete / Rename / Upload blocked | Cả hai lớp quyền |
| Firewall safe | Không disable firewall |
| TCP 445 not exposed to Internet | Chỉ `100.64.0.0/10` (+ bind adapter nếu được) |
| No hard-coded password | `Read-Host` / `Get-Credential` |
| No destructive operations | Không format, không xóa data share |
| Idempotent | Chạy lại không nhân share, không xóa user, không reset password sẵn có |
| Error handling | `try/catch`, log, exit code |
| Rollback | Mục 8 |

---

## Điểm Windows 11 không thể đảm bảo 100% bằng script

1. **Bind firewall đúng một interface Tailscale** — tên/alias adapter không ổn định. Đã thiết kế theo remote CGNAT + bind best-effort, không mở 445 ra Internet.
2. **Firewall / antivirus hãng khác** — script chỉ cấu hình Windows Defender Firewall.
3. **NTLM trên Windows 11 24H2** — share workgroup + user local + kết nối bằng IP dùng NTLM. Nếu tổ chức chặn NTLM outbound, map drive sẽ fail; không thể chuyển sang Kerberos nếu không có domain.
4. **Z: trong Explorer khi script chạy elevated** — hạn chế UAC; đã bật `EnableLinkedConnections`, có thể cần sign out.
5. **Ứng dụng cần file lock/temp trên share** (một số phiên bản Office) — không mở được để sửa; phù hợp mục tiêu read-only.
