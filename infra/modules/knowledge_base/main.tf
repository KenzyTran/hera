# --- S3 source bucket (markdown catalog) ---
# force_destroy = true so terraform destroy succeeds even with objects in the bucket (Pitfall E / Pitfall #20).
# Recovery from accidental destroy is git checkout + re-upload of catalog/*.md (RUNBOOK.md).

resource "aws_s3_bucket" "source" {
  bucket        = "${var.name_prefix}-kb-source-${var.env}"
  force_destroy = true
}

# Block ALL public access on the source bucket. Defense in depth — even if a future bucket
# policy were loosened, this blocks public reads/writes/ACLs at the account level.
resource "aws_s3_bucket_public_access_block" "source" {
  bucket = aws_s3_bucket.source.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- S3 Vectors bucket + index ---
# Pitfall G: argument is vector_bucket_name, NOT name.
# Pitfall H: data_type and distance_metric are LOWERCASE here (uppercase in the KB resource is a separate provider quirk).
# Pitfall B: dimension is IMMUTABLE post-create; changing it requires destroy + recreate.

resource "aws_s3vectors_vector_bucket" "this" {
  vector_bucket_name = "${var.name_prefix}-kb-vectors-${var.env}"
  force_destroy      = true
  # encryption_configuration omitted -> SSE-S3 (AES256) default
}

resource "aws_s3vectors_index" "this" {
  index_name         = "${var.name_prefix}-kb-index"
  vector_bucket_name = aws_s3vectors_vector_bucket.this.vector_bucket_name

  data_type       = "float32"
  dimension       = var.embedding_dimension
  distance_metric = "cosine"

  # Bedrock KB writes the chunk text into AMAZON_BEDROCK_TEXT and source
  # attribution into AMAZON_BEDROCK_METADATA. S3 Vectors caps total filterable
  # metadata at 2048 bytes per record, so chunks at the configured 300-token
  # max overflow that limit. Mark both keys non-filterable (we never filter
  # by them; we only retrieve them) to lift the size cap.
  metadata_configuration {
    non_filterable_metadata_keys = [
      "AMAZON_BEDROCK_TEXT",
      "AMAZON_BEDROCK_METADATA",
    ]
  }
}

# --- Bedrock Knowledge Base ---
# embedding_data_type is UPPERCASE here (FLOAT32) — provider inconsistency vs aws_s3vectors_index lowercase. Both are correct in their own context (Pitfall H).
# depends_on on the inline policy is required: KB validates role permissions at create time. Without this, Terraform may try to create the KB before the inline policy attaches and trigger a transient AccessDeniedException (RESEARCH.md Pattern 5 / Anti-Patterns).

resource "aws_bedrockagent_knowledge_base" "this" {
  name     = "${var.name_prefix}-kb-${var.env}"
  role_arn = aws_iam_role.kb_service_role.arn

  knowledge_base_configuration {
    type = "VECTOR"

    vector_knowledge_base_configuration {
      embedding_model_arn = "arn:aws:bedrock:${var.region}::foundation-model/amazon.titan-embed-text-v2:0"

      embedding_model_configuration {
        bedrock_embedding_model_configuration {
          dimensions          = var.embedding_dimension
          embedding_data_type = "FLOAT32"
        }
      }
    }
  }

  storage_configuration {
    type = "S3_VECTORS"

    s3_vectors_configuration {
      index_arn = aws_s3vectors_index.this.index_arn
    }
  }

  depends_on = [aws_iam_role_policy.kb_inline]
}

# --- Bedrock KB Data Source ---
# Wires the S3 source bucket to the KB. inclusion_prefixes scopes ingestion to the catalog/ prefix
# so other directory uses of the same bucket stay out of the KB.
# FIXED_SIZE chunking with 300 tokens / 20% overlap per D-04. Hierarchical chunking is rejected because parent-child links can blow the per-vector metadata overlay (Pitfall #8 / Anti-Patterns).

resource "aws_bedrockagent_data_source" "catalog" {
  name              = "${var.name_prefix}-catalog"
  knowledge_base_id = aws_bedrockagent_knowledge_base.this.id

  data_source_configuration {
    type = "S3"

    s3_configuration {
      bucket_arn         = aws_s3_bucket.source.arn
      inclusion_prefixes = ["catalog/"]
    }
  }

  vector_ingestion_configuration {
    chunking_configuration {
      chunking_strategy = "FIXED_SIZE"

      fixed_size_chunking_configuration {
        max_tokens         = var.chunk_max_tokens
        overlap_percentage = var.chunk_overlap_pct
      }
    }
  }

  # The AWS provider does not force-new this resource when knowledge_base_id
  # changes. When the KB is replaced (e.g. due to a force-new on the underlying
  # vector index), the data source must be recreated alongside it - the API
  # treats data sources as children of the KB and the old data source ID dies
  # with the old KB. Without this, terraform tries to UpdateDataSource on the
  # new KB ID with the dead data source ID and gets ResourceNotFoundException.
  lifecycle {
    replace_triggered_by = [aws_bedrockagent_knowledge_base.this]
  }
}
