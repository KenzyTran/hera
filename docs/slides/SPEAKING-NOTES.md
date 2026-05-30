# Hera Sharing Session — Speaking Notes

Tài liệu chuẩn bị lý thuyết và giáo án cho buổi sharing 25 phút.
Tất cả nguồn từ AWS docs, AWS blogs, aws-samples GitHub.

---

## Giáo án tổng thể (25 phút · 20 slides)

| Chặng | Slides | Thời lượng | Mục tiêu |
|---|---|---|---|
| **A. Tổng quan** | 1-6 | ~5 phút | Hera là gì, use case, kiến trúc, voice turn flow |
| **B. Lý thuyết** | 7-14 | ~8 phút | Cascade vs S2S, 9 AWS service và vì sao chọn |
| **C. Demo + số liệu** | 15-17 | ~5 phút | Live demo + số liệu thực tế |
| **D. Hướng mở rộng + Recap** | 18-20 | ~7 phút | v2 story, surprises + pitfalls, Q&A |

**Pre-session checklist — 3 cửa sổ mở sẵn**:
1. **Browser**: tab 1 = demo URL public; tab 2 = `docs/architecture-aws.drawio` (hoặc `static/images/architecture-aws.png` nếu projector không mở được drawio).
2. **Terminal**: ở `c:/Users/trant/projects/hera`, sẵn 1 tab chạy `bin/verify-kb.sh` để demo KB query live nếu còn thời gian.
3. **IDE** (tùy chọn): nếu Q&A có hỏi sâu về code, mở Phụ lục C để biết đường tới file:line.

**Quy tắc thời gian**: nếu vượt phút thứ 18 mà chưa tới demo → cắt phần Recap còn 2 phút, tập trung vào v2 story và để dành thời gian Q&A.

---

# PHẦN A — TỔNG QUAN (~5 phút)

---

## Slide 1: Cover

> Xin chào mọi người, chào mừng đến với buổi sharing hôm nay.

> Hôm nay mình sẽ chia sẻ về Hera — một dự án voice agent chạy trên AWS. Nói nôm na, đây là một trợ lý ảo mà bạn có thể nói chuyện bằng giọng nói thật, qua trình duyệt, và nó sẽ trả lời bạn bằng giọng nói tự nhiên luôn — không cần cài đặt gì, không cần app, chỉ cần microphone.

> Dự án này được xây dựng hoàn toàn trên hạ tầng AWS, sử dụng Amazon Bedrock Nova 2 Sonic — một speech-to-speech model rất mới — kết hợp với AgentCore Runtime để deploy.

> Mình sẽ đi từ tổng quan để mọi người nắm bức tranh lớn trước, rồi vào lý thuyết từng service AWS, sau đó là demo live, và cuối cùng là những bài học rút ra.

---

## Slide 2: Agenda

> Chúng ta sẽ đi qua 4 chặng chính trong khoảng 25 phút.

> Đầu tiên là tổng quan — Hera là gì, use case, kiến trúc tổng thể, và một voice turn đi qua những đâu. Sau đó là lý thuyết — cascade vs speech-to-speech, và từng AWS service mình dùng. Tiếp theo là demo live cộng số liệu thực tế. Và cuối cùng là câu chuyện v2 và recap những surprise đáng nhớ nhất.

> Mình cố gắng giữ cho mọi thứ thực tế nhất có thể — toàn bộ số liệu đều từ hệ thống đang chạy thật, không phải lý thuyết.

---

## Slide 3: Hera là gì?

> Vậy Hera là gì? Rất đơn giản: bạn mở trình duyệt, bấm nút record, rồi nói "Do you have MacBook Pro?" — và agent sẽ trả lời bạn bằng giọng nói tự nhiên, có thông tin sản phẩm thật từ knowledge base.

> Đây là demo một Apple Store assistant. Mình chọn use case này vì nó đủ đơn giản để mọi người hiểu, nhưng đủ phức tạp để thể hiện được sức mạnh của kiến trúc.

> Phía sau hậu trường, khi bạn hỏi về sản phẩm, model Nova 2 Sonic tự quyết định gọi một tool tên `lookup_product`. Tool này query vào Bedrock Knowledge Base, tìm trong S3 Vectors, trả về top-3 kết quả liên quan nhất. Rồi Sonic tổng hợp thông tin đó và phát audio trả lời cho bạn.

> Tất cả diễn ra trong dưới 3 giây — từ lúc bạn nói xong đến lúc nghe được câu trả lời. Hệ thống đang chạy thật, public 24/7, idle gần $0.

---

## Slide 4: Use case — Apple Store assistant

> Mình cho mọi người xem qua một đoạn hội thoại mẫu thực tế.

