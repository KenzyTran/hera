---
title: "3.3 Deploy AgentCore"
date: 2025-01-01
weight: 3
---

## Mục tiêu phần này

Build container multi-arch (linux/arm64,linux/amd64) + push lên ECR của bạn → `cdk deploy` AgentCore Runtime (CDK Python — D-24 hybrid IaC) → second-pass `terraform apply` để wire `widget_presigner` Lambda vào runtime ARN → `bin/smoke-deploy.sh` end-to-end gate. Sau bước này, agent đã chạy trên Bedrock AgentCore Runtime ở `ap-northeast-1` thay vì laptop của bạn.

## Hybrid IaC: Terraform + CDK Python (D-24)

Hera dùng đồng thời hai IaC tool theo phân vai rõ ràng:

- **Terraform `~> 6.27` quản lý mọi thứ TRỪ AgentCore Runtime resource:** Knowledge Base + S3 Vectors, IAM (kể cả AgentCore exec role), ECR, S3 widget bucket, CloudFront distribution, CloudWatch log group, observability dashboard + alarms, và `widget_presigner` Lambda. Lý do: AWS provider ở các area này có native support đầy đủ.
- **CDK Python (`infra/cdk/`) quản lý DUY NHẤT 1 resource — AgentCore Runtime:** `AWS::BedrockAgentCore::Runtime`. Đầu 2026, Terraform AWS provider chưa có resource native cho AgentCore Runtime → dùng CDK Python để bridge gap (D-24 Phase 3).
- **4-step lifecycle (D-25 amended Plan 03-04):** TF apply → push image → cdk deploy → second-pass TF apply. Bước cuối thêm vào vì `widget_presigner` Lambda cần Runtime ARN trong env var + IAM policy resource scope, nhưng Runtime do CDK tạo SAU TF first apply — chicken-and-egg solved bằng two-pass apply.
- **Same-artifact contract (AGT-08):** Phase 2 build local Dockerfile multi-arch (`linux/arm64,linux/amd64`); Phase 3 push CÙNG image lên AgentCore Runtime ARM64-only — không rebuild. Lockfile (`agent/uv.lock`) frozen verbatim cho production deploy.

## Bước 0: AgentCore concurrency mặc định (cap=10)

AgentCore default account quota = 10 concurrent runtimes/account. **Workshop của bạn dùng cap=10 mặc định không cần làm gì** — ở scale workshop session bạn sẽ không hit cap. Bỏ qua step này và tiếp tục Bước 1.

{{% notice info %}}
**Reference cho instructor (D-30 không áp dụng cho learner):** instructor demo URL chạy với D-30 concurrency cap=2 để cap cost. Nếu bạn (instructor) muốn replicate setup đó:

1. Mở `https://console.aws.amazon.com/servicequotas/home/services/bedrock-agentcore/quotas` ở `ap-northeast-1`.
2. Tìm "Concurrent runtime sessions" (hoặc tương tự).
3. Click "Request quota increase" → nhập 2 → Submit. AWS approve trong 1-2 ngày.

![Service Quotas — request AgentCore concurrency 2 (D-30, instructor reference)](/images/3.3-deploy-agentcore/service-quotas-agentcore-concurrency.png)

*Source: RUNBOOK.md + Phase 3 D-30 — Phase 3 Plan 03-04*
{{% /notice %}}

## Bước 1: Apply Terraform (KB + IAM + ECR + widget hosting)

Wave-1 apply tạo toàn bộ resource trừ AgentCore Runtime. Trên fresh deploy, `agentcore_runtime_arn` dùng giá trị empty-string default (placeholder ARN trong IAM policy của presigner) — sẽ được swap ở Bước 3.5.

```bash
cd infra/envs/prod
terraform init
terraform plan -out plan.out
terraform apply plan.out
cd ../../..
```

*Source: RUNBOOK.md (Phase 3 Step 1) — Phase 3 Plan 03-01*

Outputs Phase 3 thêm: `ecr_repo_url`, `agentcore_exec_role_arn`, `agentcore_log_group_arn`, `agentcore_log_group_name`, `widget_cloudfront_url`, `widget_s3_bucket_name`, `widget_cloudfront_distribution_id`. Phần 3.4 sẽ dùng các widget output để deploy frontend.

