# Chương 0 — Bản đồ một hệ thống lớn: mỗi service AWS ngồi ở đâu?

> Đọc chương này trước. Nó không có câu hỏi thi nào, nhưng nó là cái khung để 684 câu hỏi phía sau tự sắp vào chỗ của chúng.

## Vì sao học theo keyword thì không nhớ được

Khi bạn học "thấy *unpredictable access pattern* thì chọn S3 Intelligent-Tiering", bạn đang nhớ một cặp từ khóa rời rạc. Đề thi có khoảng 300 cặp như vậy. Não người không giữ được 300 cặp rời rạc trong một tuần.

Nhưng nếu bạn hiểu rằng: *một sàn thương mại điện tử có hàng trăm triệu ảnh sản phẩm, trong đó ảnh của sản phẩm đang hot thì được xem hàng nghìn lần một ngày, ảnh của sản phẩm ngừng bán thì cả tháng không ai xem, và cái oái oăm là không ai biết trước sản phẩm nào sẽ hot — nên phải có một cơ chế tự nó theo dõi từng file và tự chuyển tầng lưu trữ* — thì bạn không cần nhớ keyword nữa. Bạn nhớ **câu chuyện**, và keyword là hệ quả.

Cả quyển sách này được viết theo nguyên tắc đó. Mỗi câu hỏi sẽ được kể lại như một tình huống có thật của một công ty có thật, đặt vào đúng tầng của hệ thống, và đối chiếu với công cụ tương đương ngoài AWS mà có thể bạn đã biết.

## Hệ thống ví dụ xuyên suốt: sàn thương mại điện tử "MuaNhanh"

Để có chỗ neo, hãy tưởng tượng một sàn thương mại điện tử cỡ Tiki/Shopee: 20 triệu người dùng, 5 triệu sản phẩm, ngày thường 2.000 đơn/giờ, ngày sale 12/12 thì 80.000 đơn/giờ. Gần như mọi service trong đề thi SAA-C03 đều có chỗ đứng trong hệ thống này. Khi gặp câu hỏi về một service lạ, hãy tự hỏi: *"Nếu MuaNhanh cần cái này, nó sẽ nằm ở đâu?"*

Dưới đây là 12 tầng của hệ thống, đi từ ngón tay người dùng vào tới đáy dữ liệu.

---

## Tầng 1 — Người dùng bấm vào tên miền: DNS

**Việc cần làm:** biến `muanhanh.vn` thành một địa chỉ IP, và nếu có nhiều trung tâm dữ liệu thì phải chọn cái nào trả về.

**AWS:** Route 53.

Phần khó không phải là "phân giải tên miền" — cái đó ai cũng làm được. Phần khó là **chọn trả về IP nào**, và đây chính là chỗ đề thi hỏi. Cùng một tên miền, tùy tình huống kinh doanh mà cách chọn khác nhau:

- MuaNhanh mở rộng sang Singapore, muốn người ở Việt Nam vào server Việt Nam, người Singapore vào server Singapore, không phải vì luật mà chỉ vì cho nhanh → **latency-based routing**.
- MuaNhanh ra giao diện mới, muốn cho 5% người dùng thử trước xem có tăng tỷ lệ chốt đơn không → **weighted routing**. Đây chính là canary release / A-B test.
- MuaNhanh có hệ thống dự phòng ở Region khác, bình thường không dùng, chỉ bật khi Region chính sập → **failover routing**.
- MuaNhanh bán rượu, luật cấm bán ở một số quốc gia, phải chặn theo biên giới quốc gia → **geolocation routing**. Chú ý sự khác biệt: latency là vì *hiệu năng*, geolocation là vì *pháp lý hoặc nội dung*. Đề thi rất hay đánh lừa ở cặp này.

**Ngoài AWS:** Cloudflare DNS, Google Cloud DNS, Azure DNS. Trong trung tâm dữ liệu tự quản thì là BIND, và các kiểu routing trên phải làm bằng thiết bị GSLB của F5 hoặc Citrix — đắt và phức tạp hơn nhiều.

---

## Tầng 2 — Tầng biên: CDN, chống tấn công

**Việc cần làm:** ảnh sản phẩm, file JS, CSS không có lý do gì phải đi từ Việt Nam sang server mỗi lần có người xem. Và phải chặn được kẻ tấn công trước khi nó chạm tới ứng dụng.

**AWS:** CloudFront (CDN), AWS WAF (tường lửa ứng dụng), AWS Shield (chống DDoS), Global Accelerator.

Ở MuaNhanh, tầng này gánh khoảng 90% lưu lượng. Một trang sản phẩm có 1 lời gọi API lấy giá và tồn kho, nhưng có 40 file ảnh. 40 file ảnh đó CloudFront trả về từ điểm phát ở Hà Nội hoặc TP.HCM, server gốc không hề biết. Đây là lý do các công ty nội dung — báo điện tử, xem phim, nghe nhạc, game phát hành bản cập nhật — chi tiền cho CDN nhiều hơn cả chi cho server.

Bốn service ở tầng này rất hay bị nhầm lẫn với nhau, phân biệt bằng *loại tấn công hoặc loại lưu lượng*:

| Service | Giải quyết việc gì | Ví dụ đời thực ở MuaNhanh |
|---|---|---|
| CloudFront | Nội dung tĩnh, giảm độ trễ toàn cầu, cache | Ảnh sản phẩm, video review, file cài app |
| WAF | Tấn công tầng ứng dụng: SQL injection, XSS, bot quét giá | Chặn bot của đối thủ đang crawl toàn bộ bảng giá, giới hạn 100 request/5 phút mỗi IP |
| Shield | Tấn công cạn kiệt băng thông và kết nối (tầng 3/4) | Đối thủ thuê botnet dội 500 Gbps vào ngày sale |
| Global Accelerator | Không phải HTTP, cần IP tĩnh, cần đường đi ngắn nhất | Kênh chat/gọi trong app, server game, VoIP |

