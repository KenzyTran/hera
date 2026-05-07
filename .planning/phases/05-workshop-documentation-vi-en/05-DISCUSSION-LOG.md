# Phase 5: Workshop Documentation (vi/en) - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-07
**Phase:** 5-workshop-documentation-vi-en
**Areas discussed:** Granularity Phần 3 Hands-on, Snippet drift discipline, Screenshot strategy, Region + build vs pre-built image, vi/en authoring + parity script

---

## Granularity Phần 3 Hands-on

| Option | Description | Selected |
|--------|-------------|----------|
| 5 trang con riêng (Recommended) | content/{vi,en}/3-hands-on/{3.1-knowledge-base, 3.2-pipecat-local, 3.3-deploy-agentcore, 3.4-web-widget, 3.5-observability}/_index.md. Tổng 12 file dưới Phần 3. Mỗi sub-step có next/prev, sidebar tách riêng, parity check dễ. | ✓ |
| 1 trang dài Phần 3 | content/{vi,en}/3-hands-on/_index.md gom 5 sub-step với heading H2. Tổng 2 file. Đơn giản nhất, scroll dài, không có next-prev giữa sub-step. | |
| Nhóm 3 trang | KB+Pipecat-local trong 3.1, Deploy+Widget trong 3.2, Observability đứng riêng. Tổng 6 file. Cân bằng readability vs nav granularity. | |

**User's choice:** 5 trang con riêng
**Notes:** D-40 trong CONTEXT.md — slug convention `<chapter>.<sub>-<slug>` matches existing `1.1-prerequisites.md`.

---

## Phần 2 + các Phần khác — single-page hay split

| Option | Description | Selected |
|--------|-------------|----------|
| 1 trang dài Phần 2 (Recommended) | content/{vi,en}/2-preparation/_index.md duy nhất với H2 sections. Phần 2 ngắn hơn Phần 3, split không đáng. | ✓ |
| Split 2.1-2.3 | content/{vi,en}/2-preparation/{2.1-aws-account-setup, 2.2-toolchain, 2.3-cost-expectation}/. Sidebar nav rõ hơn, 6 file con thay vì 2. | |
| Hybrid: tất cả Phần khác single, chỉ Phần 3 split | Phần 1/2/4/5 single, chỉ Phần 3 sub. Total ~28 file. | |

**User's choice:** 1 trang dài Phần 2
**Notes:** D-41 trong CONTEXT.md — Phần 1, 2, 4, 5 đều single-page. Total 28 markdown files.

---

## Snippet drift discipline

| Option | Description | Selected |
|--------|-------------|----------|
| Inline + footer reference (Recommended) | Snippet copy-paste, footer 'Source: agent/hera_agent/main.py (Phase 2 Plan 02-01)'. Readable nhất, drift risk thấp vì source frozen post-Phase 4. | ✓ |
| Hugo readFile shortcode | Custom shortcode đọc từ source path lúc build. Zero drift, nhưng granularity file-level + theme deprecated không hỗ trợ line range, cần custom layout. | |
| CI extract+grep gate | Snippet inline + comment marker `# SOURCE: <path> # END-SOURCE`. CI script grep ngược vào source, fail PR nếu lệch. Drift safety cao nhất, add 1 script + cognitive overhead. | |

**User's choice:** Inline + footer reference
**Notes:** D-42 + D-43 trong CONTEXT.md — footer path là repo-relative, không dùng GitHub permalink với SHA.

---

## Screenshot strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Minimal: chỉ UI bắt buộc + 2-3 hero (Recommended) | Screenshot chỉ chỗ buộc phải dùng console (Bedrock model access, Billing Alerts, AgentCore quota) + 2-3 hero (widget UI, dashboard, cleanup-verify output). ~10-15 ảnh tổng. Ít maintenance. | ✓ |
| Full UI walkthrough | Mỗi bước Phần 2+3 có screenshot (~50-80 ảnh). Friendly cho beginner, nhưng AWS Console UI đổi 3-6 tháng/lần → maintenance burden lớn. Conflict với CLI-first tone. | |
| Hybrid: GIF/video cho complex flow | Minimal screenshot + record GIF/short MP4 cho 2-3 complex flow. Nặng hơn về file size + maintenance. | |

**User's choice:** Minimal screenshots
**Notes:** D-44 + D-45 + D-46 trong CONTEXT.md — inventory locked: 3 mandatory Console + 3 hero + 2-4 supporting. Storage path `static/images/<chapter>/`. No GIF/video.

---

## Region default cho learner