## Bước 2: Build + push container lên ECR (của bạn)

`bin/push-image.sh` đóng gói Phase 2 buildx invocation thành single paste-block. Cùng Dockerfile, cùng image artifact — chỉ khác registry đích là ECR thay vì local docker daemon.

```bash
bin/push-image.sh
```

*Source: bin/push-image.sh — Phase 3 Plan 03-03*

Script làm gì:

- Resolve `ecr_repo_url` từ `terraform output -raw ecr_repo_url`.
- Compute `git rev-parse --short HEAD` → image tag (ECR `imageTagMutability=IMMUTABLE` per Plan 03-01 — không dùng `:latest`).
- `aws ecr get-login-password | docker login` ECR registry của bạn.
- Tạo idempotent buildx builder `hera-builder` nếu chưa có.
- `docker buildx build --platform linux/arm64,linux/amd64 --provenance=false --sbom=false --push -t ${ECR_URL}:${GIT_SHA} ./agent`.
- `aws ecr describe-images --image-ids imageTag=${GIT_SHA}` confirm manifest list landed cho cả 2 arch.

Note quan trọng: `--provenance=false` + `--sbom=false` BẮT BUỘC. BuildKit v0.11+ default emit OCI in-toto attestation manifests — ECR manifest validator REJECT với `UnsupportedMediaTypeException` trên trailing attestation blob nếu không tắt 2 flag này.

## Bước 3: cdk deploy AgentCore Runtime

```bash
# Dump terraform outputs so the CDK app can read them (TF -> CDK bridge).
cd infra/envs/prod
terraform output -json > terraform-outputs.json
cd ../../..

# Provision/replace the AgentCore Runtime resource. Captures the runtime ARN
# in dist/cdk-outputs.json under hera-agentcore.AgentCoreRuntimeArn.
cd infra/cdk
GIT_SHA=$(git rev-parse --short HEAD)
uv run cdk deploy hera-agentcore --context image_tag=${GIT_SHA} --outputs-file ../../dist/cdk-outputs.json --require-approval never
cd ../..
```

*Source: RUNBOOK.md (Phase 3 Step 3) — Phase 3 Plan 03-04*

CDK chỉ quản lý 1 stack — `hera-agentcore` với resource `AWS::BedrockAgentCore::Runtime`. Output `AgentCoreRuntimeArn` ghi ra `dist/cdk-outputs.json`. Lưu ý: concurrency cap KHÔNG có ở schema CFn (verified `aws cloudformation describe-type` Plan 03-04) — service quota mới là gate (xem Bước 0 phía trên).

## Bước 3.5: Second-pass terraform apply

```bash
RUNTIME_ARN=$(jq -r '."hera-agentcore".AgentCoreRuntimeArn' dist/cdk-outputs.json)
cd infra/envs/prod
terraform apply -var "agentcore_runtime_arn=${RUNTIME_ARN}" -auto-approve
cd ../../..
```

*Source: RUNBOOK.md (Phase 3 Step 3.5) — Phase 3 Plan 03-04*

Chicken-and-egg: `widget_presigner` Lambda cần Runtime ARN trong env var + IAM policy resource scope, nhưng Runtime do CDK tạo SAU TF first apply. Solution two-pass: TF first apply dùng default empty-string placeholder ARN; second-pass apply (sau khi `cdk deploy` emit ARN) swap thành real ARN. `presign_url` output cũng chỉ populate được sau bước này.

## Bước 4: Smoke gate end-to-end (bin/smoke-deploy.sh)

`bin/smoke-deploy.sh` chạy lại toàn bộ Bước 1-4 trong 1 paste-block + thêm gate kiểm tra HTTPS + presigner + WSS smoke probe. Idempotent — re-run an toàn từ bất kỳ failure point nào.

```bash
bin/smoke-deploy.sh
```

*Source: bin/smoke-deploy.sh — Phase 3 Plan 03-04*

Script làm gì:

