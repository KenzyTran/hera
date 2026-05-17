# Hera — Voice agent on Amazon Bedrock AgentCore Runtime

Demo voice agent + bilingual (vi/en) workshop cho FCJ (First Cloud Journey). Người dùng nói qua microphone trên trình duyệt, agent trả lời bằng giọng nói, có RAG hỗ trợ từ một Apple Store knowledge base nhỏ.

**Stack:** Amazon Nova 2 Sonic (speech-to-speech) · Pipecat 1.2.1 · Amazon Bedrock AgentCore Runtime · Bedrock Knowledge Base + S3 Vectors + Titan v2 embeddings · CloudFront + S3 widget · Lambda SigV4 presigner. Tuỳ chọn: Langfuse cloud cho waterfall tracing.

Kiến trúc đầy đủ: [`docs/architecture-aws.drawio`](docs/architecture-aws.drawio)

---

## Repo layout

```
agent/                Pipecat voice agent (FastAPI on AgentCore Runtime)
frontend/             Browser widget (vanilla JS + AudioWorklet)
infra/
  envs/prod/          Terraform root (KB, S3 Vectors, IAM, CloudFront, Lambda, ECR, observability)
  modules/            Reusable TF modules (knowledge_base, agentcore_iam, widget_hosting, ...)
  cdk/                CDK app -- single resource: AgentCore Runtime
bin/                  Build, deploy, smoke-test scripts (push-image, build-widget, cleanup-verify, ...)
content/              Workshop chapters (vi + en mirrored, hugo-theme-learn)
docs/                 Architecture diagram, observability ops guide
.planning/            GSD planning artifacts (ROADMAP, REQUIREMENTS, phase plans, STATE)
```

---

## Workshop

5 chương song ngữ vi/en theo format FCJ:

1. **Introduction** -- bối cảnh, kiến trúc, conventions
2. **Preparation** -- AWS account setup, tools (uv, terraform, cdk, docker)
3. **Hands-on** -- 5 sections: knowledge base, Pipecat local, deploy AgentCore, widget, observability (CloudWatch + alarm; optional Langfuse waterfall tracing)
4. **Cleanup** -- `cdk destroy` + `terraform destroy` + `bin/cleanup-verify.sh` (20 read-only checks)
5. **Summary** -- recap + extensions

Workshop chạy local bằng:

```bash
hugo server -D --bind 0.0.0.0
```

Bilingual parity được CI kiểm tra qua `bin/check-i18n-parity.sh` (DOC-12).

---

## Deploy production (operator)

```bash
# 1. Terraform: KB + IAM + ECR + CloudFront + Lambda
cd infra/envs/prod && terraform apply

# 2. Build + push agent image to ECR
cd ../../.. && bash bin/push-image.sh

# 3. CDK deploy AgentCore Runtime (binds to TF-managed image + role)
cd infra/cdk && uv run cdk deploy hera-agentcore --context image_tag=<short-git-sha>

# 4. (Optional) Set Langfuse keys for waterfall tracing
source .env.langfuse  # gitignored; create manually with keys from cloud.langfuse.com
aws bedrock-agentcore-control update-agent-runtime ... --environment-variables "..,LANGFUSE_PUBLIC_KEY=$LANGFUSE_PUBLIC_KEY,LANGFUSE_SECRET_KEY=$LANGFUSE_SECRET_KEY,LANGFUSE_HOST=$LANGFUSE_HOST"

# 5. Build widget + sync to CloudFront origin
cd ../.. && bash bin/build-widget.sh
```

Ops guide chi tiết về tracing + log: [`docs/OBSERVABILITY.md`](docs/OBSERVABILITY.md)

---

## Destroy (zero cost)

```bash
cd infra/cdk && uv run cdk destroy hera-agentcore --force
aws s3 rm s3://hera-kb-source-prod --recursive
aws s3 rm s3://hera-widget-prod --recursive
aws ecr batch-delete-image --repository-name hera-agent --image-ids "$(aws ecr list-images --repository-name hera-agent --query 'imageIds[*]' --output json)"
cd ../envs/prod && terraform destroy
cd ../../.. && bash bin/cleanup-verify.sh  # expects 20/20 PASS
```

---

## License

Workshop content + scaffolding cho mục đích giáo dục. Code agent / infra modules dùng giấy phép tương ứng của upstream (Pipecat: BSD-2-Clause; hugo-theme-learn: MIT).