Khác biệt cốt lõi giữa CloudFront và Global Accelerator: **CloudFront giữ lại bản sao nội dung ở biên** (phù hợp HTTP, nội dung tĩnh), còn **Global Accelerator không cache gì cả, nó chỉ đưa gói tin vào mạng riêng của AWS sớm nhất có thể** (phù hợp TCP/UDP, nội dung động, game, VoIP). Nếu đề nói "UDP" hoặc "cần IP tĩnh để khách hàng doanh nghiệp mở firewall" thì đó là Global Accelerator hoặc NLB, không bao giờ là CloudFront.

**Ngoài AWS:** Cloudflare, Akamai, Fastly. WAF tự dựng thì là ModSecurity trên Nginx, hoặc thiết bị F5 ASM, Imperva. Chống DDoS ở tầng nhà mạng thì có Arbor Networks.

**Ai dùng nặng nhất:** Netflix, Disney+, các nền tảng xem phim — băng thông video là chi phí lớn nhất của họ. Các nhà phát hành game khi ra bản cập nhật 50 GB cho 10 triệu người tải cùng lúc. Các sàn TMĐT trong ngày sale.

---

## Tầng 3 — Cửa vào ứng dụng: cân bằng tải và API gateway

**Việc cần làm:** một tên miền, nhưng đằng sau là 200 server. Phải chia lưu lượng, phải phát hiện server nào chết để không gửi khách vào đó.

**AWS:** Application Load Balancer (ALB), Network Load Balancer (NLB), Gateway Load Balancer (GWLB), API Gateway.

Cách phân biệt dễ nhớ nhất là hỏi: **thiết bị này có cần đọc hiểu nội dung HTTP không?**

- **ALB** đọc được đường dẫn URL và tên miền. Nhờ vậy nó làm được việc mang tính kinh doanh: `muanhanh.vn/thanh-toan` đi vào nhóm server thanh toán (nhóm này chạy máy mạnh, đội ngũ riêng, deploy cẩn thận), `muanhanh.vn/tim-kiem` đi vào nhóm server tìm kiếm. Đây là nền tảng của kiến trúc microservice. Mọi công ty có microservice chạy trên AWS đều có ALB.
- **NLB** không đọc HTTP, chỉ chuyển gói tin ở tầng 4. Đổi lại nó cực nhanh, chịu được hàng triệu kết nối, và **có IP tĩnh**. Cái IP tĩnh này quan trọng về mặt kinh doanh hơn bạn tưởng: khi MuaNhanh tích hợp với một ngân hàng để nhận webhook thanh toán, bộ phận bảo mật của ngân hàng sẽ yêu cầu "cho chúng tôi một danh sách IP cố định để mở firewall". Ngân hàng không chấp nhận tên miền thay đổi IP. Lúc đó bạn buộc phải dùng NLB.
- **GWLB** là loại đặc biệt, sinh ra chỉ để đưa lưu lượng đi xuyên qua thiết bị tường lửa của hãng thứ ba (Palo Alto, Fortinet, Check Point). Bối cảnh: doanh nghiệp lớn đã mua giấy phép Palo Alto và có đội vận hành quen nó, khi lên mây họ không muốn đổi sang WAF của AWS. GWLB cho phép giữ nguyên thiết bị cũ. Thấy đề nói "third-party virtual appliance", "inspection VPC" thì gần như chắc chắn là GWLB.
- **API Gateway** đứng trước các API, làm những việc mà bản thân ALB không làm: xác thực token, giới hạn tốc độ theo từng khách hàng, quản lý phiên bản API, và tính tiền theo lượt gọi. Bối cảnh kinh doanh điển hình: MuaNhanh mở API cho các đối tác logistics và các shop lớn tự tích hợp, mỗi đối tác có một API key, gói miễn phí 1.000 lượt/ngày, gói trả tiền 1 triệu lượt/ngày.

**Ngoài AWS:** Nginx, HAProxy là ALB tự dựng. F5 BIG-IP là thiết bị vật lý làm cả ALB và NLB. Kong, Apigee, WSO2 là API Gateway tự dựng.

---

## Tầng 4 — Nơi code chạy: máy chủ, container, hàm

**Việc cần làm:** thực thi logic nghiệp vụ.

**AWS:** EC2 + Auto Scaling Group, ECS/EKS (+ Fargate), Lambda, AWS Batch.

Đây là tầng có nhiều lựa chọn nhất, và tiêu chí chọn gần như luôn là **đánh đổi giữa quyền kiểm soát và công sức vận hành**:

- **EC2** là máy ảo, bạn toàn quyền và cũng toàn bộ trách nhiệm: vá lỗi hệ điều hành, cài agent, xử lý ổ đĩa đầy. Ai dùng? Hệ thống cũ vừa chuyển từ trung tâm dữ liệu lên mây mà chưa kịp viết lại (lift-and-shift), phần mềm thương mại chỉ hỗ trợ chạy trên máy chủ (SAP, Oracle), và các tải cần phần cứng đặc thù như GPU cho huấn luyện AI.
- **Auto Scaling Group** là thứ khiến EC2 khác hẳn máy chủ trong phòng máy: nó tự thêm máy khi tải lên và tự bỏ máy khi tải xuống. MuaNhanh ngày thường chạy 20 máy, 20h ngày 12/12 chạy 300 máy, 2h sáng còn 8 máy. Trong trung tâm dữ liệu tự quản, bạn phải mua sẵn 300 máy và để chúng chạy không tải 360 ngày một năm. Đây là lý do kinh tế lớn nhất để lên mây.
- **ECS/EKS trên Fargate** là container mà không phải quản máy chủ bên dưới. Ai dùng? Công ty đã chuẩn hóa quy trình phát hành bằng Docker, có nhiều microservice, muốn deploy nhanh nhiều lần một ngày.
- **Lambda** là hàm chạy khi có sự kiện, tối đa 15 phút, không trả tiền khi không chạy. Điểm mấu chốt về nghiệp vụ: nó phù hợp với công việc *thưa và giật cục*. Ví dụ ở MuaNhanh: mỗi khi shop tải lên một ảnh sản phẩm, cần tạo ra 5 kích cỡ ảnh khác nhau. Ngày có 3.000 ảnh, ngày có 90.000 ảnh. Nuôi một dàn server để chờ việc này thì vô lý.
- **AWS Batch** dành cho công việc tính toán dài hàng giờ, xếp hàng chờ tài nguyên. Ai dùng? Ngân hàng chạy mô hình rủi ro cuối ngày, hãng dược so trình tự gen, hãng phim render từng khung hình, hãng xe mô phỏng va chạm.

