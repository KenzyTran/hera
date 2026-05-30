# Hera Evaluation

End-to-end quality evaluation for the Hera voice agent using **Amazon Bedrock
Prompt Management** (system prompt storage) and **Amazon Bedrock Evaluation**
(RAG quality scoring).

## Layout

```
evals/
├── golden-dataset.jsonl    # 20 Q&A samples (Bedrock RAG eval JSONL format)
└── README.md               # this file

infra/modules/bedrock_prompt/   # Terraform: stores system prompt in AWS
infra/modules/bedrock_eval/     # Terraform: S3 bucket + IAM role for eval jobs
bin/run-kb-eval.sh              # Imperative: launches an eval job
```

## What gets evaluated

The eval job runs in **RAG retrieve-and-generate** mode:

1. For each sample, Bedrock retrieves the top-3 chunks from the Hera KB
2. A text generator model (default: `amazon.nova-lite-v1:0`) composes an
   answer from those chunks — same KB the voice agent uses at runtime
3. A judge model (default: `amazon.nova-lite-v1:0`) scores each answer
   against the reference response on 5 built-in metrics:
   - **Correctness** — does the answer match the reference?
   - **Completeness** — does it cover all parts of the reference?
   - **Helpfulness** — would the answer be useful to a customer?
   - **Logical Coherence** — internal logical consistency
   - **Faithfulness** — does the answer stay grounded in retrieved context?

This evaluates the **RAG layer** (KB + generator) independently of Nova Sonic,
which is the right separation: Sonic is voice-only and not text-evaluable, but
the underlying KB + retrieve + generate pipeline IS the failure surface that
matters for answer quality.

## Golden dataset

20 samples covering:
| Category | Count | What it tests |
|---|---|---|
| MacBook Pro M4 questions | 5 | Stock, price, specs, battery |
| iPhone 13 Pro Max | 4 | Stock, price, colors, water resistance |
| Apple Watch Series 11 | 4 | Overview, pricing, battery, stock |
| Store policy | 3 | Returns, hours, warranty |
| Cross-product compare | 2 | Cheaper-than, cheapest option |
| Out-of-stock edge case | 1 | Correct "currently out of stock" answer |
| Non-Apple refusal | 1 | Persona-compliant 1-line refusal |

Format: one JSON record per line. Each record has `conversationTurns[]` with
`prompt` (user input) and `referenceResponses` (expected answer).

## Workflow

### One-time setup

```bash
# Apply Terraform — creates Bedrock Prompt resource + S3 bucket +
# IAM role and uploads the golden dataset.
terraform -chdir=infra/envs/prod apply
```

After apply:
- System prompt is in Bedrock console → Prompt Management →
  `hera-system-prompt-prod` (versioned)
- Golden dataset is uploaded to
  `s3://hera-evals-prod/datasets/golden-dataset.jsonl`

### Run an evaluation

```bash
bin/run-kb-eval.sh
```

Outputs the job ARN. Poll with:

```bash
aws bedrock get-evaluation-job \
  --region ap-northeast-1 \
  --job-identifier <ARN>
```

When the job completes (typically 5-15 minutes for 20 samples), result JSON
appears under `s3://hera-evals-prod/results/<job-id>/`.

### When to re-run

Run an evaluation:
- After changing the system prompt (`agent/hera_agent/prompts.py`)
- After updating the catalog (`catalog/*.md`) + re-running KB ingestion
- After tuning `KB_SCORE_THRESHOLD` or chunk parameters
- Before any production prompt change — for A/B baseline

## Updating the dataset

Edit `golden-dataset.jsonl` and re-apply Terraform — `aws_s3_object` re-uploads
on `filemd5` change. Then re-run `bin/run-kb-eval.sh`.

## Pricing note

Bedrock Evaluation charges per generator + judge invocation. With Nova Lite as
both, 20 samples ≈ a few cents per run. Switch to Claude Sonnet for higher-
quality judge at higher cost via `JUDGE_MODEL_ID=anthropic.claude-3-5-sonnet-20241022-v2:0`.
