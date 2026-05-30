#!/usr/bin/env bash
# Run a Bedrock Knowledge Base evaluation (retrieve-and-generate) against the
# Hera KB using the golden dataset uploaded by infra/modules/bedrock_eval.
#
# Usage:
#   bin/run-kb-eval.sh                 # uses Terraform outputs from infra/envs/prod
#   bin/run-kb-eval.sh --name my-eval  # custom job name
#
# Prerequisites:
#   - `terraform -chdir=infra/envs/prod apply` has been run (creates S3 bucket,
#     IAM role, and uploads evals/golden-dataset.jsonl)
#   - AWS CLI v2 with bedrock evaluation create-evaluation-job support
#   - Default profile or AWS_PROFILE configured with permission to call
#     bedrock:CreateEvaluationJob in the region

set -euo pipefail

REGION="${AWS_REGION:-ap-northeast-1}"
JOB_NAME="hera-kb-eval-$(date +%Y%m%d-%H%M%S)"
GENERATOR_MODEL_ID="${GENERATOR_MODEL_ID:-amazon.nova-lite-v1:0}"
JUDGE_MODEL_ID="${JUDGE_MODEL_ID:-amazon.nova-lite-v1:0}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) JOB_NAME="$2"; shift 2 ;;
    --region) REGION="$2"; shift 2 ;;
    --generator) GENERATOR_MODEL_ID="$2"; shift 2 ;;
    --judge) JUDGE_MODEL_ID="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

cd "$(dirname "$0")/.."

# Resolve infra outputs (single terraform call to amortize cost).
TF_OUTPUTS_JSON="$(terraform -chdir=infra/envs/prod output -json)"

KB_ID="$(echo "$TF_OUTPUTS_JSON" | jq -r '.kb_id.value')"
DATASET_URI="$(echo "$TF_OUTPUTS_JSON" | jq -r '.eval_dataset_s3_uri.value')"
RESULTS_PREFIX="$(echo "$TF_OUTPUTS_JSON" | jq -r '.eval_results_s3_uri_prefix.value')"
ROLE_ARN="$(echo "$TF_OUTPUTS_JSON" | jq -r '.eval_role_arn.value')"

for v in KB_ID DATASET_URI RESULTS_PREFIX ROLE_ARN; do
  if [[ -z "${!v}" || "${!v}" == "null" ]]; then
    echo "Missing terraform output: $v" >&2
    echo "Did you run: terraform -chdir=infra/envs/prod apply ?" >&2
    exit 1
  fi
done

GENERATOR_MODEL_ARN="arn:aws:bedrock:${REGION}::foundation-model/${GENERATOR_MODEL_ID}"
JUDGE_MODEL_ARN="arn:aws:bedrock:${REGION}::foundation-model/${JUDGE_MODEL_ID}"

echo "Launching Bedrock KB evaluation:"
echo "  job_name   : $JOB_NAME"
echo "  region     : $REGION"
echo "  kb_id      : $KB_ID"
echo "  generator  : $GENERATOR_MODEL_ID"
echo "  judge      : $JUDGE_MODEL_ID"
echo "  dataset    : $DATASET_URI"
echo "  results    : $RESULTS_PREFIX"
echo "  role       : $ROLE_ARN"
echo

EVAL_CONFIG=$(cat <<JSON
{
  "automated": {
    "datasetMetricConfigs": [
      {
        "taskType": "QuestionAndAnswer",
        "dataset": {
          "name": "hera-golden",
          "datasetLocation": {"s3Uri": "$DATASET_URI"}
        },
        "metricNames": [
          "Builtin.Correctness",
          "Builtin.Completeness",
          "Builtin.Helpfulness",
          "Builtin.LogicalCoherence",
          "Builtin.Faithfulness"
        ]
      }
    ],
    "evaluatorModelConfig": {
      "bedrockEvaluatorModels": [{"modelIdentifier": "$JUDGE_MODEL_ARN"}]
    }
  }
}
JSON
)

INFERENCE_CONFIG=$(cat <<JSON
{
  "ragConfigs": [
    {
      "knowledgeBaseConfig": {
        "retrieveAndGenerateConfig": {
          "type": "KNOWLEDGE_BASE",
          "knowledgeBaseConfiguration": {
            "knowledgeBaseId": "$KB_ID",
            "modelArn": "$GENERATOR_MODEL_ARN"
          }
        }
      }
    }
  ]
}
JSON
)

OUTPUT_CONFIG=$(cat <<JSON
{"s3Uri": "$RESULTS_PREFIX"}
JSON
)

JOB_ARN="$(aws bedrock create-evaluation-job \
  --region "$REGION" \
  --job-name "$JOB_NAME" \
  --role-arn "$ROLE_ARN" \
  --application-type "RagEvaluation" \
  --evaluation-config "$EVAL_CONFIG" \
  --inference-config "$INFERENCE_CONFIG" \
  --output-data-config "$OUTPUT_CONFIG" \
  --query 'jobArn' --output text)"

echo "Evaluation job submitted:"
echo "  $JOB_ARN"
echo
echo "Poll status with:"
echo "  aws bedrock get-evaluation-job --region $REGION --job-identifier $JOB_ARN"
echo
echo "Results appear under: $RESULTS_PREFIX (subfolder named after the job id)"