Về **chi phí** thì tầng này chia ba kiểu mua, và đây là chỗ đề thi hỏi rất nhiều:

- Tải chạy liên tục, biết trước sẽ dùng ít nhất 1–3 năm → **Savings Plans / Reserved Instances**, giảm tới ~72%. Giống như thuê nhà dài hạn thì rẻ hơn thuê tháng.
- Tải chịu được bị ngắt giữa chừng → **Spot**, giảm tới ~90%. AWS bán rẻ công suất dư và có quyền lấy lại sau 2 phút báo trước. Dùng cho render phim, xử lý ảnh, huấn luyện mô hình có lưu điểm dừng, xử lý hàng đợi. **Không** dùng cho database hay server web đang phục vụ khách.
- Tải bất thường không đoán được → **On-Demand**, đắt nhất nhưng linh hoạt.

Hai loại nữa hay bị nhầm: **Dedicated Host** là khi bạn phải trả tiền giấy phép phần mềm theo số socket/số core vật lý (Oracle, SQL Server, Windows Server mua theo kiểu cũ) — bạn cần biết chính xác mình đang chiếm máy vật lý nào để khai báo giấy phép. **Dedicated Instance** chỉ đảm bảo không chia sẻ máy vật lý với công ty khác, thường vì yêu cầu tuân thủ, nhưng không cho bạn nhìn thấy phần cứng. Thấy chữ "license" gắn với "per-core" hoặc "per-socket" thì chọn Dedicated **Host**.

**Ngoài AWS:** EC2 tương đương máy ảo trên VMware vSphere. EKS tương đương Kubernetes tự dựng hoặc OpenShift. Lambda tương đương Knative, OpenFaaS. AWS Batch tương đương Slurm, PBS, LSF trong các trung tâm siêu máy tính.

---

## Tầng 5 — Tầng đệm và điều phối: hàng đợi, sự kiện, luồng

Đây là tầng mà người mới thường không hiểu để làm gì, nhưng nó là **tầng quan trọng nhất trong đề thi SAA-C03** và cũng là thứ phân biệt một hệ thống nghiệp dư với một hệ thống chịu được ngày 12/12.

**Vấn đề thực tế:** khách bấm "Đặt hàng". Để hoàn tất một đơn hàng cần: trừ tồn kho, tạo mã đơn, gọi cổng thanh toán, gửi email, gửi thông báo đẩy, đẩy đơn sang hệ thống kho, ghi vào hệ thống báo cáo, cộng điểm thưởng. Nếu làm tuần tự trong một lời gọi HTTP thì khách phải chờ 8 giây, và nếu dịch vụ email đang lỗi thì đơn hàng thất bại — dù việc gửi email chẳng liên quan gì đến chuyện khách đã trả tiền hay chưa.

**Cách làm đúng:** ghi nhận đơn hàng, đẩy một tin nhắn vào hàng đợi, trả về cho khách trong 200 ms. Các việc còn lại xử lý phía sau. Đây gọi là **decoupling** — tách rời.

**AWS:** SQS, SNS, EventBridge, Kinesis, Step Functions.

