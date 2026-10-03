# SAA-C03 — Học qua bối cảnh thực tế

Bộ tài liệu này viết lại 684 câu hỏi trong đề SAA-C03 theo hướng **hiểu vì sao**, thay vì nhớ keyword. Mỗi câu được dịch sang tiếng Việt, đặt vào một tình huống kinh doanh có thật, chỉ rõ nó nằm ở tầng nào trong một hệ thống lớn, và đối chiếu với công cụ tương đương ngoài AWS.

## Thứ tự đọc

| File | Nội dung | Trạng thái |
|---|---|---|
| [00-ban-do-he-thong.md](00-ban-do-he-thong.md) | **Đọc trước.** Bản đồ 12 tầng của một hệ thống lớn, mỗi service AWS ngồi ở đâu, tương đương ngoài AWS, và ba câu hỏi thay thế cho việc nhớ 300 keyword | Xong |
| [phan-01-cau-001-020.md](phan-01-cau-001-020.md) | Câu 1–20 | Xong |
| [phan-02-cau-021-040.md](phan-02-cau-021-040.md) | Câu 21–40 | Xong |
| [phan-03-cau-041-060.md](phan-03-cau-041-060.md) | Câu 41–60 | Xong |
| [phan-04-cau-061-080.md](phan-04-cau-061-080.md) | Câu 61–80 | Xong |
| [phan-05-cau-081-100.md](phan-05-cau-081-100.md) | Câu 81–100 | Xong |
| [phan-06-cau-101-120.md](phan-06-cau-101-120.md) | Câu 101–120 | Xong |
| [phan-07-cau-121-140.md](phan-07-cau-121-140.md) | Câu 121–140 | Xong |
| [phan-08-cau-141-160.md](phan-08-cau-141-160.md) | Câu 141–160 | Xong |
| [phan-09-cau-161-180.md](phan-09-cau-161-180.md) | Câu 161–180 | Xong |
| [phan-10-cau-181-200.md](phan-10-cau-181-200.md) | Câu 181–200 | Xong |
| [phan-11-cau-201-220.md](phan-11-cau-201-220.md) | Câu 201–220 | Xong |
| [phan-12-cau-221-240.md](phan-12-cau-221-240.md) | Câu 221–240 | Xong |
| [phan-13-cau-241-260.md](phan-13-cau-241-260.md) | Câu 241–260 | Xong |
| [phan-14-cau-261-280.md](phan-14-cau-261-280.md) | Câu 261–280 | Xong |
| [phan-15-cau-281-300.md](phan-15-cau-281-300.md) | Câu 281–300 | Xong |
| [phan-16-cau-301-320.md](phan-16-cau-301-320.md) | Câu 301–320 | Xong |
| [phan-17-cau-321-340.md](phan-17-cau-321-340.md) | Câu 321–340 | Xong |
| [phan-18-cau-341-360.md](phan-18-cau-341-360.md) | Câu 341–360 | Xong |
| [phan-19-cau-361-380.md](phan-19-cau-361-380.md) | Câu 361–380 | Xong |
| [phan-20-cau-381-400.md](phan-20-cau-381-400.md) | Câu 381–400 | Xong |
| [phan-21-cau-401-420.md](phan-21-cau-401-420.md) | Câu 401–420 | Xong |
| [phan-22-cau-421-440.md](phan-22-cau-421-440.md) | Câu 421–440 | Xong |
| [phan-23-cau-441-460.md](phan-23-cau-441-460.md) | Câu 441–460 | Xong |
| [phan-24-cau-461-480.md](phan-24-cau-461-480.md) | Câu 461–480 | Xong |
| [phan-25-cau-481-500.md](phan-25-cau-481-500.md) | Câu 481–500 | Xong |
| [phan-26-cau-501-520.md](phan-26-cau-501-520.md) | Câu 501–520 | Xong |
| [phan-27-cau-521-540.md](phan-27-cau-521-540.md) | Câu 521–540 | Xong |
| [phan-28-cau-541-560.md](phan-28-cau-541-560.md) | Câu 541–560 | Xong |
| [phan-29-cau-561-580.md](phan-29-cau-561-580.md) | Câu 561–580 | Xong |
| [phan-30-cau-581-600.md](phan-30-cau-581-600.md) | Câu 581–600 | Xong |
| [phan-31-cau-601-620.md](phan-31-cau-601-620.md) | Câu 601–620 | Xong |
| [phan-32-cau-621-640.md](phan-32-cau-621-640.md) | Câu 621–640 | Xong |
| [phan-33-cau-641-660.md](phan-33-cau-641-660.md) | Câu 641–660 | Xong |
| [phan-34-cau-661-684.md](phan-34-cau-661-684.md) | Câu 661–684 | Xong |