1. `terraform output -json > terraform-outputs.json` (CDK đọc).
2. `cdk deploy hera-agentcore` (idempotent — second run no-op nếu image tag không đổi).
3. Extract `AgentCoreRuntimeArn` từ `dist/cdk-outputs.json`.
4. Second-pass `terraform apply -var=agentcore_runtime_arn=<arn>`.
5. Read `presign_url` output, export thành `PRESIGN_URL`.
6. `bin/build-widget.sh` (sed-inject + s3 sync + invalidate — chi tiết ở Phần 3.4).
7. `curl -fsS https://<cloudfront-domain>/` HTTPS reachability gate (DEM-01 verify).
8. `curl -fsS ${PRESIGN_URL}` presigner gate (expects `{"url": "wss://..."}`).
9. `uv run python bin/_smoke_deploy_probe.py` — open WSS, send 1s synthetic 16 kHz Int16 silence, assert >=1 inbound binary frame within 10s.

Success ends with:

```
OK: Phase 3 smoke passed.
    Widget URL  : https://<your-distribution>.cloudfront.net
    Presign URL : https://<your-fn-url>.lambda-url.ap-northeast-1.on.aws/
    Runtime ARN : arn:aws:bedrock-agentcore:ap-northeast-1:<your-account>:runtime/...
    Image tag   : <git-sha>
```

## POST /invocations: AgentCore HTTP protocol contract (Phase 4 Plan 04-01)

```python
@app.post("/invocations")
async def invocations() -> JSONResponse:
    """AgentCore HTTP data-plane stub. Voice loop runs on /ws (D-31)."""
    return JSONResponse(
        {
            "agent": "hera-pipecat-sonic",
            "status": "running",
            "model": "amazon.nova-sonic-v1:0",
        }
    )
```

*Source: agent/hera_agent/main.py — Phase 4 Plan 04-01*

AgentCore HTTP protocol mặc định gọi container ở `POST /invocations` per Bedrock convention (chọn bởi `ProtocolConfiguration: HTTP` trong CDK stack Phase 3). Voice loop thật chạy ở `/ws` (Pipecat WebSocket transport) — `/invocations` chỉ là static envelope stub để satisfy AgentCore data-plane invocation API trả về 200.

Plan 04-01 deploy Runtime version=3 status=READY referencing image `hera-agent:7e72b66`, đóng Phase 3 SC#2 (data-plane invoke trả về `statusCode=200`).

## Live state (instructor reference)

- Account: `851725411875` (instructor; bạn dùng account của bạn).
- Region: `ap-northeast-1`.
- Runtime: `hera_agent-GIsf2P4ImD` (instructor's; `cdk deploy` của bạn tạo runtime mới).
- Live URL: `https://dg0w939ktclw6.cloudfront.net/` (instructor demo).
- Cost active: AgentCore Runtime + Sonic streaming theo D-54 ballpark `~$2-5 USD per 2-hour session`. Số liệu per-service breakdown chính xác sẽ cập nhật post-launch sau khi instructor pull 24h Cost Explorer data từ một workshop session thực tế.

## Cleanup order

```bash
# Tear down CDK first, then Terraform.
cd infra/cdk && uv run cdk destroy hera-agentcore --force && cd ../..
cd infra/envs/prod && terraform destroy && cd ../..
```

*Source: RUNBOOK.md (Phase 3 Cleanup order) — Phase 3 Plan 03-04*

Chi tiết cleanup (kèm `bin/cleanup-verify.sh` và 24h Cost Explorer paste-line) ở Phần 4. CDK trước vì AgentCore Runtime giữ IAM exec role mà Terraform quản lý — reverse order → `terraform destroy` fail vì policy còn attach và role còn in-use.

## Tiếp theo

AgentCore Runtime đang chạy ở `ap-northeast-1`, nhưng chưa có UI cho người dùng. Phần 3.4 sẽ deploy widget HTML/JS lên S3+CloudFront (đã setup ở Bước 1), sed-inject `__PRESIGN_URL__`, và bạn sẽ mở URL HTTPS trong browser để test voice loop end-to-end.
