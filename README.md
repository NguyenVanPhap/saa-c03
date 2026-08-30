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
| phan-06-cau-101-120.md | Câu 101–120 | Chưa |
| ... | ... | |

Tổng: 684 câu. Đã xong 100.

## Chủ đề lặp lại nhiều nhất (cập nhật sau mỗi 100 câu)

Đề chỉ xoay quanh một số mẫu rất giới hạn. Bảng này đếm số lần mỗi chủ đề đã xuất hiện — nếu còn ít thời gian thì ôn theo thứ tự này. Phân tích chi tiết ở cuối [Phần 5](phan-05-cau-081-100.md).

| Chủ đề | Số lần | Các câu |
|---|---|---|
| Hàng đợi làm bộ đệm giữa thành phần nhanh và chậm | 5 | 25, 45, 75, 87, 94 |
| Secrets Manager tự luân phiên | 4 | 11, 13, 61, 86 |
| S3 Gateway Endpoint | 4 | 4, 42, 72, 91, 92 |
| Multi-AZ so với read replica (standby RDS không đọc được) | 4 | 14, 90, 93, 95 |
| FSx for Windows (Windows + AD + SMB) | 3 | 6, 64, 97 |
| IAM role thay vì access key tĩnh | 3 | 17, 61, 92 |
| SQS visibility timeout gây xử lý trùng | 2 | 67, 98 |
| S3 Object Lock cho WORM | 2 | 53, 85 |
| ASG scale theo độ sâu hàng đợi | 2 | 8, 81 |
| Chứng chỉ import vào ACM không tự gia hạn | 2 | 62, 82 |

## Các câu có đáp án gây tranh chấp

Những câu dưới đây bị nhiều bộ đề dump ghi sai đáp án. Trong sách đã ghi rõ lý do và dẫn nguồn.

| Câu | Đáp án trong sách | Dump thường ghi | Căn cứ |
|---|---|---|---|
| 28 | B (two-way trust) | A (one-way trust) | Tài liệu AWS: *"One-way trusts do not work with IAM Identity Center."* |
| 36 | B (multi-Region KMS key) | D (khóa riêng mỗi Region) | Đề yêu cầu cứng "cùng một khóa KMS"; D tạo hai khóa khác nhau |

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