- **SQS** là hàng đợi công việc. Mỗi tin nhắn được một nơi xử lý, xử lý xong thì xóa, xử lý lỗi thì tự thử lại, thử mãi không được thì rơi vào **dead-letter queue** để người ta vào xem. Giá trị kinh doanh lớn nhất của SQS là **hấp thụ đỉnh tải**: ngày sale đơn về gấp 40 lần, hàng đợi phình lên, nhóm máy xử lý cứ rút ra từ từ theo tốc độ nó chịu được. Database phía sau không sập. Nếu không có hàng đợi, cú sốc 40 lần đó đập thẳng vào database.
- **SQS FIFO** khi thứ tự bắt buộc phải đúng. Ví dụ: lệnh "nạp 100k vào ví" rồi "trừ 80k" — đảo thứ tự là số dư âm. Ví điện tử, sàn chứng khoán, hệ thống kế toán cần FIFO. Còn gửi email thông báo thì thứ tự không quan trọng, dùng standard queue rẻ và nhanh hơn.
- **SNS** là loa phát thanh: một thông báo, nhiều nơi cùng nhận. Kết hợp SNS + nhiều SQS (gọi là **fanout**) là mẫu kiến trúc kinh điển: sự kiện "đơn hàng đã thanh toán" được phát một lần, phòng kho nhận một bản, phòng kế toán nhận một bản, hệ thống email nhận một bản, mỗi bên có hàng đợi riêng và tự xử lý theo tốc độ của mình. Thêm phòng ban mới thì chỉ cần đăng ký thêm, không ai phải sửa code chỗ đặt hàng.
- **EventBridge** là SNS thông minh hơn: nó lọc được nội dung sự kiện ("chỉ gửi cho tôi đơn trên 10 triệu đồng"), nhận sự kiện từ chính hạ tầng AWS ("có người vừa tắt máy chủ production"), nhận sự kiện từ dịch vụ SaaS bên ngoài, và chạy được theo lịch. Nó là xương sống của kiến trúc event-driven.
- **Kinesis Data Streams** là dòng chảy dữ liệu liên tục, giữ lại được và cho nhiều nơi đọc lại từ đầu. Khác SQS ở chỗ: SQS xử lý xong là xóa, Kinesis giữ bản ghi trong nhiều giờ đến nhiều ngày và nhiều bên đọc độc lập. Dùng cho **clickstream** — mỗi cú nhấp chuột của 20 triệu người dùng — để đồng thời: gợi ý sản phẩm theo thời gian thực, phát hiện gian lận, và nạp vào kho dữ liệu. Đây chính là Apache Kafka phiên bản có người quản.
- **Kinesis Data Firehose** là đường ống chỉ làm một việc: hứng dữ liệu rồi tự đổ vào S3, Redshift hoặc OpenSearch, không cần viết dòng code nào. Trong đề, "real-time" nghiêng về Data Streams, "near real-time và không muốn quản lý gì" là Firehose.
- **Step Functions** điều phối một quy trình nhiều bước có trạng thái, có nhánh rẽ, có chờ người duyệt. Bối cảnh kinh doanh: quy trình mở tài khoản ngân hàng — nhận ảnh giấy tờ, gọi OCR, đối chiếu danh sách đen, nếu điểm rủi ro cao thì chuyển cho người thẩm định, chờ có thể tới 2 ngày, rồi mới kích hoạt tài khoản. Quy trình này không thể nhồi vào một hàm Lambda 15 phút.

**Ngoài AWS:** SQS ↔ RabbitMQ, ActiveMQ. SNS/EventBridge ↔ Kafka, NATS. Kinesis ↔ Apache Kafka (gần như một-đối-một). Firehose ↔ Logstash/Fluentd hoặc Kafka Connect. Step Functions ↔ Airflow, Temporal, Camunda.

**Ai dùng nặng nhất:** Netflix xây đường ống dữ liệu khổng lồ trên Kinesis để thu mọi sự kiện xem phim. Các công ty quảng cáo trực tuyến sống bằng clickstream. Ví điện tử và sàn chứng khoán dùng FIFO. Mọi hệ thống TMĐT dùng SQS cho luồng đơn hàng.

---

## Tầng 6 — Dữ liệu nóng: database giao dịch và cache

**Việc cần làm:** lưu đơn hàng, số dư, tồn kho, thông tin người dùng — những thứ mà đọc sai hoặc mất là chết.

**AWS:** RDS, Aurora, DynamoDB, ElastiCache.

Câu hỏi đầu tiên luôn là **dữ liệu này có quan hệ hay không**:

- **RDS** là MySQL/PostgreSQL/SQL Server/Oracle có AWS lo hộ việc sao lưu, vá lỗi, dựng bản dự phòng. Dùng cho dữ liệu cần tính nhất quán chặt và cần `JOIN`: đơn hàng, hóa đơn, sổ kế toán, hồ sơ nhân sự. Hầu hết hệ thống ERP, core banking, quản lý bệnh viện đều là quan hệ.
- **Aurora** là RDS bản hiệu năng cao do AWS tự viết lại phần lưu trữ, tương thích MySQL/PostgreSQL. Chọn Aurora khi cần nhiều bản đọc (tới 15), chuyển đổi dự phòng nhanh (dưới 30 giây), hoặc cần trải ra nhiều Region (**Aurora Global Database** — dùng khi công ty có người dùng ở nhiều châu lục mà vẫn cần một database quan hệ duy nhất).
- **DynamoDB** là NoSQL khóa–giá trị, độ trễ vài milli-giây bất kể dữ liệu 1 GB hay 100 TB. Đổi lại: không `JOIN`, phải thiết kế theo cách truy vấn từ đầu. Dùng khi lượng truy cập cực lớn và mẫu truy vấn đơn giản: giỏ hàng, phiên đăng nhập, trạng thái người chơi game, bảng xếp hạng, dữ liệu IoT, catalogue sản phẩm tra theo mã.
- **ElastiCache** đặt giữa ứng dụng và database để nhớ tạm kết quả. Vì sao cần? Trang chủ MuaNhanh gọi cùng một câu truy vấn "20 sản phẩm bán chạy nhất" 500.000 lần mỗi giờ, nhưng kết quả chỉ đổi 5 phút một lần. Cache biến 500.000 lần đọc database thành 12 lần. Redis còn dùng cho bảng xếp hạng, đếm lượt xem, và giữ phiên đăng nhập.

**Phân biệt hai thứ rất hay bị nhầm trong đề:**

- **RDS Multi-AZ** là để *không sập*: có một bản dự phòng đồng bộ ở AZ khác, chính sập thì tự chuyển sang. Bản dự phòng đó **không phục vụ đọc**.
- **Read Replica** là để *đọc nhanh hơn*: bản sao không đồng bộ tức thì, dùng cho báo cáo, tìm kiếm, trang danh sách sản phẩm.

Đề thi rất thích ra đáp án "dùng Multi-AZ để tăng khả năng đọc" — luôn sai.

**Ngoài AWS:** RDS ↔ MySQL/PostgreSQL tự cài trên máy ảo, Oracle RAC. Aurora ↔ Percona Cluster, Vitess. DynamoDB ↔ Cassandra, ScyllaDB, MongoDB, HBase. ElastiCache ↔ Redis/Memcached tự dựng.