> User hỏi: "Do you have MacBook Pro M4 in stock?" — Agent trả lời: "Yes, we have the 14-inch M4 Pro in Silver and Space Black. The 14-inch starts at $1,999."

> User hỏi tiếp: "What about iPhone 13 Pro Max?" — Agent trả lời: "iPhone 13 Pro Max is currently out of stock. Would you like me to suggest an alternative?"

> Những câu trả lời này không phải hardcoded. Agent thực sự query vào Knowledge Base, lấy dữ liệu từ catalog markdown mà mình viết sẵn. Catalog có 3 SKU — Apple Watch, iPhone, MacBook — đủ để chứng minh concept hoạt động.

> Chút nữa ở phần lý thuyết, mình sẽ nói kỹ hơn về RAG layer này.

---

## Slide 5: Kiến trúc tổng thể

**Live diagram**: trong khi nói slide này, **chuyển sang tab drawio** (`docs/architecture-aws.drawio`) hoặc PNG render (`static/images/architecture-aws.png`). Chỉ tay theo từng vùng khi nói "Edge Layer" → "Compute + AI layer".

> Đây là architecture diagram của Hera. Mình chia thành 2 layer chính.

> Bên trái là Edge Layer — đây là phần mà browser user tương tác trực tiếp. CloudFront phân phối widget HTML/JS, S3 host static files, Lambda Function URL làm nhiệm vụ presigner — tạo URL WebSocket có chữ ký SigV4 để browser kết nối vào AgentCore.

> Bên phải là Compute + AI Layer. AgentCore Runtime chạy container Pipecat của mình. Pipecat kết nối vào Nova 2 Sonic qua bidirectional stream. Khi cần lookup sản phẩm, nó gọi Bedrock KB, KB query S3 Vectors, trả chunks về cho Sonic để compose câu trả lời.

> Bên ngoài kiến trúc, mình có vẽ thêm Phone (PSTN) → Twilio để minh họa hướng v2 — nếu muốn agent nhận cuộc gọi điện thoại thật, đường đi sẽ là Twilio → AgentCore. Hiện tại v1 chỉ chạy web channel.

> Một điểm đáng chú ý: toàn bộ hệ thống KHÔNG có ECS, KHÔNG có EC2, KHÔNG có VPC tự quản. Mọi thứ đều managed.

### Nguồn