| Option | Description | Selected |
|--------|-------------|----------|
| ap-northeast-1 (giống instructor) (Recommended) | Snippet copy-paste 1:1 với infra/envs/prod hiện tại, screenshot region selector đúng. Sonic+AgentCore+KB ở ap-northeast-1. Latency VN tốt nhất. Trả giá: latency cao hơn cho non-APAC. | ✓ |
| us-east-1 | Region phổ biến nhất, free-tier dominant. Snippet phải chỉnh region tag, screenshot khác. Latency VN cao hơn ~150ms (ảnh hưởng AGT-04 budget?). | |
| Parametrize: learner pick | Snippet dùng REGION=ap-northeast-1 placeholder, hướng dẫn check Sonic available regions + chọn nearest. Linh hoạt nhưng workshop dài hơn + dễ trượt. | |

**User's choice:** ap-northeast-1 (giống instructor)
**Notes:** D-47 trong CONTEXT.md — note 1 dòng trong Phần 1 Architecture cho non-APAC learners để biết các region khác cũng support.

---

## Container: build vs pre-built image

| Option | Description | Selected |
|--------|-------------|----------|
| Learner tự build + push ECR (Recommended) | bin/push-image.sh chạy từ account của learner; multi-arch buildx → learner's ECR repo. Cần Docker Desktop. Full understanding: Dockerfile, uv lock, ENV bake-in, --provenance=false. Đúng workshop core promise. | ✓ |
| Pull instructor's public ECR image | Instructor publish image tới public ECR. Learner skip build, deploy nhanh nhất. Cần setup public repo policy + lộ instructor account ID. Đổi bản chất SC#2: không thật sự 'their own deploy'. | |
| Hybrid: build mặc định, pull fallback | Phần 3.3 main path = build. Sidebar 'Stuck on docker buildx?' callout fallback pull. Cân bằng nhưng cần duy trì cả hai path + làm public ECR. | |

**User's choice:** Learner tự build + push ECR
**Notes:** D-48 trong CONTEXT.md — không hybrid fallback v1; Phần 2 list Docker Desktop là tool gate.

---

## vi/en authoring order

| Option | Description | Selected |
|--------|-------------|----------|
| vi-first → translate en (Recommended) | User viết tiếng Việt native, Claude/dịch sang en sau. Mỗi plan ship cả hai lang trong 1 commit — CI parity check chặn merge nếu thiếu lang. Phù hợp tốc độ user. | ✓ |
| en-first → vi | Code, log, banner đều en — en-first giữ terminology consistent với source. Sau đó dịch vi. Có thể less natural cho audience VN. | |
| Parallel: viết song song từng chapter | Mỗi chapter viết cả hai lang cùng turn. Tốn thời gian hơn nhưng đồng bộ nhất. | |

**User's choice:** vi-first → translate en
**Notes:** D-49 trong CONTEXT.md — vi+en cho 1 chapter là 1 atomic commit để parity check không trip.

---

## DOC-12 CI parity check shape

| Option | Description | Selected |
|--------|-------------|----------|
| Minimal: count file (Recommended) | Bash đếm số _index.md vs sub-page dưới content/vi vs content/en, fail nếu không bằng. Bắt 'quên tạo file lang kia'. Không catch 'vi 5 section, en 3 section'. | ✓ |
| Per-file heading parity | Đếm `## ` trong từng file vi vs en, fail nếu lệch. Catch 'dịch thiếu section'. False positive khi heading được re-word. | |
| Shortcode-aware | Pitfall callout {{% notice %}} + code block footer phải có ở cả hai. Strict nhất, chặn 'quên dịch pitfall'. Add ~30 dòng bash + maintenance. | |

**User's choice:** Minimal file-count parity
**Notes:** D-50 trong CONTEXT.md — script `bin/check-i18n-parity.sh`, ~20 dòng bash, wired vào `.github/workflows/deploy.yml` pre-build step.

---

## Claude's Discretion

Captured in CONTEXT.md `<decisions>` → "Claude's Discretion" subsection. Highlights:
- Plan wave structure (one plan per chapter? per language? mega-plan?).
- Hugo front-matter shape per file.
- Whether `i18n/{vi,en}.toml` needs new keys.
- Exact Mermaid diagram source for D-55 (researcher sketches from RUNBOOK + Phase 3/4 SUMMARY).
- Translation cadence within a single plan.
- Whether `bin/check-i18n-parity.sh` lands first or with first chapter.
- Whether `1.1-prerequisites.md` is repurposed or removed.

## Deferred Ideas

Captured in CONTEXT.md `<deferred>` section. Highlights:
- Hugo theme migration `learn` → `relearn` (v2).
- Custom code-include shortcode + CI extract+grep (v2 if drift becomes painful).
- Pull instructor's public ECR fallback (v2 if needed).
- us-east-1 / parametrized region (v2 expansion).
- Full UI walkthrough screenshots / GIF / video (v2 if learner feedback demands).
- Per-section heading parity / shortcode-aware parity in DOC-12 (v2 if half-translated PRs become a problem).
- Twilio / Cognito SSO / ECS Fargate alternative / multi-agent / language-detection chapters (v2 per PROJECT.md).
- Pre-built CMS (out of scope).
- Re-publishing original ElevenLabs+n8n+Gemini transcript (origin material, not workshop content).