Tổng: 684 câu. **Đã xong hết.**

## Chủ đề lặp lại nhiều nhất (cập nhật sau mỗi 100 câu)

Đề chỉ xoay quanh một số mẫu rất giới hạn. Bảng này đếm số lần mỗi chủ đề đã xuất hiện — nếu còn ít thời gian thì ôn theo thứ tự này. Phân tích chi tiết ở cuối [Phần 10](phan-10-cau-181-200.md).

Cập nhật sau 200 câu (ôn nhanh). Phần 21–34 (401–684) lặp lại cùng các mẫu này, thêm vài biến thể hay ra:

| Chủ đề mới / biến thể (401–684) | Ví dụ câu |
|---|---|
| RDS Multi-AZ **cluster** (failover nhanh + đọc standby) ≠ Multi-AZ instance | 420, 536, 575 |
| Compute Savings Plan khi đổi **family**; Instance SP chỉ EC2 | 417, 552 |
| DAX (μs) vs Redis tự cache | 361, 472, 561, 578 |
| Global Accelerator + **NLB** (UDP / game / VoIP) | 408, 461, 530, 647 |
| Egress-only IGW (IPv6); NAT GW (IPv4) | 470 |
| S3 interface endpoint khi **on-prem + DX** cần S3 | 667 |
| SnapStart (Java) vs provisioned concurrency | 573, 379, 516 |
| Aurora Serverless / v2 khi tải lởm hoặc vài giờ/tuần | 411, 511, 572, 574, 596 |
| Macie = PII; GuardDuty = threat; Security Hub = dashboard | 495, 533, 616 |
| SCP: EBS encrypt, tag, billing, CloudTrail, instance type | 419, 433, 488, 492, 619 |
| Snowball khi PB / uplink yếu; DataSync khi còn access lúc copy | 435, 445, 604, 659 |
| FSx Lustre persistent HPC; ONTAP = NFS+SMB | 646, 648, 658 |
| Local Zone khi cấm deploy Region gần nhà | 684 |
| Recycle Bin / vault lock snapshot; Object Lock WORM | 446, 453, 675 |

Cập nhật sau 200 câu:

| Chủ đề | Số lần | Các câu |
|---|---|---|
| SQS để tách và làm bền yêu cầu | 8 | 25, 45, 75, 87, 94, 164, 181, 195 |
| S3 Lifecycle và các tầng lưu trữ | 8 | 12, 69, 113, 126, 147, 153, 160, 199 |
| Multi-AZ so với read replica | 7 | 14, 90, 144, 182, 187, 191, 193 |
| CloudFront cho phân phối nội dung | 7 | 83, 104, 131, 141, 155, 166, 183 |
| Fargate cho container không quản máy | 6 | 58, 112, 128, 163, 187, 198 |
| IAM role thay vì access key tĩnh | 5 | 17, 61, 92, 179, 185 |
| S3 Object Lock cho WORM | 5 | 53, 85, 109, 154, 189 |
| S3 cộng Athena cho phân tích | 5 | 2, 51, 156, 192, 199 |
| KMS và quản lý khóa mã hóa | 5 | 61, 106, 121, 135, 189 |
| Secrets Manager tự luân phiên | 4 | 11, 13, 61, 86 |
| VPC Endpoint cho truy cập riêng tư | 4 | 4, 76, 176, 185 |
| Lambda cho xử lý theo sự kiện | 4 | 65, 107, 161, 184 |
| FSx for Windows (Windows + AD + SMB) | 4 | 6, 64, 97, 186 |
| Dịch vụ AI cho tài liệu và âm thanh | 3 | 68, 192, 199 |
| Dịch vụ có quản tương thích công nghệ cũ | 3 | 111, 188, 198 |
| API Gateway và bảo vệ API | 3 | 158, 180, 200 |
| SQS visibility timeout gây xử lý trùng | 2 | 67, 98 |
| ASG scale theo độ sâu hàng đợi | 2 | 8, 81 |
| Chứng chỉ import vào ACM không tự gia hạn | 2 | 62, 82 |

## Các câu có đáp án gây tranh chấp