**Ai dùng nặng nhất:** DynamoDB được các công ty game và ứng dụng có hàng chục triệu người dùng đồng thời dùng rất nặng — Duolingo công khai chia sẻ họ lưu hàng chục tỷ bản ghi trên DynamoDB, các tựa game battle royale dùng nó cho trạng thái người chơi. Capital One là ví dụ nổi tiếng về một ngân hàng đóng toàn bộ trung tâm dữ liệu để chuyển sang AWS với Aurora và DynamoDB.

---

## Tầng 7 — Dữ liệu lạnh và phân tích: kho, hồ, và báo cáo

**Việc cần làm:** giám đốc muốn biết doanh thu theo ngành hàng theo tỉnh trong 3 năm. Câu truy vấn này quét 4 tỷ dòng. Không được chạy nó trên database đang phục vụ khách.

**AWS:** S3, Glue, Athena, Redshift, EMR, QuickSight, OpenSearch.

Đây là kiến trúc **data lake**, và thứ tự các mảnh gần như luôn giống nhau:

1. **S3** là hồ chứa. Mọi thứ đổ vào đây: bản sao database, log web, clickstream, file đối tác gửi. S3 rẻ, không giới hạn dung lượng, độ bền cực cao. Trong mọi kiến trúc dữ liệu hiện đại trên AWS, S3 là trung tâm.
2. **Glue** đi quét S3, đoán ra cấu trúc dữ liệu và ghi vào một danh mục (catalog), để các công cụ khác biết trong hồ có bảng gì cột gì. Glue cũng chạy các bước làm sạch và biến đổi dữ liệu (ETL).
3. **Athena** cho phép chạy SQL trực tiếp trên file trong S3, trả tiền theo lượng dữ liệu quét. Đây là lựa chọn cho truy vấn **thỉnh thoảng, không định trước**: "cho tôi xem log 3 hôm trước để điều tra sự cố". Không phải dựng cụm máy nào cả.
4. **Redshift** là kho dữ liệu thật sự, dành cho báo cáo chạy hàng ngày, dashboard nhiều người xem, truy vấn phức tạp trên hàng tỷ dòng. Nó tốn tiền cố định nên chỉ đáng khi có nhu cầu phân tích thường xuyên và nặng.
5. **EMR** là cụm Hadoop/Spark có người quản, dành cho việc mà SQL không làm được: xử lý dữ liệu quy mô lớn bằng code, huấn luyện mô hình, biến đổi phức tạp.
6. **QuickSight** là công cụ vẽ biểu đồ để người không biết SQL cũng xem được.
7. **OpenSearch** dành cho tìm kiếm toàn văn và soi log: ô tìm kiếm sản phẩm gợi ý ngay khi đang gõ, hoặc đội vận hành tìm một mã lỗi trong 2 tỷ dòng log.

Ranh giới **Athena vs Redshift** là chỗ đề hỏi nhiều nhất. Quy tắc: đề nói "ad-hoc", "occasional", "simple queries", "minimal changes to architecture", "least operational overhead" → **Athena**. Đề nói "complex joins", "dashboard cho nhiều người dùng", "petabyte-scale data warehouse" → **Redshift**.

**Ngoài AWS:** S3 ↔ MinIO, Ceph, HDFS, NetApp StorageGRID. Athena ↔ Presto/Trino. Redshift ↔ Teradata, Vertica, Greenplum, Snowflake, BigQuery. EMR ↔ Hadoop/Cloudera tự dựng. QuickSight ↔ Tableau, Power BI, Metabase. OpenSearch ↔ Elasticsearch + Kibana tự dựng, Splunk.

**Ai dùng nặng nhất:** gần như mọi công ty có bộ phận dữ liệu. Sàn TMĐT dùng để tính gợi ý sản phẩm và định giá. Nhà mạng dùng để phân tích hành vi thuê bao. Ngân hàng dùng để báo cáo cho cơ quan quản lý. Netflix nổi tiếng với việc xây toàn bộ kho dữ liệu trên S3 thay vì database truyền thống.

---

## Tầng 8 — Lưu trữ file: đĩa, thư mục chia sẻ

**Việc cần làm:** ứng dụng cần một ổ đĩa hoặc một thư mục để đọc ghi file.

**AWS:** EBS, EFS, FSx, Instance Store.

Đây là tầng dễ nhất nếu bạn hỏi đúng một câu: **có bao nhiêu máy cần dùng chung file này?**

- **Một máy** → **EBS**. Nó là ổ đĩa gắn vào một máy ảo, giống ổ SSD trong laptop. Dùng cho ổ hệ điều hành, file dữ liệu của database. `gp3` là mặc định hợp lý; `io1/io2` khi cần cam kết số IOPS cho database nặng.
- **Nhiều máy Linux** → **EFS**. Đây là thư mục chia sẻ theo giao thức NFS. Bối cảnh kinh điển và cũng là bẫy hay gặp nhất trong đề: MuaNhanh chạy 10 server web, người dùng tải ảnh lên, ảnh nằm trên ổ EBS của đúng server đã nhận file đó. Lần sau khách vào server khác thì không thấy ảnh. Đây chính là vấn đề "mỗi lần refresh lại thấy một nửa số tài liệu" — và cách sửa là chuyển sang EFS (hoặc tốt hơn là S3).
- **Nhiều máy Windows, cần Active Directory** → **FSx for Windows File Server**. Bối cảnh: doanh nghiệp truyền thống, ngân hàng, bệnh viện, công ty kế toán — nơi có thư mục chung `\\fileserver\ketoan` mà nhân viên gán quyền theo nhóm trong Active Directory. Khi họ lên mây, cái thư mục đó thành FSx for Windows.
- **Tính toán hiệu năng cao** → **FSx for Lustre**. Bối cảnh rất cụ thể: hàng nghìn nhân CPU cùng đọc một khối dữ liệu hàng trăm terabyte với thông lượng hàng trăm GB/s. Ai cần? Công ty dầu khí xử lý dữ liệu địa chấn, hãng dược so trình tự gen, hãng xe mô phỏng khí động học, studio render phim, quỹ đầu tư chạy mô phỏng Monte Carlo. Thấy chữ "HPC", "Lustre", "high-performance computing" là nó.
- **Instance Store** là ổ SSD vật lý gắn trực tiếp trên máy, cực nhanh nhưng **mất sạch khi máy tắt**. Chỉ dùng làm bộ nhớ tạm, không bao giờ dùng cho dữ liệu cần giữ.