- [Deploy voice agents with Pipecat and AgentCore Runtime (AWS ML Blog)](https://aws.amazon.com/blogs/machine-learning/deploy-voice-agents-with-pipecat-and-amazon-bedrock-agentcore-runtime-part-1/)
- [aws-samples/sample-nova-sonic-websocket-agentcore](https://github.com/aws-samples/sample-nova-sonic-websocket-agentcore)

---

## Slide 6: Một voice turn đi qua những đâu?

> Mình muốn giải thích rõ hơn: khi bạn nói một câu, chuyện gì xảy ra phía sau?

> **Bước 1**: Browser gọi Lambda presigner, nhận được một URL WebSocket đã ký SigV4, có hiệu lực 5 phút. Lý do cần bước này là vì browser không thể tự ký SigV4 cho WebSocket upgrade — đây là một giới hạn kỹ thuật của browser, không phải lỗi thiết kế.

> **Bước 2**: Browser dùng URL đó mở WebSocket trực tiếp tới AgentCore. Không cần SDK, không cần Cognito, chỉ vanilla JavaScript.

> **Bước 3**: Pipecat container trong AgentCore nhận audio PCM 16kHz mono Int16 từ browser qua WebSocket.

> **Bước 4**: Nova 2 Sonic nhận audio, transcribe nội bộ, quyết định gọi tool `lookup_product`. Bedrock KB nhận query, embed bằng Titan v2, tìm trong S3 Vectors, trả top-3 chunks.

> **Bước 5**: Sonic tổng hợp thông tin từ KB và phát audio response 24kHz về browser, browser phát ra loa qua audio worklet.

> Toàn bộ quá trình này dưới 3 giây p95. Và khi không có ai dùng? Chi phí bằng 0 — AgentCore managed microVM tự wake và sleep theo session.

---

# PHẦN B — LÝ THUYẾT (~8 phút)

---

## Slide 7: Lý thuyết (divider)

> Bây giờ mình đi vào phần lý thuyết — tại sao chọn từng service.

> Phần này có 7 slide: bắt đầu với bối cảnh ngành — cascade vs speech-to-speech, rồi overview 9 service mình dùng, sau đó deep-dive 5 nhóm service quan trọng nhất.

---

## Slide 8: Bài toán — Cascade vs Speech-to-Speech

> Nếu bạn muốn build một voice AI chatbot cách đây 1-2 năm, cách làm phổ biến nhất là ghép 3 service lại với nhau: một cái chuyển giọng nói thành text (STT), một cái xử lý text đó bằng LLM, rồi một cái chuyển text trả lời thành giọng nói (TTS). Người ta gọi đây là kiến trúc cascade — nối tiếp nhau như thác nước.

> Vấn đề là gì? Mỗi bước cộng thêm latency. STT mất 100-500ms, LLM mất 350ms đến hơn 1 giây, TTS thêm 75-200ms nữa. Tổng cộng bạn phải chờ 4-6 giây cho một turn. Cảm giác nói chuyện rất gượng gạo, không tự nhiên.

> Và còn một vấn đề nữa ít ai để ý: khi bạn chuyển giọng nói thành text, bạn mất hết ngữ điệu, cảm xúc, nhịp điệu. Model không biết bạn đang vui hay buồn, đang hỏi nghiêm túc hay đùa. Tất cả thông tin đó bị "xóa sạch" ở bước STT.

> Cách làm mới — speech-to-speech — thay đổi hoàn toàn. Chỉ có 1 foundation model xử lý tất cả: nghe giọng nói đầu vào, suy luận, rồi phát giọng nói đầu ra trực tiếp. Không qua text trung gian. Model giữ nguyên ngữ điệu, hỗ trợ barge-in — tức là bạn có thể ngắt lời nó giữa chừng, y hệt nói chuyện với người thật.

> Amazon Nova 2 Sonic chính là model speech-to-speech của AWS trên Bedrock. Và đó là thứ mình dùng trong Hera.

### Nguồn

- [Introducing Amazon Nova Sonic (AWS Blog, Apr 2025)](https://aws.amazon.com/blogs/aws/introducing-amazon-nova-sonic-human-like-voice-conversations-for-generative-ai-applications/)
- [Introducing Amazon Nova 2 Sonic (AWS Blog, Dec 2025)](https://aws.amazon.com/blogs/aws/introducing-amazon-nova-2-sonic-next-generation-speech-to-speech-model-for-conversational-ai/)
- [Amazon Nova Speech](https://aws.amazon.com/ai/generative-ai/nova/speech)

---

## Slide 9: AWS services dùng trong v1

> Hera dùng 9 AWS services.

> Bedrock cho model Nova 2 Sonic. Bedrock KB cho RAG. AgentCore Runtime cho compute. S3 vừa host widget vừa lưu KB source. CloudFront làm CDN. Lambda làm presigner. ECR lưu container image. IAM quản lý permission. CloudWatch cho observability.

> Điểm đặc biệt: KHÔNG có ECS, KHÔNG có EC2, KHÔNG có EKS, KHÔNG có VPC tự quản. Hoàn toàn serverless/managed.

---

## Slide 10: Amazon Bedrock + Nova 2 Sonic

> Đây là trái tim của hệ thống. Nova 2 Sonic là speech-to-speech model của AWS, chạy trên Bedrock.

> Tính chất quan trọng nhất: bidirectional WebSocket stream. Audio chạy 2 chiều cùng lúc — giống như cuộc gọi điện thoại thật, không phải request-response. Đây là thứ cho phép barge-in tự nhiên.

> Tính năng mình thích nhất là built-in tool calling. Sonic tự quyết định khi nào cần gọi tool — mình không phải viết logic routing nào cả. Mình chỉ đăng ký tool `lookup_product` với schema JSON, còn lại Sonic tự xử lý. Phiên bản Nova 2 Sonic còn hỗ trợ async tool calling — model tiếp tục nói trong lúc tool chạy nền.

> Một giới hạn quan trọng cần biết: 8-min stream cap. Mỗi WebSocket connection tối đa 8 phút. Mình xử lý bằng cách rotate connection ở phút thứ 6, truyền chat history sang connection mới. Người dùng không biết stream bị rotate.

> Về giá: khoảng $0.017/phút hội thoại. Đây là một con số rất cạnh tranh trong nhóm speech-to-speech foundation model.

### Nguồn

- [Introducing Amazon Nova 2 Sonic (AWS Blog)](https://aws.amazon.com/blogs/aws/introducing-amazon-nova-2-sonic-next-generation-speech-to-speech-model-for-conversational-ai/)
- [Nova 2 Sonic Model Card (Bedrock Docs)](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-amazon-nova-2-sonic.html)
- [Using Bidirectional Streaming API (Nova Docs)](https://docs.aws.amazon.com/nova/latest/userguide/speech-bidirection.html)
- [Amazon Nova Pricing](https://aws.amazon.com/nova/pricing/)
- [Nova Sonic Technical Report (Amazon Science)](https://www.amazon.science/publications/amazon-nova-sonic-technical-report-and-model-card)

---

## Slide 11: Bedrock Knowledge Base + S3 Vectors

> Tiếp theo là RAG layer — phần giúp agent có "trí nhớ" về sản phẩm.

> Bedrock Knowledge Base là dịch vụ managed của AWS làm toàn bộ RAG workflow. Mình chỉ cần đặt file markdown vào S3, tạo KB, rồi chạy ingestion job. KB tự động parse, chunk, embed bằng Titan v2, rồi lưu vectors vào S3 Vectors.

> S3 Vectors là thứ rất mới — GA tháng 12/2025. Đây là cloud object storage đầu tiên có native vector support. Nôm na là bạn có thể lưu và query vectors trực tiếp trong S3, không cần provision bất kỳ compute nào.

> So với OpenSearch Serverless, S3 Vectors khác về mô hình tính phí — pay per use, không có OCU floor — và tích hợp native với Bedrock KB qua một field `storage_configuration` đơn giản. Hợp với workload có pattern truy cập spiky hoặc read-light, dữ liệu scale dần theo thời gian.

> OpenSearch Serverless thì phù hợp khi cần QPS cao, complex filter, hoặc latency dưới 100ms ổn định — đó là trade-off thật, không phải vấn đề đắt-rẻ tuyệt đối.

> Về Titan Text Embeddings V2: 1024 dimensions, cosine similarity, hỗ trợ hơn 100 ngôn ngữ.

> Khi user hỏi về sản phẩm, flow diễn ra như sau: Nova Sonic emit tool call `lookup_product` → Pipecat function handler gọi Retrieve API → KB embed query bằng Titan v2 → ANN search trong S3 Vectors → trả top-3 chunks → chunks được trả về cho Sonic → Sonic compose audio response.

### Nguồn

- [Amazon S3 Vectors](https://aws.amazon.com/s3/features/vectors/)
- [S3 Vectors GA blog](https://aws.amazon.com/blogs/aws/amazon-s3-vectors-now-generally-available-with-increased-scale-and-performance/)
- [Using S3 Vectors with Bedrock KB (docs)](https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-vectors-bedrock-kb.html)
- [Building cost-effective RAG with S3 Vectors (AWS ML Blog)](https://aws.amazon.com/blogs/machine-learning/building-cost-effective-rag-applications-with-amazon-bedrock-knowledge-bases-and-amazon-s3-vectors/)
- [Amazon Bedrock Knowledge Bases](https://aws.amazon.com/bedrock/knowledge-bases/)
- [Titan Text Embeddings V2 (docs)](https://docs.aws.amazon.com/bedrock/latest/userguide/titan-embedding-models.html)

---

## Slide 12: Amazon Bedrock AgentCore Runtime

> Đây là service mà mình thấy ít người biết nhưng rất mạnh cho voice agent workload.

> AgentCore Runtime là managed serverless hosting cho AI agents. Mỗi user session chạy trong một microVM riêng biệt — CPU, memory, filesystem hoàn toàn cách ly giữa các session. Và điểm quan trọng nhất: scale-to-zero thật sự — không có session thì không có compute, không mất tiền.

> Mình deploy bằng cách package Pipecat agent code vào Docker container ARM64, push lên ECR, rồi tạo AgentCore Runtime. Service tự wake microVM khi có request đến.

> So với ECS Fargate: AgentCore là first-party agent runtime, scale-to-zero thật sự, managed networking (không VPC, không NLB, không NAT). Fargate phù hợp khi workload always-on, hoặc khi cần fine-tune VPC/NLB/security group.

> Session tối đa 8 giờ — so với Lambda max 15 phút. Cho voice call dài, đây là khác biệt quan trọng.

> AgentCore hiện có ở 9 regions, bao gồm `ap-northeast-1` Tokyo — đúng region mà Hera dùng cho production.

### Nguồn

- [Amazon Bedrock AgentCore](https://aws.amazon.com/bedrock/agentcore/)
- [AgentCore Pricing](https://aws.amazon.com/bedrock/agentcore/pricing/)
- [How AgentCore Runtime works (docs)](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-how-it-works.html)
- [HTTP protocol contract (docs)](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-http-protocol-contract.html)
- [Introducing AgentCore (launch blog)](https://aws.amazon.com/blogs/aws/introducing-amazon-bedrock-agentcore-securely-deploy-and-operate-ai-agents-at-any-scale/)

---

## Slide 13: Edge + auth bridge

> Layer edge gồm 3 service đơn giản nhưng có một thiết kế đáng nói.

> CloudFront phân phối widget HTML/JS qua HTTPS. S3 host static files với Origin Access Control — chỉ CloudFront truy cập được, không ai gọi thẳng S3 URL.

> Phần đáng nói nhất là Lambda presigner. Vấn đề là: AgentCore yêu cầu IAM SigV4 authentication cho mọi kết nối. Nhưng browser KHÔNG THỂ tự ký SigV4 cho WebSocket upgrade request. Đây là giới hạn kỹ thuật — SigV4 signing cần AWS credentials, mà bạn không thể đặt credentials trong browser code (ai cũng nhìn thấy).

> Giải pháp: Lambda Function URL hoạt động như một presigner. Khi user click record, browser gọi Lambda → Lambda dùng IAM role của nó để ký một presigned WebSocket URL → URL này có hiệu lực 5 phút → browser dùng URL đó kết nối thẳng vào AgentCore. Sau đó audio chạy trực tiếp browser ↔ AgentCore, Lambda không còn trong đường đi nữa.

> IAM least-privilege chặt: Lambda chỉ được `InvokeAgentRuntime` trên đúng một ARN, không có wildcard nào.

### Nguồn

- [AWS Lambda Function URLs (docs)](https://docs.aws.amazon.com/lambda/latest/dg/lambda-urls.html)
- [Amazon CloudFront](https://aws.amazon.com/cloudfront/)

---

## Slide 14: Observability, security, container supply

> Ba service hỗ trợ nhưng không kém quan trọng.

> **CloudWatch**: mình có 1 dashboard `hera-prod` với 5 panel, 2 operational alarm — error rate vượt 5% trong 5 phút và latency p95 vượt 5 giây trong 5 phút. Và 1 billing alarm ở `us-east-1` đặt ngưỡng $5/ngày.

> Tại sao billing alarm phải ở us-east-1? Vì AWS chỉ emit metric `AWS/Billing` ở region us-east-1, bất kể resource của bạn chạy ở region nào. Đây là một "gotcha" mà nhiều người không biết cho đến khi alarm không bao giờ trigger.

> **IAM**: least-privilege nghiêm ngặt — ZERO `Resource: *` wildcard. Mỗi service có role riêng. Confused-deputy mitigation bằng condition keys (`aws:SourceAccount` + ARN scope).

> **ECR**: repository `hera-agent` dùng IMMUTABLE tags — push tag nào rồi thì không ghi đè được. Scan-on-push enabled. Image build multi-arch (ARM64 cho AgentCore Graviton, AMD64 cho dev local).

### Nguồn

- [CloudWatch Billing Alarms (docs)](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/monitor_estimated_charges_with_cloudwatch.html)
- [Amazon ECR](https://aws.amazon.com/ecr/)
- [AWS IAM](https://aws.amazon.com/iam/)

---

# PHẦN C — DEMO + SỐ LIỆU (~5 phút)

---

## Slide 15: Demo + Bài học (divider)

> Bây giờ đến phần thú vị nhất — demo live và số liệu thực.

---

## Slide 16: Live demo

> Đây là URL public — ai cũng có thể mở ngay bây giờ trên điện thoại hoặc laptop.

> Mình sẽ hỏi vài câu: "Do you have MacBook Pro?", "What about iPhone 13 stock?", "Tell me about Apple Watch."

> Các bạn chú ý: latency từ lúc mình nói xong đến lúc agent bắt đầu trả lời. Target là dưới 3 giây.

> Lưu ý: concurrency cap = 2, nghĩa là chỉ 2 người dùng cùng lúc. Nếu busy thì sẽ phải chờ vài giây.

---

## Slide 17: Số liệu thực tế

> Một vài số liệu thực tế từ hệ thống đang chạy.

> **Chi phí burst test dưới $1/giờ** — bao gồm voice, KB query, dashboard. **Idle qua đêm gần $0** — AgentCore scale-to-zero thật sự.

> **KB top score 0.86** — khi mình query "iPhone 13 Pro Max stock", kết quả trả về với confidence score 0.86, rất tốt cho semantic search.

> **Latency p95 dưới 3 giây** — từ lúc user nói xong đến lúc nghe được audio response đầu tiên.

> **Pricing Nova 2 Sonic ~$0.017/phút** — một con số rất cạnh tranh cho speech-to-speech foundation model.

---

# PHẦN D — HƯỚNG MỞ RỘNG + RECAP (~7 phút)

---

## Slide 18: Hướng mở rộng (v2 + sau)

> Mình muốn chia sẻ câu chuyện v2 — vì nó khá thú vị.

> Ban đầu mình định thêm Twilio voice channel — cho phép gọi điện thoại vào agent. Mình viết xong bridge code, test offline pass, nhưng khi deploy lên App Runner thì phát hiện App Runner edge từ chối inbound WebSocket upgrade. Bridge code đúng, nhưng compute target defective. Bài học: hãy test trên production-like environment sớm nhất có thể.

> Sau đó mình pivot sang Amazon Connect — dùng Lex V2 + Lambda + Polly Neural thay Twilio. Deploy xong, gọi thử, mới nhận ra: kiến trúc Connect + Lex là IVR-style cũ. Mỗi turn có gap 3-5 giây — so với Sonic dưới 2 giây. Trải nghiệm rất khác biệt.

> Cuối cùng mình quyết định: giữ nguyên v1 Nova Sonic web widget. Đây là technology mới nhất — 1 foundation model speech-to-speech, không phải pipeline ghép nhiều component. Và đó là đúng hướng đi của ngành.

> Trên architecture diagram, mình vẫn vẽ Twilio bên ngoài như một entry channel tương lai — nếu sau này có nhu cầu phone, đường đi sẽ là Twilio → AgentCore (không qua Lambda presigner, vì Twilio tự ký được SigV4 server-side).

> Hướng tiếp theo nếu tiếp tục: multi-language support (Nova 2 Sonic đã hỗ trợ 7 ngôn ngữ), multi-agent routing, persistent conversation bằng DynamoDB, và có thể một chapter so sánh AgentCore vs ECS Fargate deployment.

### Nguồn

- [Amazon Connect at re:Invent 2025 (AWS Blog)](https://aws.amazon.com/blogs/contact-center/amazon-connect-at-reinvent-2025-creating-the-future-of-customer-experience-with-ai/)
- [Top Announcements re:Invent 2025 (AWS Blog)](https://aws.amazon.com/blogs/aws/top-announcements-of-aws-reinvent-2025/)

---

## Slide 19: Recap — xây một voice agent gồm gì?

> Tóm lại buổi hôm nay — nếu bạn về và muốn tự xây một voice agent, đây là 5 điều cốt lõi.

> **1. Speech-to-speech là bước nhảy.** Thay vì ghép STT → LLM → TTS (cascade — 4-6 giây mỗi turn, mất hết ngữ điệu), Hera dùng MỘT model — Nova 2 Sonic — xử lý trọn vẹn audio-vào đến audio-ra. Kết quả: dưới 3 giây mỗi turn, giữ nguyên cảm xúc giọng nói, ngắt lời tự nhiên (barge-in). Đây là thứ thay đổi trải nghiệm nhiều nhất.

> **2. Tool calling + RAG biến model nói chuyện thành agent hữu ích.** Sonic tự quyết định khi nào gọi `lookup_product` — mình không viết một dòng routing nào. Tool query Bedrock KB → S3 Vectors → trả chunks → Sonic compose câu trả lời có dữ liệu thật. Một model biết nói, cộng tool + RAG, thành một agent biết việc.

> **3. Pipecat lo phần khó.** Quản lý audio frame, barge-in detection, rotate stream khi chạm 8 phút — Pipecat xử lý sẵn. Mình chỉ ghép pipeline và đăng ký tool. Nhờ vậy đi từ ý tưởng đến chạy thật trong 1 ngày, không phải 2-3 tuần.

> **4. Hạ tầng hoàn toàn managed / serverless.** AgentCore Runtime (microVM, scale-to-zero, $0 khi idle), Bedrock KB, S3 Vectors, Lambda presigner, CloudFront. KHÔNG ECS, KHÔNG EC2, KHÔNG VPC tự quản. Idle gần $0, một buổi demo dưới $1.

> **5. Quan sát được từ ngày đầu.** CloudWatch dashboard + alarm cho metric; Langfuse cho waterfall trace từng cuộc hội thoại (session → tool call → KB Retrieve). Build agent mà không trace được là build trong bóng tối.

> Tóm một câu: **voice agent hôm nay = 1 speech-to-speech model + tool calling + RAG, đặt trên hạ tầng managed, có observability.** Phần còn lại là chi tiết kỹ thuật.

> (Trên đường đi mình có gặp vài "gotcha" đáng nhớ — browser không ký được SigV4, 8-min stream cap, billing alarm phải ở us-east-1 — mình để chi tiết ở Phụ lục E cho ai muốn đào sâu, để slide này tập trung vào bức tranh lớn.)

### Nguồn

- [Deploy voice agents with Pipecat + AgentCore (AWS ML Blog)](https://aws.amazon.com/blogs/machine-learning/deploy-voice-agents-with-pipecat-and-amazon-bedrock-agentcore-runtime-part-1/)
- [Introducing Amazon Nova 2 Sonic (AWS Blog)](https://aws.amazon.com/blogs/aws/introducing-amazon-nova-2-sonic-next-generation-speech-to-speech-model-for-conversational-ai/)
- [Amazon Bedrock AgentCore](https://aws.amazon.com/bedrock/agentcore/)

---

## Slide 20: Cảm ơn!

> Đó là toàn bộ những gì mình muốn chia sẻ hôm nay.

> Repo public trên GitHub — github.com/KenzyTran/hera. Demo URL mình để ở slide.

> Nếu mọi người muốn tự build, mình có workshop 5 chương song ngữ tiếng Việt và tiếng Anh, deploy từ đầu đến cuối trên AWS account của mình.

> Cảm ơn mọi người đã lắng nghe. Mình sẵn sàng nhận câu hỏi.

---

# PHỤ LỤC (Speaker reference — không lên slide)

---

## Phụ lục A: Tổng hợp chi phí Hera v1

| Resource | Idle | 1 giờ active demo |
|---|---|---|
| AgentCore Runtime | $0 | ~$0.10/h khi có session |
| Bedrock Nova 2 Sonic | $0 | ~$0.30 / 10 phút conversation |
| Bedrock KB Retrieve | $0 | ~$0.001 / query |
| CloudFront + S3 widget | ~$0 | ~$0 (low traffic) |
| Lambda presigner | $0 | $0 (free tier) |
| S3 Vectors storage | ~$0 (KB nhỏ <10 MB) | ~$0 |

**Total burst test: < $1/h. Idle overnight: < $0.05.**

Billing alarm `hera-billing-prod` (us-east-1) trigger khi cost > $5/ngày.

### Nguồn

- [Amazon Bedrock Pricing](https://aws.amazon.com/bedrock/pricing/)
- [AgentCore Pricing](https://aws.amazon.com/bedrock/agentcore/pricing/)
- [Amazon S3 Pricing](https://aws.amazon.com/s3/pricing/)
- [Amazon Nova Pricing](https://aws.amazon.com/nova/pricing/)

---

## Phụ lục B: Pipecat framework (nền tảng xuyên suốt)

> Pipecat là open-source Python framework cho voice + multimodal AI agents, tạo bởi Daily.co. Khoảng 10,900 GitHub stars, Apache 2.0 license.

> Kiến trúc pipeline: mọi dữ liệu (audio, text, signals) là typed Frame objects chạy qua chuỗi FrameProcessors. Mỗi processor chạy async riêng. Swap STT/LLM/TTS providers không cần thay đổi logic pipeline.

> AWS integration: `AWSNovaSonicLLMService` — first-class speech-to-speech service. `FastAPIWebsocketTransport` cho browser connections. Audio wire format: 16 kHz mono Int16 input, 24 kHz mono Int16 output.

> Hera dùng Pipecat v1.1.0. Latest là v1.2.1 (May 2026).

### Nguồn

- [Pipecat GitHub](https://github.com/pipecat-ai/pipecat)
- [Pipecat Docs](https://docs.pipecat.ai/getting-started/introduction)
- [AWS Nova Sonic Pipecat docs](https://docs.pipecat.ai/server/services/s2s/aws)
- [Deploy voice agents with Pipecat + AgentCore (AWS ML Blog)](https://aws.amazon.com/blogs/machine-learning/deploy-voice-agents-with-pipecat-and-amazon-bedrock-agentcore-runtime-part-1/)

---

## Phụ lục C: Code walkthrough — bảng tra nhanh

Dùng khi Q&A hỏi sâu về implementation. Không trình bày code trên slide.

| Concept | File | Lines |
|---|---|---|
| 3-route AgentCore HTTP contract | `agent/hera_agent/main.py` | 34-50, 72-96 |
| Nova Sonic LLM + 8-min rotate | `agent/hera_agent/pipeline.py` | 69-81 |
| Pipecat pipeline assembly | `agent/hera_agent/pipeline.py` | 131-137 |
| Raw PCM serializer | `agent/hera_agent/serializer.py` | 26-54 |
| KB retrieve (boto3) | `agent/hera_agent/tools.py` | 29-50 |
| Tool schema | `agent/hera_agent/tools.py` | 87-104 |
| System prompt persona | `agent/hera_agent/prompts.py` | 9-20 |
| S3 Vectors bucket + index | `infra/modules/knowledge_base/main.tf` | 26-51 |
| Bedrock KB → S3 Vectors wire | `infra/modules/knowledge_base/main.tf` | 57-85 |
| KB data source + chunking | `infra/modules/knowledge_base/main.tf` | 92-125 |
| AgentCore CfnRuntime | `infra/cdk/hera_agentcore/stack.py` | 93-110 |
| WSS URL construction | `infra/cdk/hera_agentcore/stack.py` | 114-131 |
| Lambda presigner SigV4 | `infra/modules/widget_presigner/src/handler.py` | 50-77 |
| Presigner IAM least-priv | `infra/modules/widget_presigner/main.tf` | 62-89 |
| CloudFront OAC | `infra/modules/widget_hosting/main.tf` | 31-37, 111-135 |
| Dashboard + alarms | `infra/modules/observability/main.tf` | 13-115 |
| AgentCore IAM (confused-deputy) | `infra/modules/agentcore_iam/main.tf` | 30-90 |
| Frontend presign fetch | `frontend/app.js` | 168-186 |
| Frontend audio playback queue | `frontend/app.js` | 218-245 |
| AudioWorklet downsample + batch | `frontend/audio-capture-worklet.js` | 14-79 |
| KB CLI smoke test | `bin/verify-kb.sh` | 78-83 |
| Sample catalog markdown | `catalog/macbook-pro-m4.md` | -- |

---

## Phụ lục D: Q&A — câu hỏi thường gặp

**"Tại sao không dùng OpenAI Realtime hoặc Gemini Flash Live?"**
> Cả 2 đều là speech-to-speech model tốt. AWS chọn Nova 2 Sonic vì native trên Bedrock — cùng credential, cùng region, cùng IAM policy với KB và AgentCore. Tooling, billing, observability tích hợp sẵn. Trade-off là vendor lock-in vào AWS, nhưng phù hợp với dự án đã chạy trên AWS.

**"AgentCore vs Lambda voice handler?"**
> Lambda max 15 phút — không đủ cho voice call dài. AgentCore tối đa 8 giờ. Lambda cũng không tối ưu cho long-running WebSocket. AgentCore là first-party agent runtime, có protocol contract sẵn cho voice.

**"Tại sao Pipecat thay vì viết tay?"**
> Pipecat đã xử lý sẵn các phần khó: barge-in detection, audio frame management, session continuation, event loop async. Viết tay từ đầu vẫn được nhưng tốn 2-3 tuần. Pipecat 1 ngày là chạy.

**"Cost thực sự bao nhiêu nếu scale lên 1000 user/ngày?"**
> Voice cost dominate — $0.017/phút × số phút conversation. KB query rẻ (~$0.001/query). AgentCore tính theo compute time thực, không idle. Lambda free tier đủ cho presigner. CloudFront/S3 cũng rẻ với traffic thấp. Bottleneck cost-wise sẽ là Nova Sonic — nhưng đó là phần tạo giá trị chính.

**"Twilio bridge có khả thi không?"**
> Có. Bridge code đã verified offline. Vấn đề là App Runner edge từ chối inbound WS — cần thử compute target khác (ECS Fargate + NLB, hoặc EC2). Đây là backlog item.

---

## Phụ lục E: Surprises & operational pitfalls (chi tiết — không lên slide)

Những thứ documentation không nói trước cho bạn. Để ở Phụ lục để Slide 19 tập trung vào bức tranh lớn; lấy ra khi Q&A hỏi sâu.

**Surprise 1 — Browser không ký được SigV4 cho WebSocket upgrade.** SigV4 cần AWS credentials, không thể đặt trong browser code. Giải pháp: Lambda Function URL làm presigner mint URL WSS đã ký, TTL 5 phút; sau đó audio chạy thẳng browser ↔ AgentCore, Lambda rời khỏi đường đi.

**Surprise 2 — Sonic 8-min stream cap.** Mỗi WebSocket connection tối đa 8 phút. Không handle thì conversation bị cắt đột ngột. Pipecat `SessionContinuationParams` rotate connection ở phút thứ 6, truyền chat history sang connection mới — người dùng không nhận ra.

**Surprise 3 — S3 Vectors metadata cap = 2 fields/document.** Ít hơn nhiều so với kỳ vọng. Nếu schema RAG cần nhiều metadata filter, phải biết trước giới hạn này.

**Surprise 4 — Langfuse tracing trên AgentCore.** Key Langfuse phải bake vào container lúc `cdk deploy` (không vá nóng bằng `update-agent-runtime`). AgentCore tự cắm OTel provider riêng → phải gắn exporter đúng cách; microVM đóng băng sau phiên → dùng `SimpleSpanProcessor` (export đồng bộ) thay vì batch. Trace hiện sau khi đóng phiên + ingest lag ~30-60s.

**Operational pitfalls:**
- **ECR IMMUTABLE tags + scan-on-push** — bảo vệ supply chain; image tag = git SHA, push lại cùng tag bị từ chối.
- **Billing alarm BẮT BUỘC ở us-east-1** — AWS chỉ emit metric `AWS/Billing` ở đó, bất kể resource chạy region nào.
- **CloudFront disable phải chờ 15-30 phút trước khi delete** — ngắt giữa chừng → distribution kẹt, không xóa được.
- **Terraform first apply** — root `infra/envs/prod` gom mọi module; observability cần runtime ARN (chưa tồn tại) → apply đầu phải `-target` để hoãn observability, apply thứ hai (có ARN) mới tạo nốt.

### Nguồn

- [HTTP protocol contract (docs)](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-http-protocol-contract.html)
- [CloudWatch Billing Alarms (docs)](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/monitor_estimated_charges_with_cloudwatch.html)
- [CloudFront Distribution Deletion (docs)](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/HowToDeleteDistribution.html)