Những câu dưới đây bị nhiều bộ đề dump ghi sai đáp án. Trong sách đã ghi rõ lý do và dẫn nguồn.

| Câu | Đáp án trong sách | Dump thường ghi | Căn cứ |
|---|---|---|---|
| 28 | B (two-way trust) | A (one-way trust) | Tài liệu AWS: *"One-way trusts do not work with IAM Identity Center."* |
| 36 | B (multi-Region KMS key) | D (khóa riêng mỗi Region) | Đề yêu cầu cứng "cùng một khóa KMS"; D tạo hai khóa khác nhau |
| 308 | B + C (RI Optimization, xem ở tài khoản payer) | A + C (xem ở từng tài khoản) | Với consolidated billing, RI được chia sẻ cho cả nhóm, nên khuyến nghị RI tính trên toàn nhóm ở tài khoản payer |
| 338 | D (Aurora global database, giữ một instance ở Region phụ) | A (binlog) hoặc B (bỏ hết instance) | Binlog vẫn tốn một instance mà nhiều việc vận hành hơn; cụm phụ không có instance thì không chuyển đổi dự phòng nhanh được |
| 342 | C (predictive scaling, khởi chạy trước 30 phút) | B (scheduled scaling) | Đề nói công ty không đủ người phân tích xu hướng capacity; scheduled scaling bắt họ tự chọn con số |
| 366 | D (usage plan cộng API key) | C (IAM chi tiết trên bảng DynamoDB) | Người dùng đến từ Cognito user pool, không có IAM credential; Lambda truy cập bảng bằng role của chính nó |
| 373 | D (Standard, sang Standard-IA sau 30 ngày, sang Deep Archive sau 1 năm) | A (Intelligent-Tiering) | Mẫu truy cập đã biết trước, và phí giám sát theo từng object của Intelligent-Tiering rất lớn khi có hàng nghìn tỷ object |
| 394 | C (io2) | B (tăng IOPS gp3) | Một volume gp3 tối đa 16.000 IOPS; nhưng RDS gp3 từ 400 GB được chia sọc nên lên tới 64.000 IOPS, nên trên RDS hiện nay B cũng chạy được |
| 638 | A (presigned URL) | D (Transfer Family SFTP) | Đề “ít ops + share nhân viên toàn cầu”; SFTP nuôi endpoint. Nếu đề nhấn SFTP/IdP thì D |
| 663 | C (S3 policy theo ECS role + SG RDS) | D (endpoint S3 + SG subnet) | “Chỉ ECS” = IAM task role, không mọi thứ trong subnet. Dump hay ghi D |
| 679 | Lifecycle expire 30 ngày, **không** Object Lock | A+C lock 30 ngày | Lock **cấm** tự xóa đúng hạn. Đề “automatically deleted after 30 days” = Lifecycle |

## Bố cục mỗi câu hỏi

- **Tình huống** — dịch tiếng Việt theo văn phong nghiệp vụ, giữ nguyên các chi tiết quyết định đáp án
- **Đáp án** và lý do chọn
- **Ngoài đời chuyện này xảy ra ở đâu** — ngành nào, công ty kiểu nào, hệ thống nào
- **Vị trí trong hệ thống lớn** — thuộc tầng nào trong 12 tầng ở Chương 0
- **Nếu không dùng AWS** — công cụ tương đương (on-prem, mã nguồn mở, nền tảng khác)
- **Vì sao các đáp án khác sai** — theo hậu quả nghiệp vụ, không theo lý thuyết

Cuối mỗi phần có mục tổng kết các **mẫu kiến trúc** đã xuất hiện. Đây là phần đáng ôn lại nhất trước ngày thi, vì đề chỉ lặp lại một số mẫu rất giới hạn.

## Lưu ý về nguồn

File đề gốc không kèm đáp án, nên đáp án trong tài liệu này do phân tích mà ra, kèm lý giải để bạn tự kiểm chứng. Chỗ nào có nhiều cách hiểu sẽ được ghi rõ. Nếu thấy đáp án nào đáng ngờ, hãy tra lại tài liệu AWS thay vì tin ngay.

Trong file gốc, khoảng 250 câu bị mất dòng tiêu đề `Question #N` khi convert từ PDF, nội dung vẫn còn nguyên. Số câu trong tài liệu này được đánh lại theo đúng thứ tự xuất hiện trong file gốc, nên có thể lệch so với số hiệu gốc ở một vài chỗ.