Về **S3 và các tầng lưu trữ**, hãy nghĩ theo *tần suất người ta còn cần tới file đó*:

| Tầng | Khi nào dùng | Ví dụ nghiệp vụ |
|---|---|---|
| Standard | Truy cập thường xuyên | Ảnh sản phẩm đang bán |
| Intelligent-Tiering | **Không đoán được** ai còn xem file nào | Kho 500 triệu ảnh, không biết sản phẩm nào sẽ hot |
| Standard-IA | Ít xem nhưng cần ngay khi cần | Hóa đơn điện tử của 6 tháng trước |
| One Zone-IA | Ít xem, và mất thì tạo lại được | Ảnh thumbnail đã resize, có thể render lại từ ảnh gốc |
| Glacier Instant Retrieval | Rất ít xem nhưng vẫn cần ngay | Ảnh y tế của bệnh nhân cũ, khi bác sĩ cần là cần ngay |
| Glacier Flexible Retrieval | Chờ vài phút đến vài giờ được | Bản ghi camera an ninh năm ngoái |
| Glacier Deep Archive | Gần như không bao giờ xem, nhưng luật buộc giữ | Chứng từ giao dịch ngân hàng phải giữ 10 năm |

**Ngoài AWS:** EBS ↔ ổ LUN trên SAN của NetApp/Dell EMC. EFS ↔ NFS server, NetApp filer, CephFS. FSx Windows ↔ Windows File Server + DFS. FSx Lustre ↔ Lustre/GPFS/BeeGFS tự dựng. Glacier Deep Archive ↔ thư viện băng từ LTO, hoặc gửi băng cho Iron Mountain giữ hộ.

---

## Tầng 9 — Mạng nền: VPC và đường về trung tâm dữ liệu

**Việc cần làm:** dựng một mạng riêng, quyết định cái gì được ra internet, cái gì được vào, và nối với trung tâm dữ liệu cũ.

**AWS:** VPC, subnet, Internet Gateway, NAT Gateway, VPC Endpoint, Security Group, NACL, Transit Gateway, Direct Connect, Site-to-Site VPN.

Mô hình chuẩn của gần như mọi hệ thống production, và MuaNhanh cũng vậy:

- **Public subnet** chứa những thứ cần cho người ngoài chạm vào: load balancer, NAT Gateway. Dấu hiệu của public subnet là có đường đi ra Internet Gateway.
- **Private subnet** chứa toàn bộ phần còn lại: server ứng dụng, database. Chúng cần ra internet để tải bản vá bảo mật, nhưng không ai từ internet vào được. Đường ra đó đi qua **NAT Gateway**.
- **VPC Endpoint** cho phép máy trong private subnet nói chuyện với S3 và DynamoDB mà không cần đi qua NAT Gateway. Đây không chỉ là chuyện bảo mật mà là **chuyện tiền**: NAT Gateway tính phí theo từng GB đi qua. Nếu MuaNhanh mỗi ngày đọc 20 TB ảnh từ S3 qua NAT Gateway thì hóa đơn rất đau. Gateway Endpoint cho S3 và DynamoDB thì **miễn phí**. Đề thi hỏi "cách tiết kiệm nhất để tránh phí truyền dữ liệu trong Region" — câu trả lời gần như luôn là Gateway Endpoint.
- **Security Group** và **NACL** là hai lớp kiểm soát khác nhau. Security Group gắn vào từng máy, chỉ có luật cho phép, và **có nhớ trạng thái** — cho phép đi ra thì gói tin trả về tự động được vào. NACL gắn vào cả subnet, có luật **từ chối**, và không nhớ trạng thái. Suy ra: cần chặn một địa chỉ IP cụ thể đang tấn công thì **buộc phải dùng NACL**, vì Security Group không có khái niệm "chặn".

Về nối với trung tâm dữ liệu cũ, chọn theo **thời gian và tiền**:

- Cần xong trong tuần này, chi phí thấp, chấp nhận đi qua internet → **Site-to-Site VPN**.
- Cần băng thông lớn và độ trễ ổn định để chạy ứng dụng thật (như đồng bộ database, hoặc nhân viên dùng ứng dụng nội bộ suốt ngày) → **Direct Connect**. Nhưng nó mất nhiều tuần đến vài tháng để nhà mạng kéo đường, và đắt. Nên mẫu thường thấy: dùng VPN trước cho kịp dự án, kéo Direct Connect song song, và giữ VPN làm đường dự phòng.
- Có 40 VPC và 3 trung tâm dữ liệu cần nối lẫn nhau → **Transit Gateway**, hoạt động như một bộ định tuyến trung tâm. Nếu không có nó, bạn phải tạo VPC Peering từng cặp, và peering **không đi xuyên qua được** — A nối B, B nối C, nhưng A không nói chuyện được với C.

**Ngoài AWS:** VPC ↔ VLAN và các vùng firewall trong trung tâm dữ liệu. NAT Gateway ↔ chức năng NAT trên firewall Palo Alto/Fortinet. Direct Connect ↔ đường truyền MPLS hoặc kênh thuê riêng. Transit Gateway ↔ bộ định tuyến trung tâm, Cisco DMVPN.

---

## Tầng 10 — Danh tính và bảo mật

**Việc cần làm:** ai được làm gì, và dữ liệu được mã hóa thế nào.

**AWS:** IAM, IAM Identity Center, Cognito, KMS, CloudHSM, Secrets Manager, Parameter Store, GuardDuty, Inspector, Macie, Security Hub, Organizations + SCP.

Điều quan trọng nhất — và cũng là quy tắc giúp bạn loại đáp án nhanh nhất trong cả kỳ thi:

> **Không bao giờ đặt access key vào trong máy chủ, trong code, hay trong file cấu hình.** Máy chủ và hàm được cấp quyền bằng **IAM Role**.

Lý do nghiệp vụ: access key là chuỗi ký tự tồn tại vĩnh viễn. Nó bị lộ qua Git, qua log, qua ảnh chụp màn hình, qua nhân viên nghỉ việc. Hầu hết các vụ rò rỉ dữ liệu trên mây được công bố đều bắt đầu từ một cặp key bị lộ. IAM Role thì cấp thông tin xác thực tạm thời, tự hết hạn, tự luân phiên. Trong đề thi, **bất kỳ đáp án nào nhắc đến việc lưu access key ở đâu đó đều sai** — kể cả khi nó nói "lưu trong file được mã hóa".

Ba nhóm danh tính, đừng nhầm lẫn:

- **Nhân viên công ty** đăng nhập vào AWS để làm việc → **IAM Identity Center** liên kết với Active Directory hoặc Okta của công ty. Điểm kinh doanh: nhân viên nghỉ việc thì phòng nhân sự vô hiệu hóa tài khoản AD, và người đó mất quyền vào AWS ngay. Nếu mỗi người một tài khoản IAM riêng, sẽ có ngày bạn phát hiện tài khoản của người đã nghỉ 8 tháng vẫn sống.
- **Khách hàng dùng app** — hàng triệu người, đăng ký bằng email hoặc Facebook/Google → **Cognito**. Khách hàng của MuaNhanh không phải là user IAM.
- **Máy và ứng dụng** → **IAM Role**.

Về mã hóa, phân biệt bằng **ai giữ chìa khóa và ai cần chứng minh điều đó với ai**:

- **SSE-S3**: AWS lo hết, bạn không thấy chìa khóa. Đủ cho phần lớn trường hợp.
- **SSE-KMS với customer managed key**: bạn tạo chìa khóa, bạn quyết định ai dùng được, và **mọi lần dùng chìa khóa đều được ghi vào CloudTrail**. Đây là điều mà kiểm toán viên và cơ quan quản lý yêu cầu. Đề nói "phải kiểm soát việc tạo, luân phiên, vô hiệu hóa khóa" → customer managed KMS key.
- **CloudHSM**: thiết bị phần cứng dành riêng cho bạn, đạt chuẩn FIPS cấp cao, AWS không hề chạm được vào khóa. Ai cần? Tổ chức phát hành thẻ, ngân hàng ký giao dịch, đơn vị cấp chứng thư số — nơi luật hoặc chuẩn ngành (PCI DSS) buộc khóa phải nằm trong HSM riêng.

Về mật khẩu và bí mật: **Secrets Manager** tự động đổi mật khẩu database theo lịch (có phí), **Parameter Store** chỉ lưu cấu hình và bí mật đơn giản (miễn phí, không tự đổi mật khẩu). Đề nói "automatic rotation" → Secrets Manager.

Bốn dịch vụ phát hiện, cực hay bị hoán đổi trong đáp án nhiễu:

| Service | Nó soi cái gì | Câu hỏi nghiệp vụ nó trả lời |
|---|---|---|
| GuardDuty | Log mạng, log DNS, log API | "Có máy nào của tôi đang bị chiếm và nói chuyện với server điều khiển botnet không?" |
| Inspector | Phần mềm trên EC2, ảnh container, Lambda | "Máy của tôi có đang chạy phiên bản OpenSSL có lỗ hổng không?" |
| Macie | Nội dung file trong S3 | "Trong hồ dữ liệu có ai vô tình đổ vào số CMND, số thẻ ngân hàng không?" |
| Security Hub | Tổng hợp phát hiện của tất cả cái trên | "Cho tôi một trang duy nhất xem toàn bộ tình hình bảo mật" |

Và ba dịch vụ ghi nhận, cũng hay bị hoán đổi:

| Service | Ghi lại gì | Ví dụ |
|---|---|---|
| CloudTrail | **Ai gọi API gì, lúc nào** | "Ai đã xóa cái database production lúc 2h sáng?" |
| AWS Config | **Cấu hình tài nguyên thay đổi thế nào, có lệch chuẩn không** | "Có S3 bucket nào đang để công khai không? Có ổ đĩa nào chưa mã hóa không?" |
| CloudWatch | **Số đo và log ứng dụng** | "CPU đang bao nhiêu phần trăm, có bao nhiêu lỗi 500?" |

Câu hỏi kinh điển ghép hai cái đầu: "cần theo dõi thay đổi cấu hình **và** lưu lịch sử lời gọi API" → Config cho cấu hình, CloudTrail cho API. Đề sẽ cho một đáp án đảo ngược hai vai này.

**Ngoài AWS:** IAM ↔ Active Directory, LDAP, Kerberos. Identity Center ↔ Okta, Entra ID, Keycloak, ADFS. Cognito ↔ Auth0, Firebase Auth, Keycloak. KMS/Secrets Manager ↔ HashiCorp Vault, CyberArk, thiết bị HSM của Thales. GuardDuty/Security Hub ↔ SIEM như Splunk, QRadar. Config ↔ Chef InSpec, các công cụ CMDB.

---

## Tầng 11 — Nhiều tài khoản: quản trị tập đoàn

Khi công ty lớn lên, một tài khoản AWS không đủ. MuaNhanh sẽ có tài khoản riêng cho production, staging, dữ liệu, bảo mật, và mỗi phòng ban một tài khoản sandbox. Lý do: **giới hạn thiệt hại**. Một lập trình viên xóa nhầm thứ gì đó trong tài khoản sandbox thì production không hề bị ảnh hưởng. Và hóa đơn tự tách theo phòng ban.

**AWS Organizations** gom các tài khoản lại và cho hóa đơn chung. **SCP (Service Control Policy)** là hàng rào cứng: "không tài khoản nào trong tập đoàn được tạo tài nguyên ngoài Region Singapore và Tokyo", "không ai được tắt CloudTrail" — kể cả người có quyền admin trong tài khoản đó cũng không phá được. **Control Tower** dựng sẵn toàn bộ cấu trúc này theo thực hành tốt nhất cho ai bắt đầu từ đầu.

Trong đề, "cần giới hạn quyền trên toàn bộ tổ chức" → SCP, không phải IAM policy. IAM policy cấp quyền cho một người trong một tài khoản; SCP đặt trần cho cả tài khoản.

---

## Tầng 12 — Chi phí: tầng mà giám đốc tài chính quan tâm

Ba câu hỏi mà một solutions architect thật sự phải trả lời hàng tháng, và đề thi hỏi lại đúng ba câu này:

1. **Tháng này tiêu vào đâu?** → Cost Explorer để bóc tách và vẽ biểu đồ. Cost and Usage Report nếu cần dữ liệu thô để tự phân tích sâu.
2. **Làm sao đừng vượt ngân sách?** → AWS Budgets để đặt ngưỡng và cảnh báo.
3. **Đang lãng phí ở đâu?** → Compute Optimizer (máy quá to so với nhu cầu), Trusted Advisor (tài nguyên bỏ không, ổ đĩa không gắn vào đâu, IP tĩnh không dùng).

Bốn nguồn tốn tiền âm thầm mà đề rất thích hỏi:

- **Truyền dữ liệu ra internet** đắt nhất. Giảm bằng CloudFront.
- **Truyền dữ liệu qua NAT Gateway** — giảm bằng VPC Endpoint.
- **Truyền dữ liệu giữa các AZ** có phí, nên hệ thống nói chuyện nhiều nội bộ thì cân nhắc giữ trong cùng AZ (nhưng đổi lại giảm khả năng chịu lỗi — đây là một đánh đổi thật, không có đáp án tuyệt đối).
- **Tài nguyên chạy không tải:** môi trường dev bật 24/7 dù chỉ dùng giờ hành chính. Tắt vào buổi tối và cuối tuần là giảm được khoảng 70% cho môi trường đó.

---

## Ba câu hỏi thay thế cho việc nhớ 300 keyword

Khi vào phòng thi và gặp một câu lạ, đi qua ba câu hỏi này theo thứ tự:

**Câu 1: Đây là loại dữ liệu hay loại công việc gì?**
File và blob → S3, EFS, FSx. Bản ghi có quan hệ → RDS/Aurora. Khóa–giá trị lượng cực lớn → DynamoDB. Dòng sự kiện liên tục → Kinesis. Công việc cần xếp hàng chờ xử lý → SQS. Truy vấn phân tích → Athena/Redshift. Xác định đúng loại là đã loại được nửa số đáp án.

**Câu 2: Đề đang ưu tiên điều gì? Đọc cụm chữ in hoa ở câu cuối.**
Đây là bước quyết định, vì thường có hai đáp án đều *chạy được*, chỉ khác nhau ở tiêu chí:

- `LEAST OPERATIONAL OVERHEAD` / `MOST OPERATIONALLY EFFICIENT` → chọn dịch vụ có người quản, không phải viết code. Mọi đáp án có cron job, script tự viết, EC2 tự vận hành đều bị loại.
- `MOST COST-EFFECTIVE` → chọn cái rẻ, chấp nhận vận hành mệt hơn.
- `MOST RESILIENT` / `HIGHEST AVAILABILITY` → chọn nhiều AZ, nhiều Region, kể cả đắt hơn.
- `MINIMAL CHANGES TO THE APPLICATION` → loại các đáp án đòi viết lại code hay đổi database.
- `AS QUICKLY AS POSSIBLE` → cẩn thận, nó có thể loại bỏ đúng cái phương án rẻ nhất.

**Câu 3: Đáp án này có ai đó phải trực đêm không?**
Nếu một đáp án ngụ ý có người phải theo dõi, chạy script tay, hoặc dựng máy chủ chỉ để làm một việc mà AWS đã có dịch vụ sẵn — thì trong đề SAA-C03 nó gần như luôn sai. Đề thi này được viết theo triết lý AWS Well-Architected, mà triết lý đó nói: giảm việc vận hành thủ công là một mục tiêu kiến trúc, không phải chuyện phụ.

---

## Cách đọc các phần sau

Từ phần 1 trở đi, mỗi câu hỏi được trình bày theo cùng một bố cục:

- **Tình huống** — dịch sang tiếng Việt theo văn phong nghiệp vụ, giữ nguyên các chi tiết quyết định đáp án.
- **Đáp án** và lý do chọn.
- **Ngoài đời chuyện này xảy ra ở đâu** — ngành nào, công ty kiểu nào, hệ thống nào.
- **Vị trí trong hệ thống lớn** — nó thuộc tầng nào trong 12 tầng ở trên.
- **Nếu không dùng AWS** — công cụ tương đương.
- **Vì sao các đáp án khác sai** — giải thích theo hậu quả nghiệp vụ, không phải theo lý thuyết.

Bạn không cần đọc theo thứ tự. Nhưng nếu quên mất một service ngồi ở đâu, quay lại chương này.
